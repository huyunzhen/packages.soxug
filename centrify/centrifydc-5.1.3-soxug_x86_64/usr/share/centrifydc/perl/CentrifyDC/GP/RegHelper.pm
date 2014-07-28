##############################################################################
#
# Copyright (C) 2008-2014 Centrify Corporation. All rights reserved.
#
# Centrify mapper script registry helper module for Mac OS X.
#
# This module puts current/previous/local registry settings and system
# setting into one class instance, and decide which setting should be applied.
# It can also save system setting into local registry.
#
#
# The standard procedure to use this module is:
#
#   1. create a new instance
#   2. get current/previous/local reg setting using load;
#   3. get setting from system (it's you responsibility) and then set 'system'
#      setting using set;
#   4. decide which reg group setting should be applied using getGroupToApply
#      and do the actual stuff. getGroupToApply will also save system
#      setting to local registry. (cannot do it in destructor)
#
#
# To create a new RegHelper:
#
#   my $reg = CentrifyDC::GP::RegHelper->new(
#               'map',
#               'machine',
#               'software/policies/centrify/centrifydc/settings/mac/security',
#               'disableAutoLogin',
#               'REG_SZ',
#               '1');
#
#       Parameter 4 and 5 can be undef.
#       If parameter 4 is undef, it will retrieve all values under the
#       specified reg key and store as hash.
#       If parameter 5 is undef, it will assume reg data type is REG_SZ.
#       Parameter 6 can be omitted. if specified, RegHelper will treat hash
#       as array.
#
#
# To load registry setting:
#
#   $reg->load();
#
# To get registry setting of a specific group:
#
#   $reg->get('previous');
#
#       Return value can be a hash reference or array reference.
#       If hash_as_array is set, then it will return array reference instead
#       of hash reference.
#
# To set registry setting of a specific group:
#
#   $reg->set('previous', '1');
#
#       Parameter 2 can be a hash reference or array reference.
#       If hash_as_array is set, use array reference
#
# To decide which registry group will be applied:
#
#   $reg->getGroupToApply();
#
#       Before calling this function, make sure system setting has been set
#       using $reg->set. If system setting is not set, this function may make
#       wrong decision.
#
# The data structure of a standard Reghelper is as below:
#
#   $reg => {
#       hash_as_array => 1,
#       action  => 'map',
#       class => 'machine',
#       key   => 'software/policies/centrify/centrifyDC/settings/mac/network/proxies',
#       value => 'FTPEnable',
#       type  => 'REG_DWORD',
#       current   => 1,
#       previous  => undef,
#       local     => 0,
#       system    => 1,
#   };
#
# If value is not specified, then all settings under specified key will be
# retrieved:
#
#   $reg => {
#       hash_as_array => 1,
#       action  => 'map',
#       class => 'machine',
#       key   => 'software/policies/centrify/centrifyDC/settings/mac/network/proxies',
#       value => undef,
#       type  => undef,
#       current   => {
#           FTPEnable  => 1,
#           FTPProxy   => 'proxy.company.com',
#           HTTPEnable => 0,
#       },
#       previous  => {
#           FTPEnable  => 0,
#       },
#       local     => {
#           HTTPEnable => 1,
#       },
#       system    => {
#           FTPPassive => 1,
#       },
#   };
#
#
# NOTICE:
#
# If there's no setting for a specific group, then the value will be undef.
# Empty string is different from undef. Remember this when updating system
# group setting: if there's no system setting, use undef.
#
##############################################################################

use strict;

package CentrifyDC::GP::RegHelper;
my $VERSION = '1.0';
require 5.000;

use CentrifyDC::GP::Registry;
use CentrifyDC::GP::General qw(:debug IsEqual IsEmpty);

sub new($$$$$$;$);
sub load($;$);
sub get($$);
sub set($$$);
sub getGroupToApply($);

# private
sub _trace($);
sub _loadGroup($$);
sub _updateLocalReg($);
sub _SortNumerically;
sub _HashToArray($);
sub _ArrayToHash($);



