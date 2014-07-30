#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2012-2014 Centrify Corporation. All rights reserved.
#
# Machine mapper script that replace sudo by dzdo via symbolic link.
#
#  This script creates symbolic link /usr/share/centrifydc/bin/sudo to 
#  /usr/share/centrifydc/bin/dzdo to redirect sudo commands to dzdo. Users 
#  can control the redirection via Centrify DirectControl group policy 
#  "Replace sudo by dzdo" in "Dzdo Settings".
#
#  If enabled, the symbolic link will be created and redirect sudo commands 
#  to dzdo. If disabled, the symbolic link will be deleted. If unconfigured, 
#  original setting will be restored. For example, if a symbolic link 
#  /usr/share/centrifydc/bin/sudo to /usr/bin/sudo is created manually before 
#  the group policy is enabled or disabled, that symbolic link will be 
#  restored when the group policy is set to unconfigured again.
#
#  Besides sudo, sudoedit and the corresponding manual pages will be redirected 
#  as well. The symbolic links to be configured are listed below:
#       /usr/share/centrifydc/bin/sudo 
#    -> /usr/share/centrifydc/bin/dzdo
#       /usr/share/centrifydc/bin/sudoedit 
#    -> /usr/share/centrifydc/bin/dzedit
#       /usr/share/centrifydc/man/man8/sudo.8.gz 
#    -> /usr/share/man/man8/dzdo.8.gz
#       /usr/share/centrifydc/man/man8/sudoedit.8.gz 
#    -> /usr/share/centrifydc/man/man8/sudo.8.gz
#
#  To use the group policy, the system should be configured as follows:
#    Set /usr/share/centrifydc/bin as the first path in $PATH
#    Set /usr/share/centrifydc/man as the first path in $MANPATH
#
#  Map:     configure symbolic links e.g. /usr/share/centrifydc/bin/sudo.
#              Not Configured: restore original setting
#              Enable:         create symbolic link
#              Disable:        delete symbolic link
#
#  Unmap:   restore original setting
#
# Parameters: <map|unmap> mode
#   map|unmap   action to take
#   mode        mode (not used)
#
# Exit value:
#   0   Normal
#   1   Error
#
##############################################################################

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug TraverseSymLink);
use CentrifyDC::GP::Registry;
use CentrifyDC::GP::RegHelper;


# >>> DATA >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


my $REGKEY = "software/policies/centrify/centrifydc/settings/dzdo";
my $REGVAL = "dzdo.replace.sudo";
my $SYMLINK_REGKEY = "$REGKEY/symlink";

my $CENTRIFY_DIR = '/usr/share/centrifydc';
my $CENTRIFY_BIN_DIR = "$CENTRIFY_DIR/bin";
my $CENTRIFY_MAN_DIR = "$CENTRIFY_DIR/man";
my $SYSTEM_MAN_DIR = '/usr/share/man';

my $SYMLINK_DZDO_REGKEY = $SYMLINK_REGKEY;
my $SYMLINK_DZDO_REGVAL = "dzdo.replace.sudo";
my $SYMLINK_DZDO_SRC = "$CENTRIFY_BIN_DIR/sudo";
my $SYMLINK_DZDO_DEST = "$CENTRIFY_BIN_DIR/dzdo";

my $SYMLINK_DZDO_MANUAL_REGKEY = $SYMLINK_REGKEY;
my $SYMLINK_DZDO_MANUAL_REGVAL = "dzdo.replace.sudo.manual";
my $SYMLINK_DZDO_MANUAL_SRC = "$CENTRIFY_MAN_DIR/man8/sudo.8.gz";
my $SYMLINK_DZDO_MANUAL_DEST = "$SYSTEM_MAN_DIR/man8/dzdo.8.gz";

my $SYMLINK_DZEDIT_REGKEY = $SYMLINK_REGKEY;
my $SYMLINK_DZEDIT_REGVAL = "dzedit.replace.sudoedit";
my $SYMLINK_DZEDIT_SRC = "$CENTRIFY_BIN_DIR/sudoedit";
my $SYMLINK_DZEDIT_DEST = "$CENTRIFY_BIN_DIR/dzedit";

