#!/bin/sh /usr/share/centrifydc/perl/run

# Copyright (C) 2009-2014 Centrify Corporation. All rights reserved.
#
# Machine/user mapper script
#

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug CreateDir);
use CentrifyDC::GP::Lock;
use CentrifyDC::GP::Registry;
use CentrifyDC::GP::RegHelper;
use CentrifyDC::GP::General qw(RunCommand GetTempDirPath);
use CentrifyDC::GP::GPIsolation qw(GetRegKey);
use CentrifyDC::GP::CertUtil qw(GetFingerprint);

use File::Glob qw(:glob csh_glob);
use File::Basename;


my $tempdir = GetTempDirPath(0);
defined($tempdir) or FATAL_OUT();


my $adcert = "/usr/share/centrifydc/sbin/adcert";
my $openssl = "/usr/share/centrifydc/bin/openssl";
my $curl = "/usr/share/centrifydc/bin/curl";
my $ldapsearch = "/usr/share/centrifydc/bin/ldapsearch";
my $c_rehash = "/usr/share/centrifydc/bin/c_rehash";

# c_rehash needs this environment variable for openssl binary
$ENV{OPENSSL} = $openssl;

my $enrollreg = GetRegKey("AutoEnroll");
my $trustreg = GetRegKey("TrustedRootCA");
my $certcontainers = $CentrifyDC::Config::properties{"adsec.cert.containers"};
my $ret;
my $hash;
my $out;
my $count;

my $CERTSTORE;

if (!defined($certcontainers))
{
    $certcontainers = "AIA,Certification Authorities,Enrollment Services,NTAuthCertificates";
}

# create a new Args for a mapper that can be both machine and user mapper
my $args = CentrifyDC::GP::Args->new();

# this will be undef if running as machine mapper
my $user = $args->user();

CentrifyDC::GP::Registry::Load($user);

$CERTSTORE = CentrifyDC::Config::GetCertStore($user);

if ($args->class() eq "user")
{
    DEBUG_OUT("Running as user mapper [$user]");
}
else
{
    DEBUG_OUT("Running as machine mapper");
}

if ($args->isMap())
{
    # make sure download dir exists
    CreateDir(${CERTSTORE}, $user);

    if ($args->class() eq "machine")
    {
        # step 1 make sure local copy of policy defined trust certs are up to date.
        # we might need to get certs from other places too
        #
	my @rootCerts = csh_glob("${CERTSTORE}/trust_*.cert");
	my $connectstate = `adinfo -m`;
	chomp($connectstate);
	if ($connectstate eq 'connected')
	{
	    unlink @rootCerts;
	}

	@rootCerts = CentrifyDC::GP::Registry::GetSubKeys($trustreg, "current", undef);

	foreach my $cname  (@rootCerts)
	{
            # blob contains the cert info
            my @ckey = CentrifyDC::GP::Registry::Query("machine", $cname, "current", "blob");
            my $cert = DecodeCertBlob($ckey[1]);

            if (defined($cert))
	    {
                # write temp copy in der format
		open CERT, ">${CERTSTORE}/temp.der";
		binmode CERT;
		print CERT $cert;
		close CERT;
		InstallCert("${CERTSTORE}/temp.der");
		unlink "${CERTSTORE}/temp.der";
            }
	}

        # now fetch root certs from configuration containers in AD
	foreach my $certcontainer (split(",", $certcontainers))
	{
	    GetAdCerts($certcontainer);
	}
    }

    my $reg = CentrifyDC::GP::RegHelper->new('map', $args->class(), $enrollreg, "aepolicy", undef);
    $reg or return undef;
    $reg->load();
    
    my $autoPolicy = $reg->get("current");
    # now see if we need to do machine auto enrollment
    # By default Windows will do autoenrollment if the policy is not configured
    # Only setting disable explicitly will turn this off. The disable bit is
    # 0x8000 which is equal to 32768 in decimal
    if(!defined($autoPolicy) || $autoPolicy != 32768)
    {
        # we dont care about the values in the policy
        # maybe we should take the flags and pass to adcert, but we dont

        my $aeCmd = "${adcert} -d ${CERTSTORE}";
        if ($args->class() eq "machine")
        {
            $aeCmd .= " -m";
        }
        else
        {
	        $aeCmd .= " -u ${user}";
            $aeCmd = "su - ${user} -c '${aeCmd}'";
        }
        my ($rc, $out) = RunCommand("${aeCmd}");
        
        # now get crls for the certs we just got
        
        my @keyfiles = csh_glob("${CERTSTORE}/*.key");
        foreach my $keyfile (@keyfiles)
        {
            my $certname = $keyfile;
            $certname =~ s/\.key/.cert/;
            RunCommand("/usr/share/centrifydc/sbin/get_crl.pl '${certname}' $tempdir/crl 1");
        }
    }

    if ($args->class() eq "machine")
    {
        my @fetchfiles = csh_glob("$tempdir/asynch_crl_fetch_*.crl");
        foreach my $fetchfile (@fetchfiles)
        {
            RunCommand("/usr/share/centrifydc/sbin/get_crl.pl ${fetchfile} $tempdir/crl 1");
            unlink $fetchfile;
        }
    }

    # Do a rehash to make sure all certs can be used.
    RehashAllCerts();
}
else
{
    # remove existing certificate information but keep the auto-enrolled 
    # cert and private key.
    my @certItems = csh_glob("${CERTSTORE}/*");
    my @deleteItems;
    foreach my $item (@certItems)
    {
        if ($args->class() eq "machine")
        {
            if ($item !~ m/^${CERTSTORE}\/auto_.*/ && $item !~ m/^${CERTSTORE}\/autoeth_.*/)
            {
                push(@deleteItems, $item);
            }
        }
	else
        {
            if ($item !~ m/^${CERTSTORE}\/autouser_.*/)
            {
                push(@deleteItems, $item);
            }
        }
    }
    unlink(@deleteItems);
}

