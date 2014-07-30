#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Machine/user mapper script to run specified commands.
# All commands are run as root.
#
#  Map:     run specified commands
#
#  Unmap:   do nothing
#
# Parameters: <map|unmap> [username] mode
#   map|unmap   action to take
#   username    username
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
use CentrifyDC::GP::General qw(:debug RunCommand IsEmpty);
use CentrifyDC::GP::RegHelper;

my $REGKEY = "software/policies/centrify/unixsettings/runcommand";



# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $args = CentrifyDC::GP::Args->new();

$args->isMap() or exit 0;

CentrifyDC::GP::Registry::Load($args->user());

my $reg_commands = CentrifyDC::GP::RegHelper->new($args->action(), $args->class(), $REGKEY, undef, undef, 1);
$reg_commands or FATAL_OUT("Cannot create RegHelper instance");
$reg_commands->load('current');

my $err = 0;

my $commands = $reg_commands->get('current');
if (! IsEmpty($commands))
{
    foreach my $command (@$commands)
    {
        DEBUG_OUT("Run command: [$command]");
        my ($ret, $output) = RunCommand($command);
        if (! defined($ret))
        {
            # if an error occurred, continue to next command
            ERROR_OUT("Cannot run command [$command]");
            $err = 1;
            next;
        }
        DEBUG_OUT("Return     : [$ret]");
    }
}

$err and FATAL_OUT();

