#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2014 Centrify Corporation. All rights reserved.
#
##############################################################################

package CentrifyDC::Ldap;
use lib '/usr/share/centrifydc/perl';  
use CentrifyDC::Logger;
use CentrifyDC::GP::General;
use Data::Dumper;
use MIME::Base64;

use strict;
our $VERSION = 1.00;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(
               ldapsearch
               ldapdelete
               ldapmodify
               ldapadd
               ldaprename
               ldap_escapednattr
               ldap_escapefilter
               LDAP_SCOPE_BASE
               LDAP_SCOPE_ONE 
               LDAP_SCOPE_TREE
);

my $ldapsearch = '/usr/share/centrifydc/bin/ldapsearch';
my $ldapdelete = '/usr/share/centrifydc/bin/ldapdelete';
my $ldapmodify = '/usr/share/centrifydc/bin/ldapmodify';
our $logger = CentrifyDC::Logger->new('ldap.pl');
use constant LDAP_SCOPE_BASE => "base";
use constant LDAP_SCOPE_ONE => "one";
use constant LDAP_SCOPE_TREE => "sub";

use constant DN_SPECIALCHARS => ',+"\<>;=#';
use constant LDAP_FILTER_SPECIALCHARS => '`"*()';

our $enc_policy = $CentrifyDC::Config::properties{"adclient.ldap.packet.encrypt"} || "Allowed";
$enc_policy =~ tr/[A-Z]/[a-z]/;
our $sasl_opts;
if($enc_policy eq "disabled")
{
   $sasl_opts = "-O \"ssflevel=disabled\"";
}
elsif($enc_policy eq "required")
{
   $sasl_opts = "-O \"ssflevel=required\"";
}
else
{
   $sasl_opts = "-O \"ssflevel=allowed\"";
}

my $auth_opts;
my $volume = "-Q";
sub checkaction {
   my ($args) = @_;
   if($args->{binddn} and $args->{password})
   {
      $auth_opts = "-x -D '".$args->{binddn}."' -w '".$args->{password}."'";
      # -x is incompatible with -O option 
      $sasl_opts = "";
      # -x is incompatible with -Q option
      $volume = "";
   }
   if($args->{machine})
   {
      $auth_opts = "-m";
   }

   if($args->{verbose})
   {
      $volume = "-v";
   }
}

sub ldapsearch {
   my (%args) = @_;
   checkaction(\%args);
   my $domain = $args{domain} || "";
   my $filter = $args{filter} || "(objectclass=*)";
   my @attrs = @{ $args{attrs} || [''] };
   my $scope = $args{scope} || LDAP_SCOPE_BASE;
   my $base = $args{base} || "";
   my $null = "2>/dev/null " unless $args{verbose};
   die if not my $path = make_path(\%args);
   $? = 0;
   my $ldap = "${ldapsearch} ${auth_opts} ${sasl_opts} ${volume} -r -t -LLL ${path} -s ${scope} -b '$base' \"${filter}\" @attrs";
   open (LDAP, "${ldap} ${null} |");

   # the resulting array
   my @objects;
   push @objects, {};
 
   while(chomp(my $line = <LDAP>))
   {
      if($line !~ m/^ *$/)        #non blank line
      {      
         next if substr($line, 0, 1) eq " ";
         my $i = index($line, ":< file://");
         my $attr;
         my $value;
         if ($i > 0)
         {   
            $attr = substr($line, 0, $i);
            my $file = substr($line, $i + 10);
            $value = `cat $file`;
            unlink $file;
            next unless $value;
        }
        else
        {
           $i = index($line, ":");
           next unless $i;
           $attr = substr($line, 0, $i);
           $value = substr($line, $i + 2);
        }
        my $oc = scalar(@objects);
        my $obj = $objects[$oc - 1];
        if ($obj->{$attr}){
           my $temp = $obj->{$attr};
           delete($obj->{$attr});
           push @{ $obj->{$attr} }, $value;
           push @{ $obj->{$attr} }, $temp;
        }
        else
        {
           $obj->{$attr} = $value;
        }
    }
    else
    {
       push @objects, {};
    }
   }
   pop @objects;
   my $c = scalar(@objects);
   close LDAP;
   mylog("ldapsearch: ${ldap} c:${c} ret:%d", $args{verbose});
   return \@objects if @objects;
}

