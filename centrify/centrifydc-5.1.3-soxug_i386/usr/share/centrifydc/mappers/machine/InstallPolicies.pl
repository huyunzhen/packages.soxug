#!/bin/sh /usr/share/centrifydc/perl/run
#
# Machine mapper script to copy GP Policy scripts from an SMB share to
# the local system.
#
# Copyright (C) 2005-2014 Centrify Corporation. All rights reserved.
#

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug);
use CentrifyDC::GP::Registry;
use CentrifyDC::SMB;

my $REGISTRYVALUE = "software/policies/centrify/unixsettings";
my $FILELISTVALUE = $REGISTRYVALUE . "/filedist";
my $LISTFILE = ".cdc_filedist";

my %windowsPaths;
my %pathOptions;



my $args = CentrifyDC::GP::Args->new('machine');

CentrifyDC::GP::Registry::Load(undef);

#
# Check whether machine policies should be installed.
#
my (undef, $copyMachine) = CentrifyDC::GP::Registry::Query($args->class(),
    $REGISTRYVALUE, "current", "InstallMachinePolicies");
if (defined($copyMachine) and $copyMachine eq "true")
{
    my $unixPath = "/usr/share/centrifydc/mappers/machine";
    my ($type, $windowsPath) = CentrifyDC::GP::Registry::Query($args->class(),
        $REGISTRYVALUE, "current", "MachinePolicySource");
    $windowsPaths{$unixPath} = $windowsPath;
}
else
{
    #
    # We're not installing machine policies now.  If we were before,
    # remove the policies we installed.
    #
    my (undef, $copyMachine) = CentrifyDC::GP::Registry::Query($args->class(),
        $REGISTRYVALUE, "previous", "InstallMachinePolicies");
    if (defined($copyMachine) and $copyMachine eq "true")
    {
        my $unixPath = "/usr/share/centrifydc/mappers/machine";
        $windowsPaths{$unixPath} = "__UNMAP__";
    }
}

#
# Check whether user policies should be installed.
#
my (undef, $copyUser) = CentrifyDC::GP::Registry::Query($args->class(),
    $REGISTRYVALUE, "current", "InstallUserPolicies");
if (defined($copyUser) and $copyUser eq "true")
{
    my $unixPath = "/usr/share/centrifydc/mappers/user";
    my ($type, $windowsPath) = CentrifyDC::GP::Registry::Query($args->class(),
        $REGISTRYVALUE, "current", "UserPolicySource");
    $windowsPaths{$unixPath} = $windowsPath;
}
else
{
    #
    # We're not installing user policies now.  If we were before,
    # remove the policies we installed.
    #
    my (undef, $copyUser) = CentrifyDC::GP::Registry::Query($args->class(),
        $REGISTRYVALUE, "previous", "InstallUserPolicies");
    if (defined($copyUser) and $copyUser eq "true")
    {
        my $unixPath = "/usr/share/centrifydc/mappers/user";
        $windowsPaths{$unixPath} = "__UNMAP__";
    }
}

if (! %windowsPaths)
{
    # Nothing to do.
    exit(0);
}

#
# Copy all the files or directories in the list.
#
my $smb = CentrifyDC::SMB->new();
$smb->convertCRLF(1);
$smb->directory(1);
$smb->recurse(0);
$smb->removeDeleted(1);
$smb->mode(0755);

foreach my $unixPath (keys(%windowsPaths))
{
    my $options = \%{$pathOptions{$unixPath}};
    my $windowsPath = $windowsPaths{$unixPath};

    next unless (defined($windowsPath));

    if (! $args->isMap() || $windowsPath eq "__UNMAP__")
    {
        DEBUG_OUT("Delete policy file $unixPath");
        $smb->DeleteLocalCopy($windowsPath, $unixPath);
    }
    else
    {
        DEBUG_OUT("Copy policy file to $unixPath");
        $smb->GetNewFiles($windowsPath, $unixPath);
    }
}

