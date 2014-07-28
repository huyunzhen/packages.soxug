#!/bin/sh /usr/share/centrifydc/perl/run
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Machine/user mapper script that updates crontab entries.
#

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug ReadFile RunCommand GetTempDirPath CreateTempFile);
use CentrifyDC::GP::Lock;
use CentrifyDC::GP::Registry;                                             


my $TEMP_DIR = GetTempDirPath(0);
defined($TEMP_DIR) or FATAL_OUT();


sub CrontabEntry($$$);
sub GetAllPreviousUsers();
sub GetAllCurrentUsersAndCrontabCommands();

my $registrykey = "software/policies/centrify/unixsettings/crontabentries";
my %regVar;
my $key;

my $args = CentrifyDC::GP::Args->new();
my $action = $args->action();

CentrifyDC::GP::Registry::Load($args->user());

# filename prefix of our temporary output file
my $TEMP_FILE_PREFIX = "$TEMP_DIR/temp.out.crontab";

# Identify operating system
my $uname=`uname -s`;
my $CRON_LIST="su %s -c 'crontab -l' 2>/dev/null |";
my $CRON_CREATE="su %s -c 'crontab %s' >/dev/null 2>&1";
my $CRON_REMOVE="crontab -r %s >/dev/null 2>&1 ";
my $CRON_ALLOW="/usr/lib/cron/cron.allow";
my $CRON_DENY="/usr/lib/cron/cron.deny";
$uname =~ s/[\s|\t|\r|\f|\n]//;
if ("$uname" eq "Linux")
{
    $CRON_LIST="crontab -u %s -l 2>/dev/null |";
    $CRON_CREATE="crontab -u %s %s >/dev/null 2>&1";
    $CRON_REMOVE="crontab -u %s -r >/dev/null 2>&1 ";
    $CRON_ALLOW="/etc/cron.allow";
    $CRON_DENY="/etc/cron.deny";
    if (`uname -r` =~ m/(2\.4\.19\-.*|2\.4\.21\-198.*|2\.6\.4-5.*|2\.6\.5\-7.*)/)
    {
        $CRON_ALLOW="/var/spool/cron/allow";
        $CRON_DENY="/var/spool/cron/deny";
    }
}
else
{
    if ("$uname" eq "Darwin")
    {
        $CRON_REMOVE="crontab -u %s -r >/dev/null 2>&1 ";
        `/usr/bin/sw_vers -productVersion` =~ m/(10\.\d)\.?(\d+)?/;
        if ($1 eq "10.4")
        {
            $CRON_ALLOW="/var/cron/allow";
            $CRON_DENY="/var/cron/deny";
        }
    }
    my $AIX_34=`uname -rv`;
    $AIX_34=~ s/[\n]//;
    if ("$AIX_34" eq "3 4")
    {
        $CRON_REMOVE="su %s -c 'crontab -r' >/dev/null 2>&1 ";
    }
}



#>>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $pre_users = GetAllPreviousUsers();
my $cur_users = GetAllCurrentUsersAndCrontabCommands();

# Set/reset the users' crontab entries in current registry.
foreach my $cuser (keys %$cur_users)
{
    # remove the user from previous users hash 
    delete $pre_users->{$cuser};
    CrontabEntry("map", $cuser, "@{$cur_users->{$cuser}}");
    DEBUG_OUT("Wrote crontab entry: @{$cur_users->{$cuser}} for user $cuser");
}

# Clean up the users' crontab entries in previous (but not in current) registry
foreach my $puser (keys %$pre_users)
{
    CrontabEntry("unmap", $puser, "");
    DEBUG_OUT("Cleaned up crontab entry for user $puser");
}