sub ldapdelete
{
   my (%args) = @_;
   checkaction(\%args);
   my $null = "2>/dev/null >/dev/null" unless $args{verbose};
   my $domain = $args{domain} || "";
   my $recurse = "-r" if $args{recurse};
   my $dn = $args{dn} || die ("need dn");
   die if not my $path = make_path(\%args);
   $? = 0;
   my $ldap = "${ldapdelete} ${sasl_opts} ${auth_opts} ${volume} ${recurse} ${path}  '${dn}'";
   `$ldap ${null}`;
   mylog("ldapdelete: ${ldap}  ret:%d", $args{verbose});
   return $? >> 8;
}

sub ldapmodify
{
   my(%args) = @_;
   checkaction(\%args);
   my $null = "2>/dev/null >/dev/null" unless $args{verbose};
   my $attrs = $args{object} || die "need attrs";
   # if a given attribute contains empty value, we assume that we need to clear/delete the attribute's value in AD.
   # if the original value in attribute is already empty then we can not use the delete operation to delete an attribute value. 
   # so here need orignial value to check whether delete an attribute value.
   my $attrs_orig = $args{object_orig} || die "need original attrs";
   my $dn = $attrs->{dn} || die ("need dn");
   my $domain = $args{domain} || "";
   my $count = 0;

   # generate update statement
   my $update_statement = "";
   while ((my $k, my $v) = each(%$attrs))
   {
      next if $k eq "dn";# we already did this
      next if $k eq "cn";# cn not allowed
      if(ref($v) eq "ARRAY")
      {
         foreach my $vv(@$v)
         {
            if($vv ne "") # replace
            {
                $count++;
                $update_statement .= "-\n" if $count > 1;
                $vv = encode_base64($vv,"");
                $update_statement .= "${k}:: ${vv}\n";
            }
            elsif($attrs_orig->{$k} ne "") # delete
            {
                $count++;
                $update_statement .= "-\n" if $count > 1;
                $update_statement .= "delete: ${k}\n";
            }
         }
      }
      else
      {
          if($v ne "") # replace
          {
              $count++;
              $update_statement .= "-\n" if $count > 1;
              $v = encode_base64($v,"");
              $update_statement .= "${k}:: ${v}\n";
          }
          elsif($attrs_orig->{$k} ne "") # delete
          {
              $count++;
              $update_statement .= "-\n" if $count > 1;
              $update_statement .= "delete: ${k}\n";
          }
      }
   }

   # if no attribute need to modify then return
   return 0 unless $count;

   die if not my $path = make_path(\%args);
   $? = 0;
   my $ldap = "${ldapmodify} ${sasl_opts} ${auth_opts} ${volume} ${path}  ";
   open LDAP, "| ${ldap} ${null}";
   print LDAP "dn: ${dn}\n";
   print LDAP "$update_statement";
   close LDAP;
   mylog("ldapmodify: ${ldap} ret:%d", $args{verbose});
   return $? >> 8;
}


sub ldapadd
{
   my (%args) = @_;
   checkaction(\%args);
   my $null = "2>/dev/null >/dev/null" unless $args{verbose};
   my $attrs = $args{object} || die "need attrs";
   my $dn = $attrs->{dn} || die ("need dn");
   my $domain = $args{domain} || "";
   my $add = "-a";
   die if not my $path = make_path(\%args);
   $? = 0;
   my $ldap = "${ldapmodify} ${sasl_opts} ${auth_opts} ${add} ${volume} ${path}  ";
   open LDAP, "| ${ldap} ${null}";
   print LDAP "dn: ${dn}\n";
   while ((my $k, my $v) = each(%$attrs))
   {
      next if $k eq "dn";# we already did this
      next if $k eq "cn";# cn not allowed
      if(ref($v) eq "ARRAY")
      {
         foreach my $vv(@$v)
         {
            if(length($vv))
            {
                $vv = encode_base64($vv,"");
                print LDAP "${k}:: ${vv}\n";
            }
         }
      }
      else
      {
          if(length($v))
          {
              $v = encode_base64($v,"");
              print LDAP "${k}:: ${v}\n";
          }
      }
   }
   close LDAP;
   mylog("ldapmodify: ${ldap} ret:%d", $args{verbose});
   return $? >> 8;
}

