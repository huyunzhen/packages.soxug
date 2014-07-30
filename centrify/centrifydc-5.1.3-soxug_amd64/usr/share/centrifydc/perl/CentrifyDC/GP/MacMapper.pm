##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify generic mapper module for Mac OS X.
#
##############################################################################

use strict;

package CentrifyDC::GP::MacMapper;
our(@ISA, @EXPORT_OK);

BEGIN {
    require Exporter;
    @ISA = qw(Exporter);
    @EXPORT_OK = qw(CONVERT_MIN_TO_SEC CONVERT_REVERSE_BOOL CONVERT_AUTO_LOGOUT Map UnMap);
}

my $VERSION = '1.0';
require 5.000;

use Foundation;

use CentrifyDC::GP::Lock;
use CentrifyDC::GP::RegHelper;
use CentrifyDC::GP::Plist;
use CentrifyDC::GP::General qw(:debug RunCommand GetFullPath IsEqual IsEmpty);
use CentrifyDC::GP::Mac qw(:objc GetMacOSVersion);
use CentrifyDC::GP::MacDefaults qw(:defaults_options);

use constant {
    CONVERT_MIN_TO_SEC      => 1,
    CONVERT_REVERSE_BOOL    => 2,
    CONVERT_AUTO_LOGOUT     => 3,
};

my %CF_TYPE = (
    bool    => CF_BOOL,
    integer => CF_INTEGER,
    real    => CF_REAL,
    string  => CF_STRING,
    date    => CF_DATE,
    array   => CF_ARRAY,
);

my %DEFAULTS_TYPE = (
    bool    => DEFAULTS_BOOL,
    integer => DEFAULTS_INTEGER,
    real    => DEFAULTS_REAL,
    string  => DEFAULTS_STRING,
    date    => DEFAULTS_DATE,
    array   => DEFAULTS_ARRAY,
);

my $MACVER;
my $BYHOST_IDENTIFIER;




# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# convert legacy value to new value. these old values should not be used
# again in new gp.
#
# bool: <true/>/<false/> or YES/NO. translate to 1/0
#
#   $_[0]:  registry value
#   $_[1]:  type
#
#   return: string/number   - new value
#           undef           - registry value is undef. do nothing.
#
sub _ConvertLegacyValue($$)
{
    my ($data, $type) = @_;

    defined($data) or return undef;

    defined($type) or return $data;

    if ($type eq 'bool')
    {
        if ($data eq '<true/>' or $data eq 'YES')
        {
            $data = 1;
        }
        elsif ($data eq '<false/>' or $data eq 'NO')
        {
            $data = 0;
        }
    }

    return $data;
}

#
# convert data based on given pre-defined method.
#
# for example, we get screensaver timeout setting as minute in registry,
# but it's stored as seconds in plist. to convert minute to second, use
# MIN_TO_SEC as method.
#
#   $_[0]:  registry value
#   $_[1]:  method (string)
#
#   return: string/number   - new value
#           undef           - failed or old value is undef
#
sub _ConvertWithPredefinedMethod($$)
{
    my ($data, $method) = @_;

    defined($data) or return undef;

    if ($method == CONVERT_MIN_TO_SEC)
    {
        TRACE_OUT('convert registry data: min -> sec');
        $data = $data * 60;
    }
    elsif ($method == CONVERT_REVERSE_BOOL)
    {
        TRACE_OUT('convert registry data: reverse bool');
        $data = _ConvertLegacyValue($data, 'bool');
        $data = ($data == 1) ? 0 : 1;
    }
    elsif ($method == CONVERT_AUTO_LOGOUT)
    {
        TRACE_OUT('convert registry data: auto logout setting');
        $data = ($data < 5) ? 0 : $data;
        $data = $data * 60;
    }

    return $data;
}

#
# run a list of commands
#
#   $_[0]:  command list (array reference)
#
#   return: 1       - successful
#           2       - no command to run
#           undef   - failed
#
sub _RunCommands($)
{
    my $command_list = $_[0];

    IsEmpty($command_list) and return 2;

    my $ret = 1;

    foreach (@$command_list)
    {
        RunCommand($_) or $ret = undef;
    }

    return $ret;
}