#>>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# This function will parse the Previous.pol to get the users. 
#
#   return: hash - A hash ref contains all the users as hash key
#
sub GetAllPreviousUsers()
{
    my %users = ();
    my @keys = CentrifyDC::GP::Registry::Values($args->class(), $registrykey, "previous");
    if (defined($keys[0]))
    {
        foreach $key(@keys)
        {
            my @values = CentrifyDC::GP::Registry::Query($args->class(), $registrykey,
                "previous", $key);
            my $croncommand = $values[1];
            $croncommand =~ s/^\s*//;
            my @entry = split(/ +/, $croncommand);
            if ($values[1])
            {
                DEBUG_OUT("Previous policy file crontab entry: $values[1]");
            }
            # Min Hour DayOfMonth Month DayOfWeek User command
            next if (scalar(@entry) < 7);
            $users{$entry[5]} = 1;
        }
    }
    return \%users;
}

#
# Find all the users and their crontab commands in Registry.pol.
#
#   return: hash - A hash ref contains all the users and their crontab commands.
#                  hash keys are the users, @{$hash->{$user}} has the crontab
#                  command of $user
#
sub GetAllCurrentUsersAndCrontabCommands()
{
    # begin to get the present values to write the crontab
    my @keys = CentrifyDC::GP::Registry::Values($args->class(), $registrykey, "current");
    my %cronvalues = ();
    if (defined($keys[0]))
    {
        foreach $key(@keys)
        {
            my @values = CentrifyDC::GP::Registry::Query($args->class(), $registrykey,
                "current", $key);
            $regVar{$key} = $values[1];
            DEBUG_OUT("Current policy file crontab entry: $values[1]");
        } # foreach
    } # if

    # crontab entries by user
    foreach my $key (sort(keys %regVar))
    {
        # skip comments and blank lines
        next if ($regVar{$key} =~ /^[ \t]*\#/o);
        next if ($regVar{$key} =~ /^[ \t]*$/o);

        # remove the space in the beginning of the crontab command
        my $croncommand = $regVar{$key};
        $croncommand =~ s/^\s*//;
        my @entry = split(/ +/, $croncommand);    
        # Min Hour DayOfMonth Month DayOfWeek User command
        next if (scalar(@entry) < 7);
        # get the user
        my $cuser = $entry[5];
        splice(@entry, 5, 1);
        # the same user's command, we will put together
        push(@{$cronvalues{$cuser}},"\n@entry\n");
    } # foreach

    foreach my $user (keys %cronvalues)
    {
        $cronvalues{$user} = \@{$cronvalues{$user}};
    } # foreach

    return \%cronvalues;
}

# write the crontab for each user
#
# For "map":
# 1. We will always rewrite the crontab commands which is between the markerstart
# and markerend. But will not modify any line before and after of them.
# 2. When markerstart not found, will add the crontab commands to the end of
# crontab
#
# For "unmap":
# we will clean up all the content which is between the markerstart and markerend
# (including markerstart and markerend)
#
#   $_[0]: map/unmap - the action will apply to user crontab
#   $_[1]: user      - user name
#   $_[2]: command   - the crontab commands will be added to user when action is
#                      map. Just set empty when action is unmap
#
sub CrontabEntry($$$)
{
    my ($action, $cuser, $command) = @_;
    
    my ($tempfh, $tempfilename) = CreateTempFile($TEMP_FILE_PREFIX);
    if (! defined($tempfh) or ! defined($tempfilename))
    {
        FATAL_OUT("Cannot create temp file");
    }
    TRACE_OUT("Temp file $tempfilename created");

    my $LIST_COMMAND=sprintf($CRON_LIST, $cuser);
    my $CREATE_COMMAND=sprintf($CRON_CREATE, $cuser, $tempfilename);
    my $REMOVE_COMMAND=sprintf($CRON_REMOVE, $cuser);
    my $empty = 1;

    # search through the config file to find the key from the registry file
    open CONFIG, "$LIST_COMMAND";
    my $markerstart = "#** Generated via group policy by centrify for $cuser Start **\n";
    my $markerend   = "#** Generated via group policy by centrify for $cuser End   **\n";
    # Make sure the markerend always starts with a new line
    $command .= "\n";
    my $configline;
    my $found = 0;
    while ($configline = <CONFIG>)
    {
        if ($configline eq $markerstart)
        {
            $found = 1;
            if ($action eq "map")
            {
                # Write the new crontab entries to the same place of centrify
                # crontab section
                print $tempfh $markerstart; 
                print $tempfh $command;
                print $tempfh $markerend;
                $empty = 0;
            } # if

            my $cl;
            # Skip all the old crontab entries in centrify crontab section
            while ($cl = <CONFIG>)
            {
                last if ($cl eq $markerend);
            } # while
        } # if
        else
        {
            # do not copy the warning lines, they get regenerated by the crontab command
            next if ($configline =~ /^\# DO NOT EDIT THIS FILE/o);
            next if ($configline =~ /^\# \(\/.+\/temp.out.crontab/o);
            next if ($configline =~ /^\# \(Cron versio/o);

            if ($configline eq $markerend)
            {
                # error condition
            } # if
            else
            {
                print $tempfh $configline; 
                $empty = 0;
            } # else

            # if the same exact line already exists in our configfile,
            # we don't need to add it again
            chomp($configline);
        } # else
    } # while

    # If no old centrify crontab section found, just append a new centrify
    # crontab section to the end.
    if (!$found and ($action eq "map"))
    {
        print $tempfh $markerstart;
        print $tempfh $command;
        print $tempfh $markerend;
        $empty = 0;
    } # if
    close $tempfh;
    close CONFIG;
    chmod 0644, $tempfilename;

    # If there is no entry for the crontab, we should remove the crontab file completely.
    if ($empty)
    {
        DEBUG_OUT("Remove empty crontab file");
        my $rc = RunCommand($REMOVE_COMMAND);
        if (! defined($rc) or $rc ne '0')
        {
            #
            # Note that error will be returned if no such crontab entry can be 
            # deleted, e.g.:
            #   RHEL 3:     "no crontab for root" (rc: 1)
            #   AIX 5.3:    "0481-152 The unlink function failed on the cron 
            #                file." (rc: 1)
            #
            # Since the below message will be normally shown in log when 
            # multiple crontab entries are defined, so we lower the message 
            # level from error to warning here.
            #
            WARN_OUT("Cannot remove empty crontab file");
        }
        unlink($tempfilename) or ERROR_OUT("Cannot remove temp file $tempfilename");
        return;
    }

    #before create the crontab, we need check the cron.allow or allow file
    my $content;
    if (-e $CRON_ALLOW)
    {
        $content=ReadFile($CRON_ALLOW);
        if ($content !~ m|$cuser$|ms)
        {
            my $lock = CentrifyDC::GP::Lock->new($CRON_ALLOW);
            if (! defined($lock))
            {
                unlink($tempfilename) or ERROR_OUT("Cannot remove temp file $tempfilename");
                FATAL_OUT("Cannot obtain lock for $CRON_ALLOW");
            }
            open(ALLOW, ">>$CRON_ALLOW");
            print (ALLOW "$cuser\n");
            close ALLOW;

            $content=ReadFile($CRON_ALLOW);
        }
    }
    else
    {
        if (-e $CRON_DENY)
        {
            $content=ReadFile($CRON_DENY);
            if ($content =~ m|$cuser$|ms)
            {
                my $lock = CentrifyDC::GP::Lock->new($CRON_DENY);
                if (! defined($lock))
                {
                    unlink($tempfilename) or ERROR_OUT("Cannot remove temp file $tempfilename");
                    FATAL_OUT("Cannot obtain lock for $CRON_DENY");
                }
                open(DENY, ">$CRON_DENY");
                $content =~ s/$cuser\n//ms;
                print (DENY "$content");
                close DENY;
            }
        }
    }

    DEBUG_OUT("Create crontab entry using command [$CREATE_COMMAND]");
    my $rc = RunCommand($CREATE_COMMAND, "$TEMP_DIR/createcrontab.lock");
    if (! defined($rc) or $rc ne '0')
    {
        ERROR_OUT("Cannot create crontab entry");
    }

    unlink($tempfilename) or ERROR_OUT("Cannot remove temp file $tempfilename");
    return;
}

