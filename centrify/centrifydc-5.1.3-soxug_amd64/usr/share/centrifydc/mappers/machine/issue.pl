#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2014 Centrify Corporation. All rights reserved.
#
##############################################################################


use strict;
use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Mapper;
use CentrifyDC::GP::GPIsolation qw(GetRegKey);

my $file;
my $action;
my $user;
$file = {
    'create' => '0644',
    'file_data_expr' => {
      'REG_SZ' => [
        '$data =~ s/\n$//',
      ],
    },
    'lock' => '/etc/issue.lock',
    'match_expr' => [
      '/()(.*)\n/s',
    ],
    'multi_sz_separator' => '\n',
    'multi_sz_split' => ',',
    'newline' => "<ENTIRE_FILE>",
    'path' => [
      '/etc/issue',
    ],
    'value_map' => {
      '' => {
        'reg_class' => 'machine',
        'reg_key' => GetRegKey("LegalNoticeText"),
        'reg_type' => [
          'REG_MULTI_SZ',
          'REG_SZ',
        ],
        'reg_value' => 'LegalNoticeText',
        'value_type' => 'named',
      },
    },
    'write_data' => '$data\n',
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