#
# process one item
#
# run pre command before saving the settings, and run post command after saving
# settings.
#
#   $_[0]:  item (hash reference)
#   $_[1]:  user (undef for machine mapper)
#   $_[2]:  action (map/unmap)
#   $_[3]:  processor (Plist or MacDefaults instance)
#
#   return: 1       - successful
#           2       - no change
#           undef   - failed
#
sub _ProcessItem($$$$)
{
    my ($item, $user, $action, $processor) = @_;

    #
    # check if current Mac OS X version is supported. if not, simply ignore
    # this item.
    #
    if ($item->{version})
    {
        $MACVER or $MACVER = GetMacOSVersion()->{major};
        my $is_supported = 0;
        if (ref($item->{version}) eq 'ARRAY')
        {
            foreach (@{$item->{version}})
            {
                if ($_ eq $MACVER)
                {
                    $is_supported = 1;
                    last;
                }
            }
        }
        else
        {
            ($item->{version} eq $MACVER) and $is_supported = 1;
        }
        if (! $is_supported)
        {
            TRACE_OUT("setting not supported on this version of Mac OS X: key: [$item->{reg_key}] value: [$item->{reg_value}]");
            return 2;
        }
    }


    # create RegHelper instance
    my $reg_class = $item->{reg_class};
    my $reg_key   = $item->{reg_key};
    my $reg_value = $item->{reg_value};
    my $reg_type  = $item->{reg_type};
    my $is_array  = defined($reg_value) ? 0 : 1;

    my $reg;
    if ($is_array)
    {
        $reg = CentrifyDC::GP::RegHelper->new($action, $reg_class, $reg_key, undef, $reg_type, 1);
    }
    else
    {
        $reg = CentrifyDC::GP::RegHelper->new($action, $reg_class, $reg_key, $reg_value, $reg_type);
    }

    $reg or return undef;


    # load current/previous/local registry setting
    $reg->load();


    # convert legacy values to new value and update RegHelper
    foreach my $group (qw(current previous))
    {
        my $data = _ConvertLegacyValue($reg->get($group), $item->{type});
        $reg->set($group, $data);
    }

    # expand special escape characters because plist file doesn't recognize them.
    # we can also use this code, which will escape everything:
    #    chomp($data = eval "<<__EOF__\n$data\n__EOF__");
    foreach my $group (qw(current previous local))
    {
        my $data = $reg->get($group);
        $data =~ s/\\n/\n/g;
        $data =~ s/\\t/\t/g;
        $data =~ s/\\r/\r/g;
        $data =~ s/\\f/\f/g;
        $data =~ s/\\b/\b/g;
        $data =~ s/\\a/\a/g;
        $data =~ s/\\e/\e/g;
        $data =~ s/\\0([0-9]{2})/chr(oct($1))/eg;           # Octal \099
        $data =~ s/\\x([0-9A-Fa-f]{2})/chr(hex($1))/eg;     # Hex   \x1A
        $reg->set($group, $data);
    }


    #
    # convert current/previous registry data to the data that will be applied
    # to the system and update RegHelper.
    # for example, we get screensaver timeout setting as minute in registry,
    # but it's stored as seconds in plist.
    #
    if ($item->{convert_method})
    {
        # use pre-defined method to convert data
        foreach my $group (qw(current previous))
        {
            my $data = $reg->get($group);
            if (defined($data))
            {
                $data = _ConvertWithPredefinedMethod($data, $item->{convert_method});
                $reg->set($group, $data);
            }
        }
    }
    elsif ($item->{convert_expr})
    {
        #
        # use expression to convert data. to convert min to sec, convert_expr
        # should be:
        #   '$data = $data * 60'
        #
        foreach my $group (qw(current previous))
        {
            my $data = $reg->get($group);
            if (defined($data))
            {
                if (ref($item->{convert_expr}) eq 'ARRAY')
                {
                    foreach my $expr (@{$item->{convert_expr}})
                    {
                        eval($expr);
                        if ($@)
                        {
                            ERROR_OUT("Cannot apply data expression [$expr]: $@");
                            return undef;
                        }
                    }
                }
                else
                {
                    my $expr = $item->{convert_expr};
                    eval($expr);
                    if ($@)
                    {
                        ERROR_OUT("Cannot apply data expression [$expr]: $@");
                        return undef;
                    }
                }
                $reg->set($group, $data);
            }
        }
    }


    if ($processor->isa('CentrifyDC::GP::Plist'))
    {
        #
        # get system setting from plist and put into reghelper
        # if registry setting is array, then convert system setting into array
        #
        my $parent_keys = $item->{parent_key};
        my $all_keys;
        if (! defined($parent_keys))
        {
            $all_keys = [];
        }
        elsif (ref($parent_keys) eq 'ARRAY')
        {
            @$all_keys = @$parent_keys;
        }
        else
        {
            ERROR_OUT("Cannot process parent key: not an array");
            return undef;
        }
        push @$all_keys, $item->{key};
        if ($is_array)
        {
            my $data = $processor->get($all_keys);
            if (IsCF($data))
            {
                my $array;
                if (IsCF($data, CF_ARRAY))
                {
                    $array = CreateArrayFromNSMutableArray($data);
                }
                else
                {
                    $array = [ToString($data)];
                }
                $reg->set('system', $array);
            }
        }
        else
        {
            $reg->set('system', ToString($processor->get($all_keys)));
        }
    }
    else
    {
        my $value = $processor->read($item->{key});
        # Not every value we want to find is in the defaults system.
        # e.g. LoginwindowText is not existed by default
        # Only set the one that exists
        if (defined($value))
        {
            $reg->set('system', $value);
        }
    }

    #
    # RegHelper is ready. determine what to do and do it
    #
    my $ret = 2;
    my $group = $reg->getGroupToApply();
    if ($group)
    {                
        my $pre_commands  = [];
        my $post_commands = [];

        # prepare pre-command. only necessary if setting changed
        if ($item->{pre_cmd})
        {
            foreach my $command (values %{$item->{pre_cmd}})
            {
                my $cmd_str = $command->{command};
                if ($command->{run_as_user} and defined($user))
                {
                    $cmd_str = "su - $user -c '" . $cmd_str . "'";
                }
                if (defined($command->{trigger_value}))
                {
                    my $val = _ConvertLegacyValue($command->{trigger_value}, 'bool');
                    if (IsEqual($reg->get('system'), $val))
                    {
                        TRACE_OUT("add pre command: [$cmd_str]");
                        push @$pre_commands, $cmd_str;
                    }
                    else
                    {
                        TRACE_OUT("pre command [$cmd_str] not triggered");
                    }
                }
                else
                {
                    TRACE_OUT("add pre command: [$cmd_str]");
                    push @$pre_commands, $cmd_str;
                }
            }
        } # pre_cmd

        # prepare post-command. only necessary if setting changed
        if ($item->{post_cmd})
        {
            foreach my $command (values %{$item->{post_cmd}})
            {
                my $cmd_str = $command->{command};
                if ($command->{run_as_user} and defined($user))
                {
                    $cmd_str = "su - $user -c '" . $cmd_str . "'";
                }
                if (defined($command->{trigger_value}))
                {
                    my $val = _ConvertLegacyValue($command->{trigger_value}, 'bool');
                    if (IsEqual($reg->get($group), $val))
                    {
                        TRACE_OUT("add post command: [$cmd_str]");
                        push @$post_commands, $cmd_str;
                    }
                    else
                    {
                        TRACE_OUT("post command [$cmd_str] not triggered");
                    }
                }
                else
                {
                    TRACE_OUT("add post command: [$cmd_str]");
                    push @$post_commands, $cmd_str;
                }
            }
        } # post_cmd

        # run pre-command (if any)
        _RunCommands($pre_commands); 

        # update system setting
        my $data = $reg->get($group);
        my $type;
        if ($processor->isa('CentrifyDC::GP::Plist'))
        {
            $type = $item->{type} ? $CF_TYPE{$item->{type}} : CF_STRING;
        }
        else
        {
            $type = $item->{type} ? $DEFAULTS_TYPE{$item->{type}} : DEFAULTS_STRING;
        }
        if (defined($data))
        {
            DEBUG_OUT("Modify key: [$item->{key}]  data: [$data]  type:[$type]");
        }
        else
        {
            DEBUG_OUT("Remove key: [$item->{key}]");
        }

        if ($processor->isa('CentrifyDC::GP::Plist'))
        {
            $ret = $processor->set($item->{parent_key}, $item->{key}, $data, $type);
            if ($ret)
            {
                $ret = $processor->save();
            }
        }
        else
        {
            if (defined($data))
            {
                $ret = $processor->write($item->{key}, $type, $data);
            }
            else
            {
                $ret = $processor->delete($item->{key});
            }
        }
        
        if ($ret)
        {
            # run post-command (if any)
            _RunCommands($post_commands);
        }
        else
        {
            ERROR_OUT("Failed to run post commands");
        }
    }

    return $ret;
}

