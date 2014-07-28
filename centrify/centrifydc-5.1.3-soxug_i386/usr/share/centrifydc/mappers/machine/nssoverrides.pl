#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2005-2014 Centrify Corporation. All rights reserved.
#
# Machine mapper script that configures NSS passwd/group override settings.
#
#  The script get passwd/group override settings from group policy and write
#  them into override files.
#
#  DO NOT edit the override file manually if NSS override group policy is
#  enabled.
#
#  Unlike centrifydc.conf, the override file is treated as a whole.
#  If override group policy is enabled, the whole override file will
#  be generated from gp setting, and original setting will be saved
#  for future restoration.
#
#  The override files can be specified in gp (3.x only) or centrifydc.conf.
#  If not specified, default will be:
#
#       passwd: /etc/centrifydc/passwd.ovr
#       group:  /etc/centrifydc/group.ovr
#
#  Override file sample can be found in passwd.ovr.sample and group.ovr.sample.
#
#   An empty (or non-existant) file is the equivalent of adding this line:
#       +::::::
#
#  Map:     modify override file based on group policy setting.
#              Not Configured: restore original setting
#              Enable:         write gp setting into override file
#              Disable:        remove override file
#
#  Unmap:   restore original setting
#
#
# Parameters: <map|unmap> mode
#   map|unmap   action to take
#   mode        mode (not used)
#
#
# Exit value:
#   0   Normal
#   1   Error
#   2   usage
#
##############################################################################

use strict;

use lib '/usr/share/centrifydc/perl';

use File::Copy;

use CentrifyDC::GP::Registry;
use CentrifyDC::Config;
use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug IsEmpty ReadFile WriteFile);
use CentrifyDC::GP::RegHelper;

# comment line at the beginning of override files
my @MARKER = (
    '######################################################################',
    '#        DO NOT EDIT. CentrifyDC group policy generated file.        #',
    '#       Changes to this file can be made through group policy.       #',
    '######################################################################',
);

my @OVERRIDE_TYPES = qw(passwd group);

my %REGKEY = (
    passwd => 'software/policies/centrify/centrifydc/settings/nssoverrides/passwd',
    group  => 'software/policies/centrify/centrifydc/settings/nssoverrides/group',
);

# hash for override file
my $override_file = {};

# hash of RegHelper that store combined override registry setting
my $reg_overrides_combined = {};

sub DoAdFlush();
sub GetOverrideFilePath($);
sub GetSettingForType($$);
sub GetSetting($);
sub UpdateSysSetting($);
sub Map();
sub UnMap();



# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# create file for adreload/adflush
#
sub DoAdFlush()
{
    open (FH, '>/var/centrifydc/reg/do_adflush');
    close (FH);
    open (FH, '>/var/centrifydc/reg/do_adreload');
    close (FH);
}

#
# get path of override file.
#
#   $_[0]:  type    (passwd/group)
#
#   return: string  - override file path
#
sub GetOverrideFilePath($)
{
    my $type = $_[0];

    #
    # try to get filename from centrifydc.conf property:
    #   passwd: nss.passwd.override
    #   group:  nss.group.override
    #
    my $file = $CentrifyDC::Config::properties{"nss.$type.override"};
    if (defined($file))
    {
        $file =~ s/^file://;
    }
    else
    {
        #
        # no setting is found in centrifydc.conf, use default setting:
        #   passwd: /etc/centrifydc/passwd.ovr
        #   group:  /etc/centrifydc/group.ovr
        #
        $file = "/etc/centrifydc/$type.ovr";
    }

    return $file;
}

