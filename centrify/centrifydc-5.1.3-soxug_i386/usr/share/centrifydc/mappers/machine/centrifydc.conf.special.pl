#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2011-2014 Centrify Corporation. All rights reserved.
#
# Machine mapper script to configure settings to Centrify DirectControl 
# configuration file in a specific way (as opposed to the generic mapper 
# script centrifydc.conf.pl).
#
#  This script handles the following types of specific settings:
#  1. Settings pre-defined by Windows side
#  2. Settings deprecated and superseded by new settings
#
#  Settings pre-defined by Windows side
#  ------------------------------------
#  These settings have pre-defined registry keys and values. So this script 
#  will write the settings to centrifydc.conf following the associations 
#  defined in the hash below.
#
#  Settings deprecated and superseded by new settings
#  --------------------------------------------------
#  These settings are superseded by new settings, so this script will write to 
#  centrifydc.conf with the new setting names.
#
#  Note that we do it this way because we need to support old versions of 
#  Centrify DirectControl. The old versions do not understand the new setting 
#  names. So the GP files need to keep the registry keys and values unchanged.
#
#  As a result, we use this mapper script to handle the new associations.
#
#
#
#  Map:     Configure settings to centrifydc.conf
#
#  Unmap:   Restore original settings
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

use CentrifyDC::GP::Mapper;
use CentrifyDC::GP::GPIsolation qw(GetRegKey GetRegValType);

my $file;
my $action;
my $user;
$file = {
    'comment_markers' => [
        '#',
    ],
    'hierarchy_separator' => '.',
    'list_expr' => ', *| +',
    'list_separator' => ', ',
    'lock' => '/etc/centrifydc/centrifydc.conf.lock',
    'match_expr' => [
        '/^\s*([^\s:=]+)[:=]\s*(.*)/',
    ],
    'named_list_separator' => ',',
    'parent_expr' => '^(.*)\.([^\.]+)$',
    'path' => [
        '/etc/centrifydc/centrifydc.conf',
    ],
    'post_action' => [
        'DO_ADRELOAD',
    ],

    'value_map' => {

        # Settings pre-defined by Windows side

        'adclient.sntp.enabled' => {
            'default_data' => '0',
            'file_valueoff' => 'false',
            'file_valueon' => 'true',
            'reg_class' => 'machine',
            'reg_key' => GetRegKey('adclient.sntp.enabled'),
            'reg_type' => [
                'REG_DWORD',
            ],
            'reg_value' => 'Enabled',
            'value_type' => 'named',
            'valueoff' => '0',
            'valueon' => '1',
        },

        'adclient.sntp.poll' => {
            'default_data' => '0',
            'reg_class' => 'machine',
            'reg_key' => GetRegKey('adclient.sntp.poll'),
            'reg_type' => [
                'REG_DWORD',
            ],
            'reg_value' => 'MaxPollInterval',
            'value_type' => 'named',
        },

        'gp.refresh.disable' => {
            'default_data' => '0',
            'file_valueoff' => 'false',
            'file_valueon' => 'true',
            'reg_class' => 'machine',
            'reg_key' => GetRegKey('gp.refresh.disable'),
            'reg_type' => [
                'REG_DWORD',
            ],
            'reg_value' => 'DisableBkGndGroupPolicy',
            'value_type' => 'named',
        },

        'pam.password.expiry.warn' => {
            'default_data' => '14',
            'reg_class' => 'machine',
            'reg_key' => GetRegKey('pam.password.expiry.warn'),
            'reg_type' => [
                'REG_DWORD',
            ],
            'reg_value' => 'PasswordExpiryWarning',
            'value_type' => 'named',
        },

        'secedit.system.access.lockoutbadcount' => {
            'reg_class' => 'machine',
            'reg_key' => GetRegKey('secedit.system.access.lockoutbadcount'),
            'reg_type' => [
                GetRegValType('secedit.system.access.lockoutbadcount'),
            ],
            'reg_value' => 'LockoutBadCount',
            'value_type' => 'named',
        },

        'secedit.system.access.lockoutduration' => {
            'reg_class' => 'machine',
            'reg_key' => GetRegKey('secedit.system.access.lockoutduration'),
            'reg_type' => [
                GetRegValType('secedit.system.access.lockoutduration'),
            ],
            'reg_value' => 'LockoutDuration',
            'reg_data_expr' => [
                '$data = ($data eq "0") ? -1 : $data',
            ],
            'value_type' => 'named',
        },

        'secedit.system.access.maximumpasswordage' => {
            'reg_class' => 'machine',
            'reg_key' => GetRegKey('secedit.system.access.maximumpasswordage'),
            'reg_type' => [
                GetRegValType('secedit.system.access.maximumpasswordage'),
            ],
            'reg_value' => 'MaximumPasswordAge',
            'reg_data_expr' => [
                '$data = ($data eq "0") ? -1 : $data',
            ],
            'value_type' => 'named',
        },

        'secedit.system.access.minimumpasswordage' => {
            'reg_class' => 'machine',
            'reg_key' => GetRegKey('secedit.system.access.minimumpasswordage'),
            'reg_type' => [
                GetRegValType('secedit.system.access.minimumpasswordage'),
            ],
            'reg_value' => 'MinimumPasswordAge',
            'value_type' => 'named',
        },

        'audittrail.targets' => {
            'reg_class' => 'machine',
            'reg_key' => 'Software/Policies/Centrify/AuditTrail',
            'reg_type' => ['REG_DWORD'],
            'reg_value' => 'AuditTrailTargets',
            'value_type' => 'named',
        },

        # Settings deprecated and superseded by new settings

        'adclient.refresh.interval.dz' => {
            'reg_class' => 'machine',
            'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Timeouts',
            'reg_type' => ['REG_DWORD'],
            'reg_value' => 'adclient.azman.refresh.interval',
            'value_type' => 'named',
        },

    },

    'write_data' => '$value: $data\n',
};

$action = $ARGV[0];
my $mode = $ARGV[2] ? $ARGV[2] : $ARGV[1];
$user = $ARGV[2] ? $ARGV[1] : undef;

if ($action eq "unmap")
{
    CentrifyDC::GP::Mapper::UnMap($file, $user);
}
else
{
    CentrifyDC::GP::Mapper::Map($file, $user);
}
