##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl mapper script Directory Access module.
#
# This module uses adquery and ldapsearch to get user info.
#
##############################################################################

use strict;

package CentrifyDC::GP::DirectoryAccess;
my $VERSION = '1.0';
require 5.000;

use vars qw(@ISA @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(GetAttribute GetQueryInfo);

use CentrifyDC::GP::General qw(:debug IsEmpty RunCommand);

my $ADQUERY     = '/usr/bin/adquery';
my $LDAPSEARCH  = '/usr/share/centrifydc/bin/ldapsearch';

sub GetQueryInfo($$);
sub GetAttribute($$$$$;$);



#
# Use adquery to get all information of specified user/group
#
#   $_[0]: type (user/group)
#   $_[1]: user/group name
#
#   return: 
#       hash reference  - user/group information
#                         => {
#                            samAccountName => user,
#                            canonicalName  => domain/OU/user,
#                            ...
#       undef           - failed
#
sub GetQueryInfo($$)
{
    my ($type, $name) = @_;

    if (! defined($type) || ($type ne 'user' && $type ne 'group'))
    {
        ERROR_OUT("Cannot query: incorrect type");
        return;
    }

    if (! defined($name))
    {
        ERROR_OUT("Cannot query: name undefined");
        return;
    }

    TRACE_OUT("Get all information of $type [$name]");

    if (! -f $ADQUERY or ! -x $ADQUERY)
    {
        ERROR_OUT("Cannot find adquery");
        return;
    }

    my ($ret, $output) = RunCommand("$ADQUERY $type -A '$name'");

    if (! defined($ret) or $ret ne 0 or ! defined($output))
    {
        ERROR_OUT("adquery failed: $output");
        return;
    }

    chomp $output;

    my $info;
    my @arr = split('\n', $output);

    foreach my $line (@arr)
    {
        chomp($line);
        if ($line =~ m/([^:]+):(.*)$/)
        {
            $info->{$1} = $2;
        }
    }

    TRACE_OUT("=== begin $type $name info ===");
    foreach my $key (sort keys %$info)
    {
        my $val = $info->{$key};
        TRACE_OUT("| %-20s: [%s]", $key, $val);
    }
    TRACE_OUT("=== end $type $name info ===");

    return $info;
}

#
# Use ldapsearch to get object attribute
#
#   $_[0]: user (if specified, run ldapsearch as user)
#   $_[1]: options
#   $_[2]: ldapuri
#   $_[3]: searchbase
#   $_[4]: filter
#   $_[5]: attribute (optional. if ignored, return the whole output of ldapsearch)
#
#   return: 
#       $1: 
#           1       - successful
#           undef   - failed
#       $2:
#           string  - attribute setting
#
sub GetAttribute($$$$$;$)
{
    my ($user, $options, $ldapuri, $searchbase, $filter, $attribute) = @_;

    defined($options) or $options = '';
    defined($ldapuri) or return;
    defined($searchbase) or return;
    defined($filter) or $filter = '';
    defined($attribute) or $attribute = '';

    if ($options eq '')
    {
        if (defined($user))
        {
            $options = "-r -Q -LLL";
        }
        else
        {
            $options = "-r -m -Q -LLL";
        }
    }

    TRACE_OUT("Get attribute:\n options: [$options]\n ldapuri: [$ldapuri]\nsearchbase: [$searchbase]\nfilter: [$filter]\n Attribute: [$attribute]");

    if (! -f $LDAPSEARCH or ! -x $LDAPSEARCH)
    {
        ERROR_OUT("Cannot find ldapsearch");
        return;
    }

    my $command = '';

    # if current user is different from the specified user, use su to run command
    my $su = 0;
    if (defined($user))
    {
        my $cur_user = (getpwuid($>))[0];
        if ($cur_user ne $user)
        {
            $su = 1;
        }
    }

    ($su) and $command .= "su - '$user' -c \" ";
    $command .= "'$LDAPSEARCH' $options -H '$ldapuri' -b '$searchbase'";
    ($filter ne '') and $command .= " '($filter)'";
    ($attribute ne '') and $command .= " '$attribute'";
    ($su) and $command .= "\"";

    my ($ret, $output) = RunCommand($command);
    if (! defined($ret) or $ret ne 0)
    {
        ERROR_OUT("ldapsearch failed");
        return;
    }

    # remove all the junks and get attribute
    if ($attribute ne '')
    {
        if ($output =~ m/^$attribute:/m)
        {
            $output =~ m/^$attribute:\s*(.*)$/m;
            $output = $1;
        }
        else
        {
            $output = undef;
        }
    }

    return (1, $output);
}

1;
