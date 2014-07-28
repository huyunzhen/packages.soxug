#!/bin/sh /usr/share/centrifydc/perl/run

################################################################################
#
# Copyright (C) 2009 Centrify Corporation
# 
# get crl for a given cert
# this is a callback from openssl via racoon 
# see rac_get_crl in crypto_openssl.c for explanation
################################################################################


use strict;
use lib '/usr/share/centrifydc/perl';
use lib '/usr/share/centrifydc/perl/URI';

use CentrifyDC::Config;
use CentrifyDC::Logger;
use CentrifyDC::GP::General qw(RunCommand GetTempDirPath);
use CentrifyDC::GP::CertUtil qw(GetFingerprint);
use Date::Parse;
use File::Copy;
use URI;

my $tempdir = GetTempDirPath(0);
defined($tempdir) or FATAL_OUT();


my $certstore = $CentrifyDC::Config::properties{"adsec.cert.dir"};
if (!defined($certstore))
{
    $certstore = "/var/centrify/net/certs";
}

my $retrytime = $CentrifyDC::Config::properties{"adsec.crl_getter.retrytime"};
if (!defined($retrytime))
{
    $retrytime = 4 * 60;#minutes
}
$retrytime = $retrytime * 60;

my $curltime = $CentrifyDC::Config::properties{"adsec.crl_getter.timeout"};
if (!defined($curltime))
{
    $curltime = 30; #seconds
}
$curltime = 1 * $curltime;

my $logger = CentrifyDC::Logger->new('adsec');
my $curl = "/usr/share/centrifydc/bin/curl";
my $ldapsearch = "/usr/share/centrifydc/bin/ldapsearch";
my $tempcrl = "$tempdir/rac_temp_crl";
my $openssl = "/usr/share/centrifydc/bin/openssl";

# cert for which we are getting a crl
my $incert = $ARGV[0];
# path where we should put crl
my $outcrl = $ARGV[1];
#should we fetch missing crls
my $fetch = $ARGV[2];
my $rc;
my $out;
my $subject;

($rc, $subject) = RunCommand("${openssl} x509 -in '${incert}' -noout -subject");
$logger->log('DEBUG', "fetch crl for ${subject}");

my $fingerprint = GetFingerprint("$incert", 'PEM');
if (!defined($fingerprint))
{
   $logger->log('DEBUG', "cannot get fingerprint for ${incert}");
   exit(9);
}
chomp($fingerprint);

my $crlpath = "${certstore}/trust_${fingerprint}.crl";
my $update ;
# ok - first , do we already have one
# or did we previoulsy try and fail (empty crl in this case)
my @testcrl = stat("${crlpath}");
if(@testcrl)
{
   if($testcrl[7] == 0) #size
   {
      # this means we have previously tried to fetch the crl and failed
      $logger->log('DEBUG', "got fail marker for ${subject}");
      my $got = $testcrl[9]; #mtime
      if(time() - $got < $retrytime)
      {
         exit(2);
      }
      $logger->log('DEBUG', "but its old so retry");
      unlink($crlpath);
   }
   else
   {
      # we already got one, is it out of date?
      ($rc, $update) = RunCommand("${openssl} crl -in ${crlpath} -noout -nextupdate");
      if($rc)
      {
         $logger->log('DEBUG', "cant read date for  ${crlpath}");
         exit(9);
      }
      chomp($update); #note this var is used later
      $update =~ s/nextUpdate=//;
      my $dt = Date::Parse::str2time($update);
      if($dt > time())
      {
         $logger->log('DEBUG', "return cached crl for ${subject}");
	 if($outcrl)
	 {
             copy($crlpath, $outcrl);
	 }
         exit(0);
      }
      $logger->log('DEBUG', "refresh crl for ${subject}");
   }
}

# we dont have one or its old - so go get it
# get its crl url. 
#
($rc, $out) = RunCommand("${openssl} x509 -in '${incert}' -text");
if($rc)
{
   $logger->log('DEBUG', "cannot read info for ${subject}");
   exit(9);
}
my @temp = split /\n/, $out;
my @http_url = grep /^\s*URI:http:/, @temp;
my @ldap_url = grep /^\s*URI:ldap:/, @temp;
if(@http_url == 0 && @ldap_url == 0)
{
   # no CRL URL!
   $logger->log('DEBUG', "no HTTP or LDAP CRL URL in ${subject}");
   exit(1);
}
if(!$fetch)
{
   copy("$incert", "$tempdir/asynch_crl_fetch_${fingerprint}.crl");
   exit(3); #wanted to fetch it but were told not to
}
my $crl;
if(@http_url)
{
    $crl = $http_url[0];
    $crl =~ s/^\s*URI://;
    $logger->log('DEBUG', "fetch ${crl}");
    ($rc, $out) = RunCommand("${curl} -o ${tempcrl} -m ${curltime} '${crl}'");
}
else
{
    $crl = $ldap_url[0];
    $crl =~ s/^\s*URI://;

    $logger->log('DEBUG', "fetch ${crl}");

    my $uri = URI->new($crl);
    unless($uri->scheme eq "ldap" && defined($uri->dn) && defined($uri->scope)
        && defined($uri->filter) && defined($uri->attributes))
    {
        $logger->log('DEBUG', "LDAP URI parse error: '${crl}'");
        exit(1);
    }

    my $host = $uri->host;
    my $dn = $uri->dn;
    my $scope = $uri->scope;
    my $filter = $uri->filter;
    my $attribute = $uri->attributes; # There should be only one attribute.

    if($host eq "")
    {
        $host = `adinfo -r`;
        chomp($host);
    }

    #
    # Make sure the rename() succeeds by putting the ldapsearch
    # temporary file into the same directory as the temporary crl
    # file.
    #
    ($ENV{'TMPDIR'} = $tempcrl) =~ s{/[^/]*$}{};

    ($rc, $out) = RunCommand("${ldapsearch} -r -t -Q -m -h '$host' -b '$dn' -s $scope '$filter' '$attribute'");
    if($rc == 0)
    {
        my @lines = split(/\n/, $out);
        my @results = grep(/^$attribute:/, @lines);
        (my $file = $results[0]) =~ s{^$attribute:< file://}{};

        unless(rename(${file}, ${tempcrl}))
        {
            $logger->log('DEBUG', 'could not rename temporary crl file: $!');
            exit(1);
        }
    }
}

if($rc)
{
   $logger->log('DEBUG', "could not fetch crl for ${crlpath}");
   #if we have old crl keep it
   if(!$update)
   {
      unlink ($crlpath);
      ($rc, $out) = RunCommand("touch ${crlpath}");
      exit(9) if ($rc);
      chmod 0444, $crlpath;
      exit(2);
   }
}

# we got it in DER format - convert to PEM
# maybe we should check that its the right CRL
($rc, $out) = RunCommand("${openssl} crl -in ${tempcrl} -inform DER -out ${crlpath}");
if($rc)
{
   $logger->log('DEBUG', "could not process crl fetched from ${crl}, maybe crl server not setup correctly");
   exit(2);
}
unlink($tempcrl);
chmod 0444, $crlpath;
if ($outcrl)
{
    copy($crlpath, $outcrl) or exit(9);
}
$logger->log('DEBUG', "fetched crl for ${subject}");
exit(0);