sub ldaprename
{
   my (%args) = @_;
   checkaction(\%args);
   my $null = "2>/dev/null >/dev/null" unless $args{verbose};
   my $dn = $args{dn} || die ("need dn");
   my $newrdn = $args{newrdn} || die ("need newdn");
   my $domain = $args{domain} || "";
   die if not my $path = make_path(\%args);
   $? = 0;
   my $ldap = "${ldapmodify} ${sasl_opts} ${auth_opts} ${volume} ${path} ";
   open LDAP,"| ${ldap} $null";
   print LDAP "dn: ${dn}\n";
   print LDAP "changetype: modrdn\n";
   print LDAP "newrdn: ${newrdn}\n";
   print LDAP "deleteoldrdn: 1\n";
   print LDAP "\n";
   close LDAP;
   mylog("ldaprename: ${ldap} ret:%d", $args{verbose});
   return $? >> 8;
}

# escaping special characters if have. for details, refer to:
# RFC1779, RFC2253 and http://msdn.microsoft.com/en-us/library/aa366101%28VS.85%29.aspx
# node, this function just be used in an attribute value of DN e.g CN, OU and DC
sub ldap_escapednattr
{
    my $str = shift;
    my $retstr = "";
    my @str_arr = string2array($str);
    my $alen = scalar(@str_arr);
    for(my $i=0; $i<$alen; $i++)
    {
        if(($i == 0 or  $i == $alen-1) and @str_arr[$i] eq " ")
        {
            $retstr .= '\ ';
        }
        elsif(have_specialchar(@str_arr[$i], DN_SPECIALCHARS))
        {
            $retstr .= "\\".@str_arr[$i];
        }
        else
        {
            $retstr .= @str_arr[$i];
        }
    }
    $retstr =~ s/\r/\\0D/g; 
    $retstr =~ s/\n/\\0A/g;
    return $retstr;
}

# escaping special characters if have '"', '\', "(", ")", "*"
# for details, refer to RFC2254
# node, this function just be used in filter of ldapcmd
sub ldap_escapefilter
{
    my $str = shift;
    my $retstr = "";
    $str =~ s/\\/\\\\\\\\/g;
    my @str_arr = string2array($str);
    my $alen = scalar(@str_arr);
    for(my $i=0; $i<$alen; $i++)
    {
        if(have_specialchar(@str_arr[$i], LDAP_FILTER_SPECIALCHARS))
        {
            $retstr .= "\\".@str_arr[$i];
        }
        else
        {
            $retstr .= @str_arr[$i];
        }
    }
    return $retstr;
}

sub have_specialchar
{
    my $char = shift;
    my $specialchars = shift;
    my @sc_arr = string2array($specialchars);
    foreach my $c (@sc_arr)
    {
        return 1 if $c eq $char;
    }
    return 0; 
}

sub string2array
{
    my $str = shift;
    my $slen = length($str);
    my @str_arr;
    for( my $i=0; $i<$slen; $i++)
    {
        push @str_arr, substr($str, $i, 1);
    }
    return @str_arr;
}

sub make_path
{
   my ($args) = @_;
   if($args->{host})
   {
      if($args->{host} eq "!")
      {
         $? = 0;
         my $host = `adinfo -r`;
         return if $?;
         chomp $host;
         return "-h ${host}";
      }
      my $host = $args->{host};
      return "-h ${host}";
   }
   elsif($args->{domain})
   {
      my $domain = $args->{domain};
      if($domain eq "\$")
      {
         return "-H \"GC://\"";
      }
      return "-H \"LDAP://${domain}\"";
   }
   else
   {
      return "-H \"LDAP://\"";
   }
}

sub mylog
{
   my ($msg, $verbose) = @_;
   my $s = $? >> 8;
   my $k = $?;
   my $buff = sprintf($msg, $s);
   $logger->log('DEBUG', $buff);
   $? = $k;
   print $buff."\n" if $verbose;
}
1;