#
# get registry/system setting for specified override type (passwd/group).
#
# combine current/previous settings of nss.overrides and nss.overrides.all
# into a new registry setting nss.overrides.combined.
#
# there are two registry values that control override setting:
#
#   nss.overrides:      +paul:psmith:x:::Paul Smith::/bin/bash
#   nss.overrides.all:  +:::::::
#
# both of them will get into override file. To compare them with system
# setting, we need to combine them into one registry value separated by
# semicolon:
#
#   nss.overrides.combined: +paul:psmith:x:::Paul Smith::/bin/bash;+:::::::
#
# then we can use RegHelper class to compare registry/system setting and store
# local setting in this registry value easily.
#
# if setting is disabled, its registry data will be set to ''. without this we
# won't be able to tell the difference between 'disabled' and 'not configured'.
#
#   $_[0]:  action  (map/unmap)
#   $_[1]:  type    (passwd/group)
#
#   return: 1       - successful
#           undef   - failed
#
sub GetSettingForType($$)
{
    my ($action, $type) = @_;

    $override_file->{$type} = GetOverrideFilePath($type);

    my $reg_overrides = CentrifyDC::GP::RegHelper->new($action, 'machine', $REGKEY{$type}, 'nss.overrides', undef);
    $reg_overrides or return undef;
    $reg_overrides->load();
    my $reg_overrides_all = CentrifyDC::GP::RegHelper->new($action, 'machine', $REGKEY{$type}, 'nss.overrides.all', undef);
    $reg_overrides_all or return undef;
    $reg_overrides_all->load();

    $reg_overrides_combined->{$type} = CentrifyDC::GP::RegHelper->new($action, 'machine', $REGKEY{$type}, 'nss.overrides.combined', undef);
    $reg_overrides_combined->{$type} or return undef;
    $reg_overrides_combined->{$type}->load();

    my $reg_enabled = CentrifyDC::GP::RegHelper->new($action, 'machine', $REGKEY{$type}, 'nss.overrides.enabled', undef);
    $reg_enabled or return undef;
    $reg_enabled->load();

    foreach my $group (qw(current previous))
    {
        my $setting = $reg_overrides->get($group);
        my $setting_all = $reg_overrides_all->get($group);
        my $array = [];

        if (defined($setting))
        {
            $setting =~ s/^\s+//;
            $setting =~ s/\s+$//;
            if ($setting ne '')
            {
                push(@$array, $setting);
            }
        }
        if (defined($setting_all))
        {
            $setting_all =~ s/^\s+//;
            $setting_all =~ s/\s+$//;
            if ($setting_all ne '')
            {
                push(@$array, $setting_all);
            }
        }
        if (! IsEmpty($array))
        {
            $reg_overrides_combined->{$type}->set($group, join(';', @$array));
        }

        #
        # get gp status (enabled = 1, disabled = 0, not configured = undef)
        # 4.x has a reg value nss.overrides.enabled, enable is 1, disable is 0.
        # 3.x doesn't have this reg value, but if disabled, nss.overrides.all
        # will be ' '.
        #
        my $is_enabled = $reg_enabled->get($group);
        if (! defined($is_enabled))
        {
            my $setting_3x = $reg_overrides_all->get($group);
            if (defined($setting_3x))
            {
                $is_enabled = ($setting_3x eq ' ') ? 0 : 1;
            }
        }

        # set registry value to empty string '' to represent 'disabled'.
        if (defined($is_enabled) and $is_enabled eq '0')
        {
            $reg_overrides_combined->{$type}->set($group, '');
        }
    }

    #
    # get setting from override file, combine settings into a string
    # and store as system setting. comments will not be saved.
    #
    my $sys_string = ReadFile($override_file->{$type});
    if (defined($sys_string))
    {
        my $array = [];
        my @sys_array = split(/\n/, $sys_string);
        foreach my $line (@sys_array)
        {
            if (! ($line =~ /^#/))
            {
                # ignore comments and empty lines
                $line =~ s/^\s+//;
                $line =~ s/\s+$//;
                if ($line ne '')
                {
                    push(@$array, $line);
                }
            }
        }
        if (! IsEmpty($array))
        {
            $reg_overrides_combined->{$type}->set('system', join(';', @$array));
        }
        else
        {
            $reg_overrides_combined->{$type}->set('system', '');
        }
    }
    else
    {
        $reg_overrides_combined->{$type}->set('system', '');
    }

    return 1;
}

#
# get registry/system setting.
#
#   $_[0]:  action  (map/unmap)
#
#   return: 1       - successful
#           undef   - failed
#
sub GetSetting($)
{
    my $action = $_[0];

    foreach my $type (@OVERRIDE_TYPES)
    {
        GetSettingForType($action, $type);
    }

    return 1;
}


#
# update override file
#
#   $_[0]:  action  (map/unmap)
#
#   return: 1       - successful
#           undef   - failed
#
sub UpdateSysSetting($)
{
    my $action = $_[0];

    my $ret = 1;
    my $changed = 0;

    foreach my $type (@OVERRIDE_TYPES)
    {
        my $group = $reg_overrides_combined->{$type}->getGroupToApply();
        if ($group)
        {
            my $setting = $reg_overrides_combined->{$type}->get($group);
            if (defined($setting) and $setting ne '')
            {
                # write override file
                DEBUG_OUT("Write $type override file " . $override_file->{$type});

                $setting =~ s/;/\n/g;

                # if setting is from gp, add comments into file header
                my $str = '';
                if ($group ne 'local')
                {
                    $str .= join("\n", @MARKER);
                    $str .= "\n";
                }
                $str .= "$setting\n";
                my $rc = WriteFile($override_file->{$type}, $str);
                if (! $rc)
                {
                    ERROR_OUT("Cannot write $type override file " . $override_file->{$type});
                    $ret = undef;
                }
                else
                {
                    $changed = 1;
                }
            }
            else
            {
                # remove override file
                DEBUG_OUT("Remove NSS $type override setting");
                my $rc = unlink($override_file->{$type});
                if (! $rc)
                {
                    ERROR_OUT("Cannot remove $type override file " . $override_file->{$type});
                    $ret = undef;
                }
                else
                {
                    $changed = 1;
                }
            }
        } # if ($group)
    }

    if ($changed)
    {
        DEBUG_OUT("NSS override setting changed. Need to do adflush.");
        DoAdFlush();
    }

    return 1;
}

#
# map
#
#   return: 1       - successful
#           undef   - failed
#
sub Map()
{
    my $ret = 1;

    UpdateSysSetting('map') or $ret = undef;

    return $ret;
}

#
# unmap
#
#   return: 1       - successful
#           undef   - failed
#
sub UnMap()
{
    my $ret = 1;

    UpdateSysSetting('unmap') or $ret = undef;

    return $ret;
}



# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $args = CentrifyDC::GP::Args->new('machine');

CentrifyDC::GP::Registry::Load(undef);

GetSetting($args->action()) or FATAL_OUT("Cannot get setting");

my $ret = 0;

$args->isMap() ? ($ret = Map()) : ($ret = UnMap());

$ret or FATAL_OUT();