#
# create instance
#
#   $_[0]:  self
#   $_[1]:  action (map/unmap)
#   $_[2]:  reg class (machine/user)
#   $_[3]:  reg key (cannot be empty)
#   $_[4]:  reg value (if undef, will get all values under the specified key)
#   $_[5]:  reg type (if undef, set to REG_SZ)
#   $_[6]:  treat hash as array (optional. when reg value is a hash - for
#           example a list of domain name - set to 1 will ignore hash key
#           and treat it as an array
#
#   return: self    - successful
#           undef   - failed
#
sub new($$$$$$;$)
{
    my ($invocant, $action, $regclass, $regkey, $regvalue, $regtype, $hash_as_array) = @_;
    my $class = ref($invocant) || $invocant;

    if (! defined($action))
    {
        ERROR_OUT("Cannot create RegHelper instance: action not specified");
        return undef;
    }
    if ($action ne 'map' and $action ne 'unmap')
    {
        ERROR_OUT("Cannot create RegHelper instance: unknown action: [$action]");
        return undef;
    }
    if (! defined($regclass))
    {
        ERROR_OUT("Cannot create RegHelper instance: registry class not specified");
        return undef;
    }
    if ($regclass ne 'machine' and $regclass ne 'user')
    {
        ERROR_OUT("Cannot create RegHelper instance: unknown registry class: [$regclass]");
        return undef;
    }
    if (! defined($regkey))
    {
        ERROR_OUT("Cannot create RegHelper instance: registry key not specified");
        return undef;
    }
    $regtype or $regtype = 'REG_SZ';

    my $self = {
        hash_as_array => $hash_as_array,
        action  => $action,
        class => $regclass,
        key   => $regkey,
        value => $regvalue,
        type  => $regtype,
        current  => undef,
        previous => undef,
        local    => undef,
        system   => undef,
    };

    bless($self, $class);

    return $self;
}

#
# query registry for current/previous/local value
#
#   $_[0]:  self
#   $_[1]:  group (optional, if omitted, load all groups)
#
sub load($;$)
{
    my ($self, $group) = @_;

    if ($group and ($group eq 'current' or $group eq 'previous' or $group eq 'local'))
    {
        _loadGroup($self, $group);
    }
    else
    {
        foreach my $grp (qw(current previous local))
        {
            _loadGroup($self, $grp);
        }
    }
}

#
# get setting of specified group and return
#
# if hash_as_array is set, will return array reference instead of hash
# reference
#
#   $_[0]:  self
#   $_[1]:  group (current/previous/local/system)
#
#   return: string or hash/array reference  - setting
#           undef                           - failed or no value
#
sub get($$)
{
    my ($self, $group) = @_;

    if (! $group)
    {
        ERROR_OUT("Cannot get registry setting: group not specified");
        return undef;
    }
    elsif($group ne 'current' && $group ne 'previous' && $group ne 'local' && $group ne 'system')
    {
        ERROR_OUT("Cannot get registry setting: unknown group: [$group]");
        return undef;
    }

    if ($self->{hash_as_array})
    {
        return _HashToArray($self->{$group});
    }
    else
    {
        return $self->{$group};
    }
}

#
# set setting of specified group. if data is an array, convert to hash
#
#   $_[0]:  self
#   $_[1]:  group (current/previous/local/system)
#   $_[2]:  setting
#
#   return: 1       - successful
#           undef   - failed
#
sub set($$$)
{
    my ($self, $group, $data) = @_;

    if (! $group)
    {
        ERROR_OUT("Cannot set registry setting: group not specified");
        return undef;
    }
    elsif($group ne 'current' && $group ne 'previous' && $group ne 'local' && $group ne 'system')
    {
        ERROR_OUT("Cannot set registry setting: unknown group: [$group]");
        return undef;
    }

    if (ref($data) eq 'ARRAY')
    {
        $self->{$group} = _ArrayToHash($data);
    }
    else
    {
        $self->{$group} = $data;
    }

    return 1;
}

#
# determine which reg group should be applied based on action
#
#   $_[0]:  self
#
#   return: string  - reg group to apply
#                   ''          - do nothing
#                   current   - enforce current registry value
#                   local     - restore local registry value
#           undef   - failed (do nothing)
#
sub getGroupToApply($)
{
    my $self = $_[0];

    my $action = $self->{action};

    my $ret = '';

    TRACE_OUT("get group to apply: action: [$action]");
    _trace($self);

    my $reg_current;
    my $reg_previous;
    my $reg_local;
    my $reg_system;

    if ($self->{hash_as_array})
    {
        $reg_current  = _HashToArray($self->{current});
        $reg_previous = _HashToArray($self->{previous});
        $reg_local    = _HashToArray($self->{local});
        $reg_system   = _HashToArray($self->{system});
    }
    else
    {
        $reg_current  = $self->{current};
        $reg_previous = $self->{previous};
        $reg_local    = $self->{local};
        $reg_system   = $self->{system};
    }

    if ($action eq 'map')
    {
        # if current registry setting exists, apply current registry setting
        if (! IsEmpty($reg_current))
        {
            # if current registry setting is the same as system setting, then
            # no need to apply again
            IsEqual($reg_system, $reg_current) or $ret = 'current';
        }
        else
        {
            # if current registry setting doesn't exist but previous registry
            # setting exists, then this gp is changed from enabled to not
            # configured or disabled. In this case, if system setting is
            # different from previous registry setting, do nothing; if system
            # setting is the same as previous registry setting (which means
            # system setting is coming from registry), restore local registry
            # setting
            if (! IsEmpty($reg_previous))
            {
                if (IsEqual($reg_system, $reg_previous))
                {
                    # need to check if it's necessary to restore local registry
                    # setting. If system setting is the same as local registry
                    # setting, then no need to restore local registry setting
                    IsEqual($reg_system, $reg_local) or $ret = 'local';
                }
            }
        }
    }
    elsif ($action eq 'unmap')
    {
        # if system setting is different from local registry setting,
        # restore local registry setting
        IsEqual($reg_system, $reg_local) or $ret = 'local';
    }

    if ($ret)
    {
        TRACE_OUT("group: $ret");
    }
    else
    {
        TRACE_OUT("group: N/A");
    }

    # save local registry
    # cannot do it in destructor
    _updateLocalReg($self);

    return $ret;
}