#
# process one plist file
#
#
#   $_[0]:  plist file (hash reference)
#   $_[1]:  user (undef for machine policy)
#   $_[2]:  action (map/unmap)
#
#   return: 1       - successful
#           2       - no change
#           undef   - failed
#
sub _ProcessFile($$$)
{
    my ($file, $user, $action) = @_;

    # skip user plist file for machine mapper
    if ($file->{class} ne 'machine')
    {
        if (! defined($user))
        {
            TRACE_OUT("skip user plist file: [$file->{path}]");
            return 2;
        }
    }

    my $processor;
    my $byhost = ($file->{class} eq 'byhost') ? 1 : 0;
    if (defined($file->{domain}))
    {
        # create MacDefaults instance
        $processor = CentrifyDC::GP::MacDefaults->new($file->{domain}, $user, $byhost);
    }
    else
    {
        # create Plist instance
        my $plist_file = $file->{path};
        $processor = CentrifyDC::GP::Plist->new($plist_file, $user, $byhost);
        if (! $processor or ! $processor->load())
        {
            ERROR_OUT("Cannot load [$plist_file]. Skip.");
            return undef;
        }
    }

    # process items one by one.
    foreach my $item (values %{$file->{value_map}})
    {
        if (defined($user))
        {
            if ($item->{class} eq 'machine')
            {
                TRACE_OUT("skip machine setting: key: [$item->{reg_key}]");
                next;
            }
        }
        else
        {
            if ($item->{class} eq 'user')
            {
                TRACE_OUT("skip user setting: key: [$item->{reg_key}]");
                next;
            }
        }
        my $result = _ProcessItem($item, $user, $action, $processor);
        if (! defined($result))
        {
            ERROR_OUT("Cannot update setting: [$item].");
            return undef;
        }
    }

    return 1;
}

sub _DoMap($$$)
{
    my ($fileset, $user, $action) = @_;

    my $ret = 1;

    CentrifyDC::GP::Registry::Load($user);

    foreach my $file (values %$fileset)
    {
        my $lock;
        if ($file->{critical})
        {
            # create exclusive lock for critical plist file.
            TRACE_OUT("Create exclusive lock to protect critical file [$file->{path}]");
            $lock = CentrifyDC::GP::Lock->new('mac.mapper.' . $file->{path});
            if (! defined($lock))
            {
                ERROR_OUT("Cannot obtain lock");
                $ret = undef;
                next;
            }
            TRACE_OUT(" lockfile: [" . $lock->file() . "]");
        }

        my $ret = _ProcessFile($file, $user, $action);
        if (! $ret)
        {
            ERROR_OUT("Failed to process $file->{class} [$file->{path}]");
            $ret = undef;
            next;
        }
    }

    return $ret;

}

sub Map($$)
{
    my ($fileset, $user) = @_;

    return _DoMap($fileset, $user, 'map');
}

sub UnMap($$)
{
    my ($fileset, $user) = @_;

    return _DoMap($fileset, $user, 'unmap');
}

1;
