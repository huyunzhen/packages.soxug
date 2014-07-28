#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2005-2014 Centrify Corporation. All rights reserved.
#
# Machine/user mapper script that modifies the sudoers setting.
#
#  1. check if sudo is installed. If sudo is not installed, script will
#     quit silently.
#  2. check registry to see if it's necessary to update sudoers file.
#  3. use  visudo -c  to locate the sudoers file.
#  4. create a copy of sudoers file, update it with GP settings, then run
#     visudo -c  again to verify it. If the copy is correct, replace the
#     old sudoers file; else the copy will be discarded.
#
#  Special markers are added around the sudoers setting in sudoers file so
#    that settings can be easily unmapped. It looks like below:
#
#    #### START CentrifyDC group policy generated machine settings START ###
#    User_Alias     FULLTIMERS =ytest1,ytest2
#    users ALL=(ALL) ALL
#    ###  END  CentrifyDC group policy generated machine settings  END  ###
#
#
#  There are several major differences between 3.0 (TIGGER) and 4.0 (TOPCAT)
#    sudoers setting:
#    1. 3.0 has both machine and user sudoers policy, while 4.0 only has
#       machine policy.
#    2. The format of 3.0/4.0 settings are different.
#    3. The registry key in 3.0/4.0 are different.
#         in 3.0 it's software/policies/centrify/centrifydc/settings/sudo
#         in 4.0 it's software/policies/centrify/unixsettings/sudo
#       So 3.0 and 4.0 settings can co-exist.
#    4. On Domain Controller side, 3.0 uses ADM, while 4.0 uses DLL snapin.
#    5. There's no marker around 3.0 mapper generated settings in sudoers file.
#
#  3.0 setting has very limited functionality, while 4.0 setting is much more
#    flexible and powerful, but it makes 3.x/4.x not compatible.
#
#
#  To ensure backward compatibility, this mapper needs to handle both 3.0 and
#    4.0 settings, while 4.0 setting has higher priority.
#
#  The machine mapper will try to use 4.0 setting first (and remove 3.0 setting
#    from sudoers file); if not available, it will use 3.0 setting.
#
#  Although 4.0 doesn't have user setting, we still need the user mapper to
#    handle 3.0 user settings. The user mapper will use 3.0 user setting if 4.0
#    machine setting doesn't exist; else it will clean up 3.0 user setting.
#
#  Below is the mapper's action under different situations.
#  Notice that we use map/unmap for 3.0 because the mapper uses our perl
#    library's standard Map/UnMap routine, but use add/remove for 4.0 because
#    the mapper needs to add/remove setting into sudoers file directly without
#    help of perl library.
#
#
# X: Not found/enabled
# O: found/enabled
# -: N/A
#
# MACHINE MAPPER
# -----------------------------------------------------------------------------
#  3.0 machine    4.0 machine                        Action
#  -----------   -------------      ----------------------------------------
#   exists      exists  enabled           Map                     Unmap
# -----------------------------------------------------------------------------
#     X           X       -       Map 3.0,   remove 4.0   Unmap 3.0, remove 4.0
#     O           X       -       Map 3.0,   remove 4.0   Unmap 3.0, remove 4.0
#     X           O       X       Map 3.0,   remove 4.0   Unmap 3.0, remove 4.0
#     X           O       O       Map 3.0,   add 4.0      Unmap 3.0, remove 4.0
#     O           O       X       Unmap 3.0, remove 4.0   Unmap 3.0, remove 4.0
#     O           O       O       Unmap 3.0, add 4.0      Unmap 3.0, remove 4.0
# -----------------------------------------------------------------------------
#
# USER MAPPER
# -----------------------------------------------------------------------------
#  3.0 user       4.0 machine                        Action
#  -----------   -------------      ----------------------------------------
#   exists      exists  enabled           Map                     Unmap
# -----------------------------------------------------------------------------
#     X           X       -       Map 3.0                 Unmap 3.0
#     O           X       -       Map 3.0                 Unmap 3.0
#     X           O       X       Map 3.0                 Unmap 3.0
#     X           O       O       Map 3.0                 Unmap 3.0
#     O           O       X       Unmap 3.0               Unmap 3.0
#     O           O       O       Unmap 3.0               Unmap 3.0
# -----------------------------------------------------------------------------
#
#
#  4.0 settings format:
#  --------------------
#  The input filed in DC's GPOE is a multi-line text field. It will be added
#    into sudoers file directly.
#
#
#  3.0 settings format:
#  --------------------
#  machine/user settings are handled differently.
#
#  Machine: There are 2 input fields in DC's GPOE, first is user name, second
#           is "runas alias" + command. The mapper will add hostname into
#           setting.
#             Example:
#               First:  aduser1
#               Second: (ALL) ALL
#             In sudoers file:
#               aduser1 HOSTNAME=(ALL) ALL
#
#  User:    There are also 2 input fields in DC's GPOE, first is "runas alias",
#           second is command. The mapper will add current user's name and
#           hostname into setting.
#             Example:
#               First:  runas_alias
#               Second: ALL
#             In sudoers file:
#               USERNAME HOSTNAME=(runas_alias) ALL
#
#
#  Map:     add sudoers setting into sudoers file.
#  Unmap:   remove sudoers setting from sudoers file.
#
#
# Parameters: <map|unmap> [username] mode
#   map|unmap   action to take
#   username    optional user name. If omitted, then it's a machine mapper
#   mode        should always be "boot"
#
# Exit value:
#   0   Normal
#   1   Error
#   2   Usage
#
##############################################################################