# >>> PRIVATE >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# write registry setting into log when log level is TRACE
#
#   $_[0]: self
#
sub _trace($)
{
    IsTraceOn() or return;

    my $self = $_[0];

    my $trace_str = ' |';
    foreach my $key (qw(action class key value type))
    {
        my $value = $self->{$key};

        $trace_str .= " $key: ";
        if (defined($value))
        {
            $trace_str .= "[$value]";
        }
        else
        {
            $trace_str .= "undefined";
        }
    }

    foreach my $key (qw(current previous local system))
    {
        my $value = $self->{$key};

        $trace_str .= sprintf("\n | %-8s: ", $key);
        if (defined($value))
        {
            if (ref($value) eq 'HASH')
            {
                if ($self->{hash_as_array})
                {
                    my $array = _HashToArray($value);
                    
                    foreach my $element (@$array)
                    {
                        if (defined($element))
                        {
                            $trace_str .= "\n |          [$element]";
                        }
                        else
                        {
                            $trace_str .= "\n |          undefined";
                        }
                    }
                } # hash_as_array
                else
                {
                    # get the max length of key. need it to format output
                    my $maxlen = 0;
                    foreach my $subkey (keys %$value)
                    {
                        my $len = length($subkey);
                        if ($len > $maxlen)
                        {
                            $maxlen = $len;
                        }
                    }
                    ($maxlen <= 30) or $maxlen = 30;

                    while (my ($subkey, $subvalue) = each(%$value))
                    {
                        $trace_str .= sprintf("\n |           %-${maxlen}s: ", $subkey);
                        if (defined($subvalue))
                        {
                            $trace_str .= "[$subvalue]";
                        }
                        else
                        {
                            $trace_str .= "undefined";
                        }
                    } # while
                }
            } # HASH
            else
            {
                $trace_str .= "[$value]";
            }
        } # defined $value
        else
        {
            $trace_str .= "undefined";
        }
    } # foreach

    TRACE_OUT($trace_str);
}

#
# query registry for a specific group
#
# if no registry setting, use undef as value. please notice that an empty
# string is also a value, so it's different from undef
#
#   $_[0]:  self
#   $_[1]:  group
#
sub _loadGroup($$)
{
    my ($self, $group) = @_;

    if ($self->{value})
    {
        $self->{$group} = (CentrifyDC::GP::Registry::Query($self->{class}, $self->{key}, $group, $self->{value}))[1];
    }
    else
    {
        my %hash = ();
        my $is_empty = 1;
        foreach my $value (CentrifyDC::GP::Registry::Values($self->{class}, $self->{key}, $group))
        {
            if ($value)
            {
                $hash{$value} = (CentrifyDC::GP::Registry::Query($self->{class}, $self->{key}, $group, $value))[1];
                $is_empty = 0;
            }
        }
        if (! $is_empty)
        {
            $self->{$group} = \%hash;
        }
    }
}

