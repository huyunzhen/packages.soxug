#!/bin/sh /usr/share/centrifydc/perl/run
#
##############################################################################
#
# Copyright (C) 2008-2014 Centrify Corporation. All rights reserved.
#
# machine/user mapper script to do adreload, adflush, restart adclient, etc.
#
# Several mapper scripts need to do adreload/adflush if configuration changed.
# To prevent multiple adreload/adflush, these mapper scripts will not run
# adreload/adflush directly. Instead, they'll create:
#       /var/centrifydc/reg/do_adreload
#       /var/centrifydc/reg/do_adflush
#       /var/centrifydc/reg/do_restart_adclient
# and this mapper script will do the actual reload/flush if these files exist.
#
#
# Parameters: <map|unmap> [username] mode
#   map|unmap   action to take
#   username    username (not used)
#   mode        mode (not used)
#
# Exit value:
#   0   Normal
#   1   Error
#   2   usage
#
##############################################################################

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug RunCommand);

my $DO_RESTART_ADCLIENT = '/var/centrifydc/reg/do_restart_adclient';
my $DO_RESTART_ADCLIENT_FOR_WATCHDOG = '/var/centrifydc/do_restart_adclient';
my $DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE = '/var/centrifydc/reg/do_restart_expire';
my $DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE_FOR_WATCHDOG = '/var/centrifydc/do_restart_expire';
my $DO_STOP_ADCLIENT = '/var/centrifydc/reg/do_stop_adclient';
my $DO_STOP_ADCLIENT_FOR_WATCHDOG = '/var/centrifydc/do_stop_adclient';
my $DO_ADRELOAD         = '/var/centrifydc/reg/do_adreload';
my $DO_ADFLUSH          = '/var/centrifydc/reg/do_adflush';
my $DO_DSRELOAD         = '/var/centrifydc/reg/do_dsreload';
my $DO_DSFLUSH          = '/var/centrifydc/reg/do_dsflush';
my $DO_SARESTART        = '/var/centrifydc/reg/do_sarestart';
my $DO_RESTART_LOGINWINDOW = '/var/centrifydc/reg/do_restart_loginwindow';
my $DO_DARELOAD         = '/var/centrifydc/reg/do_dareload';

my $CMD_ADRELOAD         = '/usr/sbin/adreload';
# The flush just expires the entire cache, this way we will not lose the users cached creds.
# Losing the users creds is BAD in a laptop system since they are in disconnected mode often.
my $CMD_ADFLUSH          = '/usr/sbin/adflush -e';
# reload should be sufficient, but is not (yet)
my $CMD_DSRELOAD         = '/usr/share/centrifydc/bin/dsconfig reload';
my $CMD_DSFLUSH          = '/usr/share/centrifydc/bin/dsconfig flush';
my $CMD_RESTART_LOGINWINDOW = '/usr/bin/killall -HUP loginwindow';
my $CMD_RESTART_SECURITYAGENT = '/usr/bin/killall -HUP SecurityAgent';
my $CMD_RESTART_AUTHORIZATIONHOST = '/usr/bin/killall -HUP authorizationhost';
# It is sufficient to reload DirectAudit settings, when the centrifyda.conf has been changed.
my $CMD_DARELOAD         = '/usr/sbin/dareload';

sub GetMacOSVersion();
sub RestartLoginWindow();


# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# get Mac OS X version based on uname -r
#       
# The sw_vers program can hang on 10.5, so don't use it.
# Instead, rely on the correlation between the kernel version
# and the OS version - the kernel version has been 4 higher
# than the OS minor version (e.g. 10.4.x is kernel version 8.x)
# from at least 10.2 through 10.5 - hopefully Apple won't change
# that on us.
#
#   return: hash reference of version
#               'major' => major version
#               'minor' => minor version
#               'trivia' => trivia version
#
sub GetMacOSVersion()
{
    my %ver = ();

    my $kernel_ver = `uname -r`;

    $kernel_ver =~ m/(\d*)\.(\d*)\.(\d)*/;

    $ver{'major'}  = '10.' . ($1 - 4);
    $ver{'minor'}  = $2;
    $ver{'trivia'} = $3;

    return \%ver;
}