use strict;

use lib '/usr/share/centrifydc/perl';

use File::Basename;
use File::Copy;
use Sys::Hostname;

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug RunCommand IsEmpty GetTempDirPath CreateTempFile);
use CentrifyDC::GP::Registry;
use CentrifyDC::GP::RegHelper;
use CentrifyDC::GP::Mapper;


my $TEMP_DIR = GetTempDirPath(0);
defined($TEMP_DIR) or FATAL_OUT();


my $TEMP_FILE_PREFIX = "$TEMP_DIR/sudoers.cdc-gp-tmp";

my $temp_file;
my $file;
my $hasdashc = 1;

# 3.0 settings
$::hostname = hostname();
$::hostname =~ s/\..*//;
chomp $::hostname;

# visudo locates in /usr/local/sbin on HPUX
# visudo locates in /usr/freeware/bin on IRIX
$ENV{'PATH'} = $ENV{'PATH'}.":/usr/freeware/bin:/usr/local/sbin:/usr/sbin:/sbin:/bin:/usr/bin:/opt/sfw/sbin:/opt/sfw/bin";



# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>


# 3.0
my %TIGGERSTYLE_REGKEY = {};
$TIGGERSTYLE_REGKEY{"machine"} = "software/policies/centrify/centrifydc/settings/sudo";
$TIGGERSTYLE_REGKEY{"user"}    = "software/policies/centrify/centrifydc/settings/sudo";


my %REGKEY_SUDO_ENABLED = {};
$REGKEY_SUDO_ENABLED{"machine"} = "software/policies/centrify/unixsettings";
$REGKEY_SUDO_ENABLED{"user"}    = "software/policies/centrify/unixsettings";

my %REGKEY = {};
$REGKEY{"machine"} = "software/policies/centrify/unixsettings/sudo";
$REGKEY{"user"}    = "software/policies/centrify/unixsettings/sudo";

my %MARKER = {};
$MARKER{"machine"} = {};
$MARKER{"machine"}{"start"} = "### START CentrifyDC group policy generated machine settings START ###\n";
$MARKER{"machine"}{"end"}   = "###  END  CentrifyDC group policy generated machine settings  END  ###\n";
$MARKER{"user"}{"start"}    = "### START CentrifyDC group policy generated user %s settings START ###\n";
$MARKER{"user"}{"end"}      = "###  END  CentrifyDC group policy generated user %s settings  END  ###\n";
my $WARNING                 = "### ### Do not edit directly, this block might be gone anytime ### ###\n";