my $SYMLINK_DZEDIT_MANUAL_REGKEY = $SYMLINK_REGKEY;
my $SYMLINK_DZEDIT_MANUAL_REGVAL = "dzedit.replace.sudoedit.manual";
my $SYMLINK_DZEDIT_MANUAL_SRC = "$CENTRIFY_MAN_DIR/man8/sudoedit.8.gz";
my $SYMLINK_DZEDIT_MANUAL_DEST = "$SYSTEM_MAN_DIR/man8/dzdo.8.gz";


# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


#
# check if symbolic link is supported by platform
#
#   return: 1   - supported
#           0   - not supported
#
sub SymlinkSupported()
{
    my $supported = eval { symlink("",""); 1 };

    WARN_OUT("Symbolic link not supported on this platform") if (!$supported);
    return ($supported ? 1 : 0);
}


#
# Create directory man8 in /usr/share/centrifydc/man. This directory is created 
# when CDC-openssh is installed but not CDC. So we need to create directory 
# here when we create symlinks. We will leave the packages to decide when to 
# remove the directory.
#
# We will simply return success if directory exists.
#
#   return: 1   - directory created or already exists
#           0   - failed to create
#
sub CreateDir($$)
{
    my $ret = 0;

    my $dir = $_[0];
    my $perm = $_[1];

    if (-d $dir)
    {
        $ret = 1;
    }
    else
    {
        if (mkdir($dir, oct($perm)))
        {
            $ret = 1;
        }
        else
        {
            WARN_OUT("Failed to create directory [$dir] with permission [$perm]: $!");
        }
    }

    return $ret;
}


#
# delete existing symbolic link and create a new symbolic link
#
#   return: 1       - success
#           undef   - failed
#
sub UpdateSymlink($$)
{
    my $ret = 1;

    my $src = $_[0];
    my $dest = $_[1];

    # check input parameters
    if (!defined($src) || !defined($dest))
    {
        DEBUG_OUT("Invalid input parameters in subroutine UpdateSymlink");

        # avoid returning failed in this case
        # however this function is not used as intended and should not continue
        return 1;
    }

    #
    # delete existing symlink and create a new one
    #

    # delete symlink if exists
    if ( -l $src )
    {
        # we assume this function is called only when the configuration has an 
        # update
        if (!(unlink($src)))
        {
            WARN_OUT("Cannot delete symbolic link [$src]: $? ".
                     "Please check if the symbolic link is still in use.");
            return undef;
        }

        DEBUG_OUT("Symbolic link [$src] deleted");
    }

    # create symlink if needed
    if ($dest ne "")
    {
        if (!symlink($dest, $src))
        {
            WARN_OUT("Cannot create symbolic link [$src] -> [$dest]: $? ".
                     "Please check if the directory is not exist or the path is already occupied.");
            return undef;
        }
        else
        {
            DEBUG_OUT("Symbolic link [$src] -> [$dest] created");
        }
    }

    INFO_OUT("Symbolic link [$src] -> [$dest] updated successfully");
    return $ret;
}