# read a cert from the registry
# it is laid out as follows (found by debuggin windows code)
# <type><x><length><value>
# type,x,value are all little endian 32 bit integers
# I suspect x is an 'occurs' count. I have only ever seen 1 in it
# Length is the length of the value in bytes
# I dont know or care what the values are except for type=32 which is the cert DER itself
# the input is a hexified string
sub DecodeCertBlob
{
   (my $blob) = @_;
   # first convert the hexified string to the binary it represents
   my $blen = length $blob;
   my $bin = pack("H${blen}", $blob);

   my $off = 0;
   while($off < length $bin)
   {
      (my $type, my $x, my $len) = unpack("VVV", substr($bin, $off));
      $off += 12;
      if($type == 32) 
      {
         return substr($bin, $off, $len);
      }
      $off += $len;
   }
   return undef;
}

# Retrieve [root] certificates from a specified AD container. ldapsearch is
# used to retrieve the domain name, then the specified container is searched by 
# looking for the "cacertificate" attribute (which is where certificates will
# be stored). Those found are considered trusted root certificates, and are
# converted from DER to PEM format and stored as "trust_<fingerprint>.cert".
#
sub GetAdCerts
{
   (my $container) = @_;

   my $val;
   my $dcdom;

   ($ret, $out) = RunCommand("${ldapsearch} -m -LLL -s base -b '' -r configurationNamingContext");
   foreach $val (split /\n/, $out)
   {
      if ($val =~ /^configurationNamingContext: (.*)$/)
      {
          $dcdom = $1;
          last;
      }
   }
   my $ldapcmd = "${ldapsearch} -m -LLL -t -b \"CN=${container},CN=Public Key Services,CN=Services,${dcdom}\" -r cacertificate";
   ($ret, $out) = RunCommand($ldapcmd);
   my @ldap = split /\n/, $out;
   my @cacerts = ();
   foreach $val (@ldap)
   {
       if ($val =~ /^cACertificate:< file:\/\/(.*)/)
       {
           push @cacerts, $1;
       }
   }

    foreach my $temp (@cacerts)
    {
        InstallCert($temp);
        unlink ${temp};
    }

    # If we find any cert then we should do a rehash so that the cert
    # can be used by other tools, like adcert.
    if (@cacerts > 0)
    {
        RehashAllCerts();
    }
}

#
# Install certificate to CERTSTORE folder which is /var/centrify/net/certs by
# default.
#
#   $_[0]:  file-based certificate input
#   $_[1]:  file-based certificate input format: PEM/DER/NET
#
#   return: 1       - successful
#           undef   - failed
#
sub InstallCert($;$)
{
    my ($cert, $certForm) = @_;

    if ($certForm ne 'PEM' && $certForm ne 'DER' && $certForm ne 'NET')
    {
        $certForm = 'DER';
    }

    # we will use the fingerprint as the cert name
    my $ret = undef;
    my $fingerprint = GetFingerprint($cert, $certForm);
    if (defined($fingerprint))
    {
        chomp $fingerprint;
        # now convert to PEM format
        my ($rc, $output) = RunCommand("${openssl} x509 -in $cert -inform $certForm -out ${CERTSTORE}/trust_${fingerprint}.cert");
        if ($rc == 0)
        {
            chmod(0444, "${CERTSTORE}/trust_${fingerprint}.cert");
            $ret = 1;
        }
        else
        {
            DEBUG_OUT("Can not convert $cert to ${CERTSTORE}/trust_${fingerprint}.cert: $output");
        }
    }
    else
    {
        # normally the return output is the failure reason
        DEBUG_OUT("Can not get fingerprint from $cert: $fingerprint");
    }
    return $ret;
}

# Rehash all certificates
# The openssl will look for certificate with the filename <subject-hash>.n.
# This is a convention to call c_rehash (a Perl script from openssl) to
# recreate symlink <subject-hash>.n for all the certifiicate files.
#
sub RehashAllCerts
{
    my $rc = RunCommand("${c_rehash} ${CERTSTORE}");
    if (!defined($rc) or $rc ne '0')
    {
        WARN_OUT("Cannot rehash symlink in ${$CERTSTORE}")
    }
}