sub topcat_policies_present($$)
#returns 1 if topcat-style policies are set
{
    my ($class, $user) = @_;
    my @tmp;
    return 0 if $class ne "machine"; #only machine settings in topcat

    @tmp= CentrifyDC::GP::Registry::Query($class,$REGKEY_SUDO_ENABLED{$class},"current", "sudo.enabled");

    return 0 unless defined $tmp[1]; #sudo.enabled not set in registry
    return 1; #sudo.enabled set in registry
}


sub tigger_policies_present($$)
#returns 1 if tigger-style policies are set
{
    my ($class, $user) = @_;

    my @values = CentrifyDC::GP::Registry::Values($class, $TIGGERSTYLE_REGKEY{$class}, "current");

    # no tigger sudo setting. return.
    return 0 unless (@values[0]);
    return 1;
}


sub sudo_is_enabled($$)
#returns non-zero only if the sudo.enabled regvalue is present and non-zero
{
    my ($class, $user) = @_;
    my @tmp;
    if ($user)
    {
        #
        # registry entry line for the user specific entry is "username:sudo_enabled"
        #
        @tmp= CentrifyDC::GP::Registry::Query($class,$REGKEY_SUDO_ENABLED{$class},"current",$user.":sudo.enabled");
    }
    else
    {
        @tmp= CentrifyDC::GP::Registry::Query($class,$REGKEY_SUDO_ENABLED{$class},"current", "sudo.enabled");
    }
    return 0 unless defined $tmp[1]; #sudo.enabled not set in registry
    return @tmp[1] eq "1";    
}