#
# save system setting to local policy file if it's different from both
# previous/local registry setting
#
#   $_[0]:  self
#
#   return: 0       - no need to update
#           1       - updated
#
sub _updateLocalReg($)
{
    my $self = $_[0];

    # no need to update local registry on unmap
    ($self->{action} eq 'map') or return 0;
    
    my $ret = 0;

    my $reg_previous;
    my $reg_local;
    my $reg_system;

    if ($self->{hash_as_array})
    {
        $reg_previous = _HashToArray($self->{previous});
        $reg_local    = _HashToArray($self->{local});
        $reg_system   = _HashToArray($self->{system});
    }
    else
    {
        $reg_previous = $self->{previous};
        $reg_local    = $self->{local};
        $reg_system   = $self->{system};
    }

    # no need to update local reg if system setting is equal to previous reg
    # setting or local reg setting
    if (IsEqual($reg_system, $reg_previous) ||
        IsEqual($reg_system, $reg_local))
    {
        return 0;
    }

    if (! IsEmpty($self->{system}))
    {
        TRACE_OUT("Save system setting to local registry:  key: [$self->{key}]");
        # system setting exists. delete current local registry and save
        # system setting to local registry
        if (ref($self->{system}) eq 'HASH')
        {
            while (my ($value, $data) = each(%{$self->{local}}))
            {
                TRACE_OUT(" | delete value: [$value]");
                CentrifyDC::GP::Registry::Delete($self->{class}, $self->{key}, 'local', $value);
            }
            while (my ($value, $data) = each(%{$self->{system}}))
            {
                TRACE_OUT(" | store value: [$value] data: [$data]");
                CentrifyDC::GP::Registry::Store($self->{class}, $self->{key}, 'local', $value, $self->{type}, $data);
            }
        }
        else
        {
            TRACE_OUT(" | store value: [$self->{value}] data: [$self->{system}]");
            CentrifyDC::GP::Registry::Store($self->{class}, $self->{key}, 'local', $self->{value}, $self->{type}, $self->{system});
        }
        $ret = 1;
    }
    else
    {
        TRACE_OUT("Delete local registry value:  key: [$self->{key}]");
        # system setting doesn't exist. delete local registry
        if (ref($self->{local}) eq 'HASH')
        {
            while (my ($value, $data) = each(%{$self->{local}}))
            {
                TRACE_OUT(" | delete value: [$value]");
                CentrifyDC::GP::Registry::Delete($self->{class}, $self->{key}, 'local', $value);
            }
            $ret = 1;
        }
        else
        {
            TRACE_OUT(" | delete value: [$self->{value}]");
            CentrifyDC::GP::Registry::Delete($self->{class}, $self->{key}, 'local', $self->{value});
        }
        $ret = 1;
    }

    if ($ret)
    {
        TRACE_OUT("Update local policy file: key: [$self->{key}]");
        CentrifyDC::GP::Registry::SaveGroupForKey($self->{class}, $self->{key}, 'local');
    }

    return $ret;
}

#
# callback function for sort
#
# we need to sort array like this:
#   VALUE1, VALUE2, ... VALUE10, VALUE11, ...
# the build-in sort will get incorrect result:
#   VALUE1, VALUE10, VALUE11, VALUE2, ...
# this function will sort them in correct order.
#
sub _SortNumerically
{
    my $a_str;
    my $b_str;
    my $a_num;
    my $b_num;

    #
    # suppose $a = VALUE1, $b = VALUE2
    # $a_str = VALUE
    # $b_str = VALUE
    # $a_num = 1
    # $b_num = 2
    #
    $a =~ m/(.*?)(\d*)$/;
    $a_str = $1;
    $a_num = $2;
    $b =~ m/(.*?)(\d*)$/;
    $b_str = $1;
    $b_num = $2;

    if (IsEqual($a_str, $b_str))
    {
        # string part is equal, compare number part
        if (defined($a_num))
        {
            if (defined($b_num))
            {
                # both a and b have number part. compare
                if ($a_num < $b_num)
                {
                    return -1;
                }
                elsif ($a_num > $b_num)
                {
                    return 1;
                }
                else
                {
                    return 0;
                }
            }
            else
            {
                # b doesn't have number part. a is bigger
                return 1;
            }
        }
        else
        {
            # a doesn't have number part
            if (defined($b_num))
            {
                return -1;
            }
            else
            {
                return 0;
            }
        }
    }
    else
    {
        # string part is not equal, use normal compare
        if ($a lt $b)
        {
            return -1;
        }
        elsif ($a gt $b)
        {
            return 1;
        }
        else
        {
            return 0;
        }
    }
}

#
# extract values in hash, put into an array and return. array values are
# sorted by hash key
#
#   $_[0]:  hash reference
#
#   return: array reference - successful
#           undef           - failed or source hash undefined
#
sub _HashToArray($)
{
    my $hash = $_[0];

    defined($hash) or return undef;

    (ref($hash) eq 'HASH') or return undef;

    my @array = ();

    foreach my $key (sort _SortNumerically keys %$hash)
    {
        my $value = $hash->{$key};
        push @array, $value;
    }

    return \@array;
}

#
# convert an array to hash. hash keys are 'VALUE1', 'VALUE2', ...
#
#   $_[0]:  array reference
#
#   return: hash reference  - successful
#           undef           - failed or source array undefined
#
sub _ArrayToHash($)
{
    my $array = $_[0];

    defined($array) or return undef;

    (ref($array) eq 'ARRAY') or return undef;

    my %hash = ();

    my $i = 1;
    foreach my $value (@$array)
    {
        my $key = 'VALUE' . $i;
        $hash{$key} = $value;
        $i++;
    }

    return \%hash;
}

# <<< PRIVATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

1;
