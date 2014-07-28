#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2007-2014 Centrify Corporation. All rights reserved.
#
# Configure machine policies that have backward compatibility issue.
#
#  This machine mapper script will handle generic policies that have
#  different keys or values in different versions of CDC. It should only
#  contain policies that need to change centrifydc.conf.
#
#  For example, if a policy's registry key was key1 in 3.x, but was changed to
#  key2 in 4.x, then this mapper should be able to handle both key so that
#  it can work with both 3.x and 4.x domain controller.
#
#  Please notice that this script needs to check both current and previous
#  registry value to determine which version of policy is currently in use.
#
#  All policies in this mapper should be documented below.
#
#
#  --- DirectControl 2.x Compatible ------------------------------------------
#
#   registry value: adclient.version2.compatible
#   The registry key is different in 3.x and 4.x.
#     3.x:  Software/Policies/Centrify/CentrifyDC/Settings
#     4.x:  Software/Policies/Centrify/CentrifyDC/Settings/Miscellaneous
#   Default is 3.x setting. If found 4.x setting, use 4.x setting.
#
#  --- Home Directory Permissions --------------------------------------------
#
#   registry key: Software/Policies/Centrify/CentrifyDC/Settings/Pam
#   The registry value is different in 3.x and 4.x
#     3.x:  a set of checkbox to set individual permission, i.e. userread,
#           userwrite, etc., each corresponding to a registry value. These
#           values are resembled in mapper script to create an octal number,
#           i.e. 0700.
#           registry value: pam_hidden_homedir_perms_enable,
#                           pam_hidden_homedir_perms_group_execute,
#                           pam_hidden_homedir_perms_group_read,
#                           pam_hidden_homedir_perms_group_write,
#                           pam_hidden_homedir_perms_other_execute,
#                           pam_hidden_homedir_perms_other_read,
#                           pam_hidden_homedir_perms_other_write,
#                           pam_hidden_homedir_perms_user_execute,
#                           pam_hidden_homedir_perms_user_read,
#                           pam_hidden_homedir_perms_user_write
#     4.x:  octal number, i.e. 0700.
#           registry value: pam.homedir.perms,
#                           pam.homedir.perms.enable
#   Default is 3.x setting. If found 4.x setting, use 4.x setting.
#
#  --- Split large group membership ------------------------------------------
#
#   registry key: Software/Policies/Centrify/CentrifyDC/Settings/Login
#   The registry value is different in 3.x and 4.x
#     3.x:  nss.split.group.members
#     4.x:  nss.split.group.membership
#   Default is 3.x setting. If found 4.x setting, use 4.x setting.
#
##############################################################################

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::Registry;
use CentrifyDC::GP::Mapper;
use CentrifyDC::GP::General qw(:debug);

my $file;

# DirectControl 2.x Compatible
my $REGKEY_2XCOMPATIBLE_V3 = "Software/Policies/Centrify/CentrifyDC/Settings";
my $REGKEY_2XCOMPATIBLE_V4 = "Software/Policies/Centrify/CentrifyDC/Settings/Miscellaneous";

# Home Directory Permissions
my $REGKEY_HOMEDIRPERMS = "Software/Policies/Centrify/CentrifyDC/Settings/Pam";



# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

sub ::centrifydc_changed()
{
    open(FH, '>/var/centrifydc/reg/do_adreload'); 
    close(FH); 
}



# >>> DATA >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

