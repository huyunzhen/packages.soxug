#!/bin/sh /usr/share/centrifydc/perl/run
#
# Copyright (C) 2005-2014 Centrify Corporation. All rights reserved.
#
# Machine mapper script that configures /etc/issue for Linux.
#

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::Registry;
use CentrifyDC::GP::General qw(:debug RunCommand);

my $registrykey = "software/policies/centrify/unixsettings/linuxfirewall";
my %regVar;

my $ipTablesCommand = 'iptables';
my $flushCommand = "$ipTablesCommand -F";
my $SAVE_FILE = "/var/centrifydc/reg/iptables.save";

$ENV{'PATH'} = $ENV{'PATH'}.":/usr/freeware/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin:/usr/bin:/opt/sfw/sbin:/opt/sfw/bin";



exit unless `uname -a` =~ /^Linux/o; # check to see if this is linux, exit if not

my $args = CentrifyDC::GP::Args->new('machine');
my $action = $args->action();

CentrifyDC::GP::Registry::Load(undef);

my @keys = CentrifyDC::GP::Registry::Values($args->class(), $registrykey, "current");

foreach my $key (@keys)
{
    if (defined($key))
    {
        my @values = CentrifyDC::GP::Registry::Query($args->class(), $registrykey, "current", $key);
        $regVar{$key} = $values[1];
    }
}

if (!defined($keys[0]) || !$keys[0])
{
    # Disabled in Group Policy; revert to local rules.
    $action = 'unmap';
}

my $ret;

if ($action eq 'map')
{
    if (! -e $SAVE_FILE)
    {
        DEBUG_OUT("Save original iptabes to file: $SAVE_FILE");
        $ret = RunCommand("iptables-save > $SAVE_FILE");
        if (! defined($ret) or $ret ne '0')
        {
            FATAL_OUT("Cannot save original optables to [$SAVE_FILE]");
        }
    }

    DEBUG_OUT("Flush iptables");
    $ret = RunCommand($flushCommand);
    if (! defined($ret) or $ret ne '0')
    {
        FATAL_OUT("Cannot flush iptables");
    }

    # Always allow incoming ssh and ICMP.
    DEBUG_OUT("Append ssh rule");
    $ret = RunCommand("$ipTablesCommand -A INPUT -p tcp --syn --destination-port 22 -j ACCEPT");
    if (! defined($ret) or $ret ne '0')
    {
        FATAL_OUT("Cannot append ssh rule");
    }
    DEBUG_OUT("Append ICMP rule");
    $ret = RunCommand("$ipTablesCommand -A INPUT -p icmp -j ACCEPT");
    if (! defined($ret) or $ret ne '0')
    {
        FATAL_OUT("Cannot append ICMP rule");
    }

    foreach my $key (sort(keys(%regVar)))
    {
        my ($Name, $Type, $Protocol, $Port, $Action) = split(/:/, $regVar{$key});
        next unless (($Type eq "INPUT") || ($Type eq "OUTPUT"));
        next unless (($Protocol eq "tcp")  ||
                     ($Protocol eq "udp")  ||
                     ($Protocol eq "icmp") ||
                     ($Protocol eq "all"));
        next unless ($Port =~ /^\d+$/o);
        next unless (($Action eq "ACCEPT") ||
                     ($Action eq "DROP")   ||
                     ($Action eq "REJECT"));
        my $syn = "--syn" if ($Protocol eq "tcp");
        DEBUG_OUT("Set iptables entry:  type: [$Type]  protocol: [$Protocol]  port: [$Port]  action: [$Action]");
        $ret = RunCommand("$ipTablesCommand -A $Type -p $Protocol $syn --destination-port $Port -j $Action");
        if (! defined($ret) or $ret ne '0')
        {
            FATAL_OUT("Cannot set iptables entry:  type: [$Type]  protocol: [$Protocol]  port: [$Port]  action: [$Action]");
        }
    } #foreach

    # Anything not expressly allowed above is prohibited
    # tcp only but obviously easy to change
    DEBUG_OUT("Reject all other tcp packets");
    $ret = RunCommand("$ipTablesCommand -A INPUT -p tcp --syn -j REJECT");
    if (! defined($ret) or $ret ne '0')
    {
        FATAL_OUT("Cannot reject all other tcp packets");
    }
} #if
else
{
    # what to do in the unmap case
    if (-e $SAVE_FILE)
    {
        DEBUG_OUT("Restore original iptabes from [$SAVE_FILE]");
        $ret = RunCommand("iptables-restore < $SAVE_FILE");
        if (! defined($ret) or $ret ne '0')
        {
            FATAL_OUT("Cannot restore original iptabes from [$SAVE_FILE]");
        }
        unlink($SAVE_FILE);
    } # else
} # else

