#!/bin/sh /usr/share/centrifydc/perl/run
#
# Copyright (C) 2005-2014 Centrify Corporation. All rights reserved.
#
# Machine/user mapper script that enforces screen locking for Linux.
#

use strict;

use lib '/usr/share/centrifydc/perl';

use File::Copy;
use File::Path;

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug);
use CentrifyDC::GP::Registry; 



exit unless `uname -a` =~ /^Linux/o; # check to see if this is linux, exit if not

my $args = CentrifyDC::GP::Args->new();

my $user = $args->user();

CentrifyDC::GP::Registry::Load($user);

my $registrykey = "software/policies/centrify/unixsettings/screenlock";
my %regVar;

my @keys = CentrifyDC::GP::Registry::Values($args->class(), $registrykey, "current");

foreach my $key (@keys)
{
    if (defined($key))
    {
        my @values = CentrifyDC::GP::Registry::Query($args->class(), $registrykey, "current", $key);
        $regVar{$key} = $values[1];
    }
}

if ($args->class() eq "machine") {
    if ($args->isMap()) {
	exit unless(($regVar{'ForceScreenLocking'}) || ($regVar{'LockTimeOut'})); # exit if nothing to do
	saveOrigSystemLockfile();
	modifySystemLockfile($regVar{'ForceScreenLocking'}, $regVar{'LockTimeOut'});
    } # if
    else {
	restoreOrigSystemLockfile(); # on unmap of machine policy restore lockfile to pre-policy state
    } # else
    exit; # end of machine policy
} # if
#
# arriving here means we are not of class machine
#

if ($args->isMap()) {
    exit unless ($regVar{'ForceScreenLocking'}); # there is nothing to do
    setUserLockfile();

#
# now that the user can not override the system default.  Set the system default to locked
#
# There is no good way to let the system default be unlocked and yet force a user to
# lock
#
    saveOrigSystemLockfile();
    modifySystemLockfile('yes', 0); # force locking leave the timeout to whatever the system default is
} # if
else {
    unsetUserLockfile();
} # else

sub setUserLockfile {
#
# So how do we prevent the user from just changing her .xscreensaver file and over riding anything
# we do?
#
# Basicly by denying her the ability to create such a file.  
#
# We do this by creating an undeletable directory by that name 
#
    my $homeDir = `/bin/echo ~$user`;
    chomp($homeDir);
    my $ssFile = "$homeDir/.xscreensaver"; 
    
    unless((-d $ssFile) && ((stat($ssFile))[4] == 0)) { # do nothing if this is already the case
	my $tmpdir = "$homeDir/.EnforceScreenLocking.$user"; # must be on same filesystem or mv wont work
	
	unlink $tmpdir; # otherwise user could stop us by blocking our tmpfile
	mkdir $tmpdir, 0700;
	open (LOCKFILE, ">${tmpdir}/locked");
	print LOCKFILE "Locked\n";
	close(LOCKFILE);
	chmod 0700, $tmpdir;
	rename $ssFile, "${tmpdir}/.xscreensaver"; # preserve any file the user had
	rename $tmpdir, $ssFile;
    DEBUG_OUT("Set user Lock file .xscreensave successfull.");
    } # unless
} # setUserLockFile

sub unsetUserLockfile {
    my $homeDir = `/bin/echo ~$user`;
    chomp($homeDir);
    my $ssFile = "$homeDir/.xscreensaver"; 
    my $tmpdir = "$homeDir/.EnforceScreenLocking.$user"; # must be on same filesystem or mv wont work

    if (-d $ssFile)
    {
        rename $ssFile, $tmpdir;
        rename "$tmpdir/.xscreensaver", $ssFile if (-f "$tmpdir/.xscreensaver");
        if (-d $tmpdir)
        {
            rmtree($tmpdir);
        }
        DEBUG_OUT("Unset of user Lock file .xscreensave successfull.");
    } # if
} # unsetUserLockfile

sub saveOrigSystemLockfile {
    my $configFile = "/usr/lib/X11/app-defaults/XScreenSaver";
#
# only copy the file if the backup does not already exist
# we only need one.  This file will be restored if the 
# policy is unmapped
#
    copy($configFile, "${configFile}.prePolicy") unless (-f "${configFile}.prePolicy");
} # saveOrigSystemLockfile

sub restoreOrigSystemLockfile {
    my $configFile = "/usr/lib/X11/app-defaults/XScreenSaver";
    if (-f "${configFile}.prePolicy")
    {
        unlink($configFile);
        copy("${configFile}.prePolicy", $configFile);
    } # if
} #restoreOrigSystemLockfile

sub modifySystemLockfile {
    my ($ForceScreenLocking, $LockTimeOut) = @_;

    my $configFile = "/usr/lib/X11/app-defaults/XScreenSaver";
    
#
# read in the config file
#
    open CONFIGFILE, "<$configFile";
    my @configFile = <CONFIGFILE>;
    close(CONFIGFILE);
    
    my ($index, $found);

    my $lockValue ="False";
    $lockValue ="True" if ($ForceScreenLocking eq "yes");

    for($index = 0; $index < $#configFile; $index++) {
        if ($configFile[$index] =~ /^\*lock:/o) {
            $found = "True";
            $configFile[$index] = "*lock:\t\t\t$lockValue\n";
        } # if
    } # for
    push @configFile, "*lock:\t\t\t$lockValue\n" unless($found);

    
    if ($LockTimeOut) {
	my $time = $LockTimeOut;
	$time = "0$time" if ($time < 10);
	
	undef $found;
	for($index = 0; $index < $#configFile; $index++) {
	    if ($configFile[$index] =~ /^\*lockTimeout:/o) {
		$found = "True";
		$configFile[$index] = "*lockTimeout:\t\t0:00:00\n";
	    } # if
	} # for
	push @configFile, "*lockTimeout:\t\t0:00:00\n" unless($found);
	
	undef $found;
	for($index = 0; $index < $#configFile; $index++) {
	    if ($configFile[$index] =~ /^\*timeout:/o) {
		$found = "True";
		$configFile[$index] = "*timeout:\t\t0:$time:00\n";
	    } # if
	} # for
	push @configFile, "*timeout:\t\t0:$time:00\n" unless($found);
    } # if
    
    open OUTFILE, ">$configFile";
    print OUTFILE @configFile;
    close OUTFILE;
} # modifySystemLockfile