$file = {
    'comment_markers' => [
      '#',
    ],
    'hierarchy_separator' => '.',
    'list_expr' => ', *| +',
    'list_separator' => ', ',
    'match_expr' => [
      '/^\s*([^\s:=]+)[:=]\s*(.*)/',
    ],
    'parent_expr' => '^(.*)\.([^\.]+)$',
    'path' => [
      '/etc/centrifydc/centrifydc.conf',
    ],
    'lock' => '/etc/centrifydc/centrifydc.conf.lock',
    'post_command' => '::centrifydc_changed()',
    'value_map' => {

      # DirectControl 2.x Compatible
      'adclient.version2.compatible' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_2XCOMPATIBLE_V3",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'adclient.version2.compatible',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },

      # Home Directory Permissions
      'pam.homedir.perms' => {
        'active' => '$value_map->{pam_hidden_homedir_perms_enable}{reg_data} eq "true"',
        'data_value' => 'pam_hidden_homedir_perms_enable',
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_data_expr' => [
          '$data = sprintf "%04o", ($value_map->{pam_hidden_homedir_perms_user_read}{reg_data} << 8) + ($value_map->{pam_hidden_homedir_perms_user_write}{reg_data} << 7) + ($value_map->{pam_hidden_homedir_perms_user_execute}{reg_data} << 6) + ($value_map->{pam_hidden_homedir_perms_group_read}{reg_data} << 5) + ($value_map->{pam_hidden_homedir_perms_group_write}{reg_data} << 4) + ($value_map->{pam_hidden_homedir_perms_group_execute}{reg_data} << 3) + ($value_map->{pam_hidden_homedir_perms_other_read}{reg_data} << 2) + ($value_map->{pam_hidden_homedir_perms_other_write}{reg_data} << 1) + ($value_map->{pam_hidden_homedir_perms_other_execute}{reg_data})',
        ],
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.homedir.perms',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'pam_hidden_homedir_perms_enable' => {
        'active' => '0',
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_enable',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      'pam_hidden_homedir_perms_group_execute' => {
        'active' => '0',
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_group_execute',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      'pam_hidden_homedir_perms_group_read' => {
        'active' => '0',
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_group_read',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      'pam_hidden_homedir_perms_group_write' => {
        'active' => '0',
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_group_write',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      'pam_hidden_homedir_perms_other_execute' => {
        'active' => '0',
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_other_execute',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      'pam_hidden_homedir_perms_other_read' => {
        'active' => '0',
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_other_read',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      'pam_hidden_homedir_perms_other_write' => {
        'active' => '0',
        'default_data' => '0',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_other_write',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      'pam_hidden_homedir_perms_user_execute' => {
        'active' => '0',
        'default_data' => '1',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_user_execute',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      'pam_hidden_homedir_perms_user_read' => {
        'active' => '0',
        'default_data' => '1',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_user_read',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      'pam_hidden_homedir_perms_user_write' => {
        'active' => '0',
        'default_data' => '1',
        'reg_class' => 'machine',
        'reg_key' => "$REGKEY_HOMEDIRPERMS",
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam_hidden_homedir_perms_user_write',
        'value_type' => 'named',
        'valueoff' => '0',
        'valueon' => '1',
      },
      
      #Split large group membership
      'nss.split.group.membership' => {
        'default_data' => 'false',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Login',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'nss.split.group.members',
        'value_type' => 'named',
        'valueoff' => 'false',
        'valueon' => 'true',
      },
      
    },
    'write_data' => '$value: $data\n',
};



# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $args = CentrifyDC::GP::Args->new();

CentrifyDC::GP::Registry::Load($args->user());


# >>> DirectControl 2.x Compatible -------------------------------------------

# if 4.x setting exists, use 4.x setting.
my $v4_2xcompatible_cur = (CentrifyDC::GP::Registry::Query($args->class(), $REGKEY_2XCOMPATIBLE_V4, "current", "adclient.version2.compatible"))[1];
my $v4_2xcompatible_pre = (CentrifyDC::GP::Registry::Query($args->class(), $REGKEY_2XCOMPATIBLE_V4, "previous", "adclient.version2.compatible"))[1];

if (defined $v4_2xcompatible_cur || defined $v4_2xcompatible_pre)
{
    DEBUG_OUT("4.x setting of DirectControl 2.x Compatible policy found. Use 4.x setting.\n");
    $file->{value_map}->{'adclient.version2.compatible'}{reg_key} = "$REGKEY_2XCOMPATIBLE_V4";
}
# <<< DirectControl 2.x Compatible -------------------------------------------


# >>> Home Directory Permissions ---------------------------------------------

# if 4.x setting exists, use 4.x setting.
my $v4_homedirperms_cur = (CentrifyDC::GP::Registry::Query($args->class(), $REGKEY_HOMEDIRPERMS, "current", "pam.homedir.perms.enable"))[1];
my $v4_homedirperms_pre = (CentrifyDC::GP::Registry::Query($args->class(), $REGKEY_HOMEDIRPERMS, "previous", "pam.homedir.perms.enable"))[1];

if (defined $v4_homedirperms_cur || defined $v4_homedirperms_pre)
{
    DEBUG_OUT("4.x setting of Home Directory Permissions policy found. Use 4.x setting.\n");
    $file->{value_map}->{'pam.homedir.perms'} = {
        'default_data' => '0700',
        'reg_class' => 'machine',
        'reg_key' => 'Software/Policies/Centrify/CentrifyDC/Settings/Pam',
        'reg_type' => [
          'REG_SZ',
        ],
        'reg_value' => 'pam.homedir.perms',
        'value_type' => 'named',
    };
}
# <<< Home Directory Permissions ---------------------------------------------


# >>> Split large group membership -------------------------------------------

# if 4.x setting exists, use 4.x setting.
my $v4_splitgroup_cur = (CentrifyDC::GP::Registry::Query($args->class(), "Software/Policies/Centrify/CentrifyDC/Settings/Login", "current", "nss.split.group.membership"))[1];
my $v4_splitgroup_pre = (CentrifyDC::GP::Registry::Query($args->class(), "Software/Policies/Centrify/CentrifyDC/Settings/Login", "previous", "nss.split.group.membership"))[1];

if (defined $v4_splitgroup_cur || defined $v4_splitgroup_pre)
{
    DEBUG_OUT("4.x setting of Split large group membership policy found. Use 4.x setting.\n");
    $file->{value_map}->{'nss.split.group.membership'}->{'reg_value'} = 'nss.split.group.membership';
}

# <<< Split large group membership -------------------------------------------

if ($args->isMap())
{
    CentrifyDC::GP::Mapper::Map($file, $args->user());
}
else
{
    CentrifyDC::GP::Mapper::UnMap($file, $args->user());
}