#
# restart loginwindow
#
# Mac 10.4: kill loginwindow
# Mac 10.5: kill SecurityAgent, then kill authorizationhost
# Mac 10.6: kill SecurityAgent
# Mac 10.7: kill SecurityAgent
#
#   return: 1       - successful
#           undef   - failed
#
sub RestartLoginWindow()
{
    my $MACVER = GetMacOSVersion()->{major};

    if (! defined($MACVER))
    {
        ERROR_OUT("Cannot get Mac OS version");
        return undef;
    }
    elsif ($MACVER eq '10.4')
    {
        DEBUG_OUT("Restart loginwindow");
        my $rc = RunCommand("$CMD_RESTART_LOGINWINDOW");
        if (!defined($rc) or $rc ne '0')
        {
            ERROR_OUT("Cannot restart loginwindow");
            return undef;
        }
    }
    elsif ($MACVER eq '10.5')
    {
        DEBUG_OUT("Restart SecurityAgent");
        my $rc = RunCommand("$CMD_RESTART_SECURITYAGENT");
        if (!defined($rc) or $rc ne '0')
        {
            ERROR_OUT("Cannot restart SecurityAgent");
            return undef;
        }
        DEBUG_OUT("Restart authorizationhost");
        my $rc = RunCommand("$CMD_RESTART_AUTHORIZATIONHOST");
        if (!defined($rc) or $rc ne '0')
        {
            ERROR_OUT("Cannot restart authorizationhost");
            return undef;
        }
    }
    else
    {
        # 10.6/10.7
        DEBUG_OUT("Restart SecurityAgent");
        my $rc = RunCommand("$CMD_RESTART_SECURITYAGENT");
        if (!defined($rc) or $rc ne '0')
        {
            ERROR_OUT("Cannot restart SecurityAgent");
            return undef;
        }
    }

    return 1;
}

# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $args = CentrifyDC::GP::Args->new();

$args->isMap() or exit(0);

if (-e $DO_ADRELOAD && ! -e $DO_RESTART_ADCLIENT && ! -e $DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE)
{
    DEBUG_OUT("Do adreload");
    my $rc = RunCommand("$CMD_ADRELOAD");
    if (!defined($rc) or $rc ne '0')
    {
        ERROR_OUT("Cannot do adreload");
    }
    unlink($DO_ADRELOAD);
}

if (-e $DO_ADFLUSH)
{
    DEBUG_OUT("Do adflush");
    my $rc = RunCommand("$CMD_ADFLUSH");
    if (!defined($rc) or $rc ne '0')
    {
        ERROR_OUT("Cannot do adflush");
    }
    unlink($DO_ADFLUSH);
}

if (-e $DO_DSRELOAD)
{
    DEBUG_OUT("Do dsreload");
    my $rc = RunCommand("$CMD_DSRELOAD");
    if (!defined($rc) or $rc ne '0')
    {
        ERROR_OUT("Cannot do dsreload");
    }
    unlink($DO_DSRELOAD);
}

if (-e $DO_DSFLUSH)
{
    DEBUG_OUT("Do dsflush");
    my $rc = RunCommand("$CMD_DSFLUSH");
    if (!defined($rc) or $rc ne '0')
    {
        ERROR_OUT("Cannot do dsflush");
    }
    unlink($DO_DSFLUSH);
}

if (-e $DO_SARESTART)
{
    DEBUG_OUT("Do sarestart (not implemented)");

    unlink($DO_SARESTART);
}

if ($args->mode() eq 'login')
{
    if (-e $DO_RESTART_LOGINWINDOW)
    {
        my $system = `uname -s`;
        if (! defined($system))
        {
            ERROR_OUT("Cannot get system name");
        }
        else
        {
            chomp $system;
            if ($system eq 'Darwin')
            {
                my $rc = RestartLoginWindow();
                if (! $rc)
                {
                    ERROR_OUT("Cannot restart loginwindow");
                }
            }
        }
        unlink($DO_RESTART_LOGINWINDOW);
    }
}

if (-e $DO_STOP_ADCLIENT)
{
    INFO_OUT("Schedule stop of adclient");

    open(FH, ">$DO_STOP_ADCLIENT_FOR_WATCHDOG");
    close(FH);
    chmod(0600, $DO_STOP_ADCLIENT_FOR_WATCHDOG);

    unlink($DO_STOP_ADCLIENT);
    unlink($DO_RESTART_ADCLIENT);
    unlink($DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE);
    unlink($DO_ADRELOAD);
}

if (-e $DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE)
{
    INFO_OUT("Schedule restart of adclient and expire of cache");

    open(FH, ">$DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE_FOR_WATCHDOG");
    close(FH);
    chmod(0600, $DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE_FOR_WATCHDOG);

    unlink($DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE);
    unlink($DO_RESTART_ADCLIENT);
    unlink($DO_ADRELOAD);
}

if (-e $DO_RESTART_ADCLIENT)
{
    INFO_OUT("Schedule restart of adclient");

    open(FH, ">$DO_RESTART_ADCLIENT_FOR_WATCHDOG");
    close(FH);
    chmod(0600, $DO_RESTART_ADCLIENT_FOR_WATCHDOG);

    unlink($DO_RESTART_ADCLIENT);
    unlink($DO_ADRELOAD);
}

if (-e $DO_DARELOAD)
{
    if (-x $CMD_DARELOAD)
    {
        DEBUG_OUT("Do dareload");
        my $rc = RunCommand("$CMD_DARELOAD");
        if (!defined($rc) or $rc ne '0')
        {
            ERROR_OUT("Cannot do dareload");
        }
    }
    else
    {
        ERROR_OUT("$CMD_DARELOAD not exist or not executable");
    }
    unlink($DO_DARELOAD);
}
