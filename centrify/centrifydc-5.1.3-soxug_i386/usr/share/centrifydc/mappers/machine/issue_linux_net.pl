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
use CentrifyDC::GP::General qw(:debug);

my $keyname="software/policies/centrify/unixsettings";
my $msgregkeyname="network.login.message.enabled";
my $issue_file = "/etc/issue";
my $issue_net_file= "/etc/issue.net";
my $issue_net_orig="/etc/issue.net.orig";



#
# check if policy is enabled
#
sub is_policy_enabled() 
{
    #
    # fetch from the registry whether the linux networkg login message policy is enabled
    #
    my @tmp = CentrifyDC::GP::Registry::Query("machine",$keyname,"current", $msgregkeyname);

    return 0 unless defined $tmp[1];  # network.login.message.enabled not set in the registry
    return $tmp[1] eq "true";
}

#
# Undo the symlink
# 1. Check if the /etc/issue exists as symink
# 2. If it does remove the symlink.
# 3. Check if the /etc/issue.net.orig exits
# 4. If it does rename it to /etc/issue.net
#
sub undo_the_symlink()
{
    my $fstat = stat($issue_net_file);
    # if it exists and is a symlink
    if ($fstat && -l $issue_net_file)
    {
        unlink($issue_net_file);
    }
    $fstat = stat($issue_net_orig);
    if ($fstat) 
    {
        rename $issue_net_orig, $issue_net_file;
    }
}
#
# D the symlink
# 1. Check if the /etc/issue.net exists and is not a symlink.
# 2. If true then
#       a. rename /etc/issue.net to /etc/issue.net.orig
#       b. create a symlink /etc/issue.net-->/etc/issue
# 3. else
# 4.    b. create a symlink /etc/issue.net-->/etc/issue
#
sub do_the_symlink()
{
    my $fstat = stat($issue_net_file);
    # if it exists and is a symlink
    if ($fstat &&  -l $issue_net_file)
    {
        #
        # nothing to do we already have a symlink
        #
        return; 
    } elsif ($fstat) 
    {
        # not a symlink so rename /etc/issue.net -->/etc/issue.net.orig
        rename $issue_net_file, $issue_net_orig;
    }
     # create a symlink /etc/issue.net-->/etc/issue
    symlink($issue_file, $issue_net_file);
}



#
#     MAIN PROGRAM
#

# check to see if this is linux, exit if not
exit unless `uname -a` =~ /^Linux/o; 

my $args = CentrifyDC::GP::Args->new('machine');

CentrifyDC::GP::Registry::Load(undef);

my $enabled = is_policy_enabled();

if (! $args->isMap() || ! $enabled)
{
    DEBUG_OUT("Unmapping the Linux Network Login Message Policy");
    undo_the_symlink();
}
elsif  ($args->isMap() && $enabled) 
{
    DEBUG_OUT("Mapping the Linux Network Login Message Policy");
    do_the_symlink();
} 
#
# policy disabled so check if the symlink and orig file exists then restore it.
#
elsif ($args->isMap() && !$enabled)
{
        undo_the_symlink();
}