#
# configure symbolic link according to GP settings
#
#   return: 1       - success
#           undef   - failed
#
sub ConfigureSymlink($$$$$)
{
    my $ret = 1;

    my $args = $_[0];
    my $action = $args->action();
    my $class = $args->class();

    # for GP settings
    my $regkey = $REGKEY;
    my $regval = $REGVAL;

    # for symlink
    my $symlink_regkey = $_[1];
    my $symlink_regval = $_[2];
    my $symlink_src = $_[3];
    my $symlink_dest = $_[4];

    my $src = $symlink_src;
    my $dest = undef;


    #
    # create RegHelper objects
    #

    # get settings from GP
    my $reg = CentrifyDC::GP::RegHelper->new($action, $class, $regkey, $regval, undef);
    $reg->load();

    # used to determine if we need to apply new settings
    my $reg_dest = CentrifyDC::GP::RegHelper->new($action, $class, $symlink_regkey, $symlink_regval, undef);
    $reg_dest->load();


    #
    # set symlink destination for current and previous groups
    #
    
    foreach my $group (qw(current previous))
    {
        $dest = undef;
        my $gp_enabled = $reg->get($group);
        
        if (defined($gp_enabled))
        {
            if ($gp_enabled eq "true")
            {
                $dest = $symlink_dest;
            }
            else
            {
                # we will distinguish disabled and unconfigured GP
                # by assigning empty string when disabled and undef when unconfigured
                $dest = "";
            }
        }
            
        $reg_dest->set($group, $dest);
    }


    #
    # set symlink target for system group
    #

    $dest = undef;
    if (-l $src)
    {
        $dest = TraverseSymLink($src);
    }
    else
    {
        # in this case, set system value the same as disabled (empty string) 
        # but not unconfigured (undef) for two purposes:
        # 1. so current group will NOT always be returned from getGroupToApply 
        #    when current value is empty string
        # 2. local value can be updated again (not always possible if system 
        #    value is undef instead)
        $dest = "";
    }

    $reg_dest->set('system', $dest);


    #
    # apply new settings
    #

    my $apply_group = $reg_dest->getGroupToApply($action);
    
    # empty string will be returned by getGroupToApply()
    if (defined($apply_group) && $apply_group ne "")
    {
        $dest = $reg_dest->get($apply_group);

        #
        # check prerequisite before update
        #

        # check if symlink is supported
        # check only when applying new settings to avoid excessive error reporting
        return undef if (!SymlinkSupported());

        # check if directory /usr/share/centrifydc/man/man8 exists
        return undef if (!CreateDir("$CENTRIFY_MAN_DIR/man8", '0755'));

        $ret = UpdateSymlink($src, $dest);
    }

    return $ret;
}

#
# Configure symbolic links. Stop and return immediately when failed to 
# configure one of the symbolic links.
#
#   return: 1       - successful
#           undef   - failed
#
sub ConfigureSymlinks($)
{
    my $ret = 0;
    
    $ret = ConfigureSymlink($_[0], 
                            $SYMLINK_DZDO_REGKEY, $SYMLINK_DZDO_REGVAL, 
                            $SYMLINK_DZDO_SRC, $SYMLINK_DZDO_DEST);
    $ret or return undef;

    $ret = ConfigureSymlink($_[0], 
                            $SYMLINK_DZDO_MANUAL_REGKEY, $SYMLINK_DZDO_MANUAL_REGVAL, 
                            $SYMLINK_DZDO_MANUAL_SRC, $SYMLINK_DZDO_MANUAL_DEST);
    $ret or return undef;

    $ret = ConfigureSymlink($_[0], 
                            $SYMLINK_DZEDIT_REGKEY, $SYMLINK_DZEDIT_REGVAL, 
                            $SYMLINK_DZEDIT_SRC, $SYMLINK_DZEDIT_DEST);
    $ret or return undef;

    $ret = ConfigureSymlink($_[0], 
                            $SYMLINK_DZEDIT_MANUAL_REGKEY, $SYMLINK_DZEDIT_MANUAL_REGVAL, 
                            $SYMLINK_DZEDIT_MANUAL_SRC, $SYMLINK_DZEDIT_MANUAL_DEST);
    return $ret;
}

#
# map
#
#   return: 1       - successful
#           undef   - failed
#
sub Map($)
{
    return ConfigureSymlinks($_[0]);
}

#
# unmap
#
#   return: 1       - successful
#           undef   - failed
#
sub UnMap($)
{
    return ConfigureSymlinks($_[0]);
}


# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


my $args = CentrifyDC::GP::Args->new();
CentrifyDC::GP::Registry::Load($args->user());

my $ret = 0;
$args->isMap() ? ($ret = Map($args)) : ($ret = UnMap($args));
$ret or FATAL_OUT();