# Returns path to sudoers file as reported by visudo(8)
#   ret:    string  - sudo path
#           0       - sudo not found
sub ::find_sudoers()
{
    my $ret = 0;

    my $out = `visudo -c 2> /dev/null`;
    if ($out eq "")
    {
        # older versions that do not support "-c" option
        # just check and return one of the hard coded path
        $hasdashc = 0;
        my @path = @{$file->{'path'}};
        for (my $i = 0; $i <= $#path; $i++)
        {
            if (-e $path[$i])
            {
                # If the '/etc/sudoers' is missing, we need try to get one from other places
                # When the '/etc/sudoers' doesn't exist, then link to the existed sudoers file
                if ($path[$i] ne "/etc/sudoers")
                {
                    DEBUG_OUT("/etc/sudoers does not exist. Link $path[$i] to /etc/sudoers");
                    my $rc = symlink($path[$i], "/etc/sudoers");
                    if (! $rc)
                    {
                         ERROR_OUT("Cannot link $path[$i] to /etc/sudoers");
                    }
                }
                return $path[$i];
            }
        }
        return $ret;
    }

    if ($out =~ /^(.*) file parsed OK$/m)
    {
        $file->{'path'}[0] = $1;
        $ret = $1;
        TRACE_OUT("$ret parsed OK");
    }
    elsif ($out =~ /^(.*): parsed OK$/m)
    {
        $file->{'path'}[0] = $1;
        $ret = $1;
        TRACE_OUT("$ret parsed OK");
    }
    else
    {
        #1. If /etc/sudoers is empty, remove it and symlink /usr/local/etc/sudoers
        #2. Validate sudoers file using visudo -c
        #3. If it's incorrect, report error and remove symlink
        my $default_sudoers = "/etc/sudoers";
        my $local_sudoers = "/usr/local/etc/sudoers";
        if (-z $default_sudoers)
        {        
           WARN_OUT("$default_sudoers is empty");
           if (`visudo -c -f $local_sudoers 2> /dev/null` =~ / parsed OK$/m)
           {
               # If /usr/local/etc/sudoers is correct, we will remove the empty /etc/sudoers 
               # and link to /usr/local/etc/sudoers
               DEBUG_OUT("Remove $default_sudoers and link $local_sudoers to $default_sudoers");
               my $rc;
               $rc = unlink $default_sudoers;
               if (! $rc)
               {
                    ERROR_OUT("Cannot remove $default_sudoers");
                    return;
               }
               $rc = symlink($local_sudoers, $default_sudoers);
               if (! $rc)
               {
                    ERROR_OUT("Cannot link $local_sudoers to $default_sudoers");
                    return;
               }
               $file->{'path'}[0] = $default_sudoers;
               $ret = $default_sudoers;
           }
           else
           { 
               $file->{'path'}[0] = $default_sudoers;       
               $ret = $default_sudoers;
               WARN_OUT("/usr/local/etc/sudoers is incorrect. ignore it");
           }
        }        
    }

    return $ret;
}

# Check if sudo is installed
#   ret:    1   - installed
#           0   - not installed
sub is_sudo_installed()
{
    my @vers = split / /, `visudo -V 2>/dev/null`;
    if ($vers[0] eq "visudo")
    {
        return 1;
    }
    else
    {
        DEBUG_OUT("visudo not found. Maybe sudo is not installed.");
        return 0;
    }
}


# Verify sudoer file by visudo(8)
#   ret:    1   - file incorrect
#           0   - file correct
sub ::verify_sudoers()
{
    my $ret = 1;
    if (!$hasdashc)
    {
        return 0;
    }
    my $out = `visudo -c 2> /dev/null`;
    if ($out =~ / parsed OK$/m)
    {
        $ret = 0;
    }
    return $ret;
}


sub copy_sudoers_to_temp_and_unmap_topcat($$$)
{
    my ($sudoersfile, $class, $user) = @_;
    my $temp = "";
    
    #read in sudoers file
    open SUDOERS, "< $sudoersfile"
        or FATAL_OUT("could not open $sudoersfile");
    while (<SUDOERS>) { $temp.= $_; }    
    close SUDOERS;
    
    #remove existing centrifydc blocks
    my $start = sprintf $MARKER{$class}{"start"}, $user;
    my $end   = sprintf $MARKER{$class}{"end"}, $user;
    $temp =~ s/$start(.*)$end//s;
    
    
    #write out temp file, but make it non-readable to others first
    my ($fh, $filename) = CreateTempFile($TEMP_FILE_PREFIX);
    if (! defined($fh) or ! defined($filename))
    {
        FATAL_OUT("Cannot create temp file");
    }

    $temp_file = $filename;
    print ($fh $temp) or FATAL_OUT("Cannot write $temp_file");
    close ($fh);
}


sub copy_temp_to_sudoers_if_verified($)
{
    my ($sudoersfile) = @_;

    TRACE_OUT "Verify $temp_file";
    FATAL_OUT("Cannot find $temp_file to verify") if (! -e $temp_file);

    #verify temp file and copy changes to sudoers if ok
    my $verified = 0;
    if ($hasdashc)
    {
        my $out = `visudo -c -f $temp_file 2> /dev/null`;
        if ($out =~ / parsed OK/m)
        {
            TRACE_OUT("$temp_file parsed OK");
            $verified = 1;
        }
    }
    else
    {
        $verified = 1;
    }

    if ($verified)
    {
        TRACE_OUT("Copy $temp_file to $sudoersfile");
        # Save original file state
        my ($mode, $uid, $gid) = (stat "$sudoersfile")[2, 4, 5];
        copy($temp_file, $sudoersfile) or FATAL_OUT("Cannot copy $temp_file to $sudoersfile");
        chmod $mode, $sudoersfile;
        chown $uid, $gid, $sudoersfile;
    }
    else
    {
        WARN_OUT("visudo Failed, will not change $sudoersfile");
    }
}


sub add_topcat_to_sudoers($$)
{
    my ($class, $user) = @_;
    my $combined_lines = "";
    DEBUG_OUT("Adding 4.0 $class $user registry entries to sudoers file");

    #get all values from local registry
    my @valuenames = CentrifyDC::GP::Registry::Values($class,$REGKEY{$class},"current");
    VALUENAME: foreach my $valuename ( sort sort_numerically @valuenames)
    {
        my @tmp = CentrifyDC::GP::Registry::Query($class,$REGKEY{$class},"current",$valuename);
        my $valuedata = $tmp[1];
        my $line = "";
        if ($valuename =~ /user/)
        {
            $line = "$user $valuedata\n";
        }
        else
        {
            $line = "$valuedata\n";
        }
        DEBUG_OUT("Adding 4.0 $class $user entry: $line");
        $combined_lines .= $line;
    }
    

    my $sudoersfile = find_sudoers() or FATAL_OUT( "visudo could not find system suoders file");

    copy_sudoers_to_temp_and_unmap_topcat($sudoersfile, $class, $user);

    #append new policy values to tmp file
    FATAL_OUT("Cannot find $temp_file to append new policy values") if (! -e $temp_file);

    open TEMP, ">> $temp_file"
        or FATAL_OUT("Cannot open $temp_file");
    print TEMP sprintf $MARKER{$class}{"start"}, $user;
    print TEMP $WARNING;
    print TEMP $combined_lines;
    print TEMP sprintf $MARKER{$class}{"end"}, $user;
    close TEMP;

    copy_temp_to_sudoers_if_verified($sudoersfile);
}


sub remove_topcat_from_sudoers($$)
{
    my ($class, $user) = @_;
    if ($user)
    {
        DEBUG_OUT("Removing 4.0 $class $user settings from sudoers file");
    }
    else
    {
        DEBUG_OUT("Removing 4.0 $class settings from sudoers file");
    }

    my $sudoersfile = find_sudoers() or  FATAL_OUT( "could not find system suoders file");
    copy_sudoers_to_temp_and_unmap_topcat($sudoersfile, $class, $user);
    copy_temp_to_sudoers_if_verified($sudoersfile);
}

# map tigger sudoers settings
sub map_tigger_settings($$)
{
    my ($class, $user) = @_;
    if ($user)
    {
        DEBUG_OUT("Map 3.0 $class $user sudoers settings");
    }
    else
    {
        DEBUG_OUT("Map 3.0 $class sudoers settings");
    }

    CentrifyDC::GP::Mapper::Map($file, $user);
}


# unmap tigger sudoers settings
sub unmap_tigger_settings($$)
{
    my ($class, $user) = @_;
    if ($user)
    {
        DEBUG_OUT("UnMap 3.0 $class $user sudoers settings");
    }
    else
    {
        DEBUG_OUT("UnMap 3.0 $class sudoers settings");
    }

    CentrifyDC::GP::Mapper::UnMap($file, $user);
}


sub sort_numerically() #callback for sort routine
#lines are named line1, line10, line11, line2, line3 etc.
#order should be line1, line2 .. line10 line11
#for users, lines are named user1 line10 line2 user3
#order should be user1 line2 user3 ... line10
{
    my $a_num; my $b_num; #extract and compare the digits
    $a =~ m/^(line|user)(\d*)$/; $a_num = $2;
    $b =~ m/^(line|user)(\d*)$/; $b_num = $2;
    return -1 if $a_num < $b_num;
    return  1 if $a_num > $b_num;
    return  0;
}


# 3.0 machine setting
$file = {
    'file_data_expr' => {
      'REG_SZ' => [
        '$value = \'root\' if ($value eq \'=\')',
      ],
    },
    'lock' => '$path.gp.lock',
    'match_expr' => [
      '/^(\S+)\s+[^=]+=(.*)/',
    ],
    'path' => [
      '/etc/sudoers',
      '/usr/local/etc/sudoers',
      '/usr/local/etc/sudo/sudoers',
    ],
    'lock' => "$TEMP_DIR/gp.sudoers.lock",
    'pre_command' => '::find_sudoers()',
    'value_map' => {
      '' => {
        'additive' => '1',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/SuDo',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => '',
        'value_type' => 'all',
      },
    },
    'verify_command' => '::verify_sudoers()',
    'write_data' => '$value  $::hostname=$data\n',
};

#
# Check registry to see if it's necessary to update sudoers file.
# If there's no registry setting, this script will quit.
# This is just a preliminary check. sudoers file may not need update even if
# this function returns true.
#
#   $_[0]:  args
#
#   return: 1 - may need to update sudoers
#           0 - no need to update sudoers
#
sub is_update_necessary($)
{
    my $args = $_[0];

    # both 3.x machine/user mapper need to check 4.x machine setting
    my $reg_v4_machine = CentrifyDC::GP::RegHelper->new($args->action(), 'machine', $REGKEY_SUDO_ENABLED{'machine'}, 'sudo.enabled', undef);
    $reg_v4_machine or FATAL_OUT("Cannot create RegHelper instance");
    $reg_v4_machine->load();

    my $reg_v3 = CentrifyDC::GP::RegHelper->new($args->action(), $args->class(), $TIGGERSTYLE_REGKEY{$args->class()}, undef, undef);
    $reg_v3 or FATAL_OUT("Cannot create RegHelper instance");
    $reg_v3->load();

    # if 4.x machine registry setting or 3.x registry setting exists, we may
    # need to update sudoers file
    if (defined($reg_v4_machine->get('current')) or
        defined($reg_v4_machine->get('previous')) or
        ! IsEmpty($reg_v3->get('current')) or
        ! IsEmpty($reg_v3->get('previous')))
    {
        return 1;
    }

    # for unmap, if 3.x local registry setting exists, then we may need to
    # restore it. 4.x doesn't have local registry setting.
    if (! $args->isMap() and ! IsEmpty($reg_v3->get('local')))
    {
        return 1;
    }

    DEBUG_OUT("No sudoers registry setting. No need to update sudoers file.");
    return 0;
}

### MAIN #######################################################################

my $args = CentrifyDC::GP::Args->new();

my $user  = $args->user();
my $class = $args->class();

#
# if sudo is not installed, then we need to do nothing.
#
is_sudo_installed() or exit(0);

# If class is user, then convert 3.0 machine setting into user setting.
if ($class eq "user")
{
    $file->{match_expr} = [
      '/^$user\s+[^=]+=\(([^\)]+)\)\s*(.*)\n/',
      '/^$user\s+[^=]+(=)\s*(.*)\n/',
    ];
    $file->{value_map}->{''}{reg_class} = 'user';
    $file->{write_data} = '$user  $::hostname=($value) $data\n';
}

# we need to check whether 4.0 machine setting exists or not, so always load
# machine registry.
CentrifyDC::GP::Registry::Load(undef);
if ($class eq "user")
{
    CentrifyDC::GP::Registry::Load($user);
}

#
# check if it's necessary to update sudoers file
#
is_update_necessary($args) or exit(0);

# the sudoers policy is different from other GPs with regard to the following:
# there is a sudo.enabled value which tells whether the policy should apply or 
# not. in both cases though, there will be values in the unixsettings/sudo registry key.
# (as the gpgui does not want to throw away the stuff the user entered)
# this means that we must only map the registry values to /etc/sudoers if 
# we are told to map, and if the sudo.enabled registry value is present and non-zero
# if sudo.enabled is not set or zero, we have to remove any previously mapped values
# from /etc/sudoers in order to stay in synch with what the admin specified in the GPO.
# that's why we have remove lines even when told to map.



if ($args->isMap())
{
    # if there's topcat settings, then remove old tigger settings.
    if (topcat_policies_present("machine", $user))
    {
        if (tigger_policies_present($class, $user))
        {
            # remove current 3.0 setting
            unmap_tigger_settings($class, $user);
        }
        else
        {
            # if current 3.0 setting doesn't exist, remove previous 3.0 setting.
            # for example, if we set 3.0 setting from "Enabled" to "Disabled"
            # at DC side, then we need to remove old setting.
            map_tigger_settings($class, $user);
        }
        if ($class eq "machine")
        {
            if (sudo_is_enabled($class, $user))
            {
                add_topcat_to_sudoers($class, $user);
            }
            else
            {
                remove_topcat_from_sudoers($class, $user);
            }
        }
    }
    else
    {
        map_tigger_settings($class, $user);
        if ($class eq "machine")
        {
            remove_topcat_from_sudoers($class, $user);
        }
    }
}
else    # unmap
{
    unmap_tigger_settings($class, $user);
    if ($class eq "machine")
    {
        remove_topcat_from_sudoers($class, $user);
    }
}

# do cleanup
END {
    unlink "$temp_file";
}

