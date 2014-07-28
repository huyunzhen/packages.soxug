#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2008-2014 Centrify Corporation. All rights reserved.
#
# Machine mapper script that add arbitrary name/value pair to centrifydc.conf.
#
#  User can specify name/value pair in a list in Windows GPOE:
#       adclient.foo: foo
#       adclient.bar: bar
#  These name/value pairs will then be added into centrifydc.conf.
#
#  This is useful for seldom used parameters which really don't justify
#  their own GP.
#
#  The mapper script need to read both current/previous/local registry to
#  get a complete list of name/value pairs.
#
#
#  Map:     add or remove name/value pair based on registry setting
#             Not configured:  restore local setting
#             Enabled:         add new name/value pair and remove old one
#             Disabled:        restore local setting
#
#  Unmap:   restore local setting
#
# Parameters: <map|unmap> mode
#   map|unmap   action to take
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
use CentrifyDC::GP::RegHelper;
use CentrifyDC::GP::Mapper;
use CentrifyDC::GP::General qw(:debug IsEmpty);

my $file;

my $REGKEY = "Software/Policies/Centrify/CentrifyDC/Settings/AdditionalProperties";



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
    'value_map' => { },
    'write_data' => '$value: $data\n',
};



# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $args = CentrifyDC::GP::Args->new('machine');

CentrifyDC::GP::Registry::Load($args->user());

my $reg = CentrifyDC::GP::RegHelper->new($args->action(), $args->class(), $REGKEY, undef, undef);
$reg or FATAL_OUT("Cannot create RegHelper instance");
$reg->load();

my $properties = {};

# get list of properties from current/previous/local registry
foreach my $group (qw(current previous local))
{
    my $hash = $reg->get($group);
    if (! IsEmpty($hash))
    {
        foreach my $key (keys %$hash)
        {
            $properties->{$key} = 1;
        }
    }
}

# populate $file so that it can be handled by generic mapper
foreach my $key (keys %$properties)
{
    TRACE_OUT("set parameter: $key");

    $file->{value_map}->{$key} = {
        'reg_class'  => $args->class(),
        'reg_key'    => $REGKEY,
        'reg_type'   => [ 'REG_SZ', ],
        'reg_value'  => $key,
        'value_type' => 'named',
    },
}

if ($args->isMap())
{
    CentrifyDC::GP::Mapper::Map($file, $args->user());
}
else
{
    CentrifyDC::GP::Mapper::UnMap($file, $args->user());
}

