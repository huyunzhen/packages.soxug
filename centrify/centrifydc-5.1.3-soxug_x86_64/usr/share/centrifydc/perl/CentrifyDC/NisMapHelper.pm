#!/bin/sh /usr/share/centrifydc/perl/run
#
# Copyright (C) 2005-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl NIS mapper helper module.
#
use strict;

package CentrifyDC::NisMapHelper;

use CentrifyDC::Config;
use lib "../perl";
use lib '/usr/share/centrifydc/perl';
use CentrifyDC::Ldap;
use CentrifyDC::Logger;
use File::Spec;
our $logger = CentrifyDC::Logger->new('nismaphelper.pl');
my $verbose = 0;

my %NisMapSchema = (
    automount => '$CimsAutomountMapVersion1',
);

our %NisMapEntrySchema = (
    netgroup => '$CimsNetgroupVersion1',
    protocols => '$CimsProtocolVersion1',
    rpc => '$CimsRpcVersion1',
    hosts => '$CimsHostVersion1',
    ethers => '$CimsEtherVersion1',
    networks => '$CimsNetVersion1',
    netmasks => '$CimsNetmaskVersion1',
    aliases => '$CimsAliasVersion1',
    services => '$CimsServiceVersion1',
    audit_user => '$CimsAuUserVersion1',
    prof_attr => '$CimsProfAttrVersion1',
    exec_attr => '$CimsExecAttrVersion1',
    auth_attr => '$CimsAuthAttrVersion1',
    user_attr => '$CimsUserAttrVersion1',
    bootparams => '$CimsBootparamsVersion1',
    printers => '$CimsPrinterVersion1',
    project => '$CimsProjectVersion1',
    publickey => '$CimsPublickeyVersion1',
    automount=> '$CimsAutomountVersion1',
);

sub GetMapSchema($;$)
{
    my ($map, $type) = @_;

    # if specified type then use it, otherwise using mapname to determine type
    if($type eq "")
    {
        # map schema is empty value, but with exception of mapname that start with auto,
        # map schema will be set to $CimsAutomountMapVersion1 automatically
        if($map =~ m/^auto/)
        {
            $type = "automount";
        }
        else
        {
            $type = $map;
        }
    }

    if (exists($NisMapSchema{$type}))
    {
        return $NisMapSchema{$type};
    }

    return "";
}

sub GetMapEntrySchema($;$)
{
    my ($map, $type) = @_;

    # if specified type then use it, otherwise using mapname to determine type
    if($type eq "")
    {
        # with exception of mapname that start with auto
        if($map =~ m/^auto/)
        {
            $type = "automount";
        }
        else
        {
            $type = $map;
        }
    }

    if (exists($NisMapEntrySchema{$type}))
    {
        return $NisMapEntrySchema{$type};
    }

    return "";
}

sub GetMapEntryType($)
{
    my $key = shift;
    my %reNisMapEntrySchema = reverse %NisMapEntrySchema;

    if (exists($reNisMapEntrySchema{$key}))
    {
        return $reNisMapEntrySchema{$key};
    }

    return "";
}

sub GetMapBaseDN($$$$)
{
    my ($map, $b, $cdcconfig,$machine) = @_;
    user_debug("Specified map dn: $b");
    if ($cdcconfig)
    {
        my $cdc_mapdn = $CentrifyDC::Config::properties{"nismap.dn.$map"};
        if ($cdc_mapdn)
        {
            user_debug("Redirected map, be specified in centrifydc.conf. map dn: $cdc_mapdn");
            return $cdc_mapdn;
        }
    }

    my $objects = ldapsearch(
            base => $b,
            verbose => $verbose,
            machine => $machine,
            attrs => ["wbempath"],
            scope => LDAP_SCOPE_BASE);

    if ($objects)
    {
        foreach my $m (@$objects)
        {
            my $path = $m->{wbemPath};
            if(ref($path) eq "ARRAY")
            {
                foreach my $v (@$path)
                {
                    if ($v)
                    {
                        user_debug("Redirected map, be specified in AD. map dn: $v");
                        return $v;
                    }
                }
            }
            elsif($path)
            {
                user_debug("Redirected map, be specified in AD. map dn: $path");
                return $path;
            }
        }
    }
    return $b;
}

sub set_vars
{
    my (%vars) = @_;
    $verbose = $vars{verbose};
}

sub user_debug
{
    my $msg = shift;
    print "$msg\n" if $verbose;
    $logger->log('DEBUG', $msg);
}

1;
