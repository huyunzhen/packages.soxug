#
# Group Policy Mapper Program Module
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Group Policy mapper programs convert the values from Group Policy
# to the appropriate configuration files on a Unix/Linux machine.
#
use strict;

package CentrifyDC::GP::Mapper;
use CentrifyDC::Logger;

my $VERSION = "1.0";
require 5.000;

use Exporter;
my @ISA = qw(Exporter);
my @EXPORT_OK = qw(Map UnMap);

use CentrifyDC::GP::Registry;
use Fcntl qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN O_RDONLY O_CREAT O_EXCL);
use Symbol;
use File::Basename;

my %reg_group_keys = (
    "current" => "reg_data",
    "previous" => "prev_data",
    "local" => "local_data",
);

my %POST_ACTION_FILES = (
    'DO_RESTART_ADCLIENT_AND_EXPIRE_CACHE'  => '/var/centrifydc/reg/do_restart_expire',
    'DO_RESTART_ADCLIENT'    => '/var/centrifydc/reg/do_restart_adclient',
    'DO_ADRELOAD'            => '/var/centrifydc/reg/do_adreload',
    'DO_ADFLUSH'             => '/var/centrifydc/reg/do_adflush',
    'DO_DSRELOAD'            => '/var/centrifydc/reg/do_dsreload',
    'DO_DSFLUSH'             => '/var/centrifydc/reg/do_dsflush',
    'DO_SARESTART'           => '/var/centrifydc/reg/do_sarestart',
    'DO_RESTART_LOGINWINDOW' => '/var/centrifydc/reg/do_restart_loginwindow',
    'DO_DARELOAD'            => '/var/centrifydc/reg/do_dareload',
);

my $system = `uname -s`;
my $version = `uname -r`;
chomp $system;
chomp $version;

#
# "current" from latest GP update should own the type 
# (reg_actual_type) - see GetNamedRegistryValues() and others.
#
my @reg_group_keys_order = ("local", "previous", "current");

my $LOCAL_GROUP = "local";

my $DEFAULT_MAXTRIES = 3;

my @tmpfiles;

#
# hashes for storing original/new values. Compare them at the end of mapping
# to know if file is changed. Initiate before mapping and undef after
# comparison.
#
my $original_values;
my $new_values;

#
# set up syslog and debug
#
my $logger = CentrifyDC::Logger->new('com.centrify.gp.Mapper');
my $DEBUG = $logger->level();

#
# remove temp files on SIGTERM
#
$SIG{'TERM'} = 'TERM_handler';

sub TERM_handler
{
    #
    # Clean up any leftover temporary files.
    #
    unlink(@tmpfiles);
}

#
# log for debugging
#
sub ffdebug($)
{
    my ($msg) = @_;
    return unless ($DEBUG eq 'DEBUG' or $DEBUG eq 'TRACE');
    $logger->log('debug', $msg);
}

sub fftrace($)
{
    my ($msg) = @_;
    return unless ($DEBUG eq 'TRACE');
    $logger->log('debug', $msg);
}

#
# log fatal error message and exit 1.
#
#   @_:  message
#
#   exit:   1
#
sub FATAL_OUT
{
    my $first = shift;

    if (defined($first))
    {
        $first = ">>> " . $first;
        unshift(@_, $first);
        $logger->log('info', @_);
    }
    else
    {
        $logger->log('info', ">>> A problem occured. Exit.");
    }

    exit(1);
}

#
# rename a file and restore security context of the destination file (for selinux)
#   $_[0]:  source file
#   $_[0]:  destination file
#   ret:    1       - successful
#           undef   - failed
#
sub rename_file($$)
{
    my ($old_file, $new_file) = @_;

    if (! defined($old_file) or $old_file eq '')
    {
        $logger->log('info', ">>> cannot rename file: source file not specified.");
        return undef;
    }
    if (! defined($new_file) or $new_file eq '')
    {
        $logger->log('info', ">>> cannot rename file: destination file not specified.");
        return undef;
    }

    rename($old_file, $new_file) || return undef;

    # Restore context type if has selinux
    if ( -e "/sbin/restorecon" )
    {
        ffdebug("Restoring security context of $new_file");
        `/sbin/restorecon $new_file`;
        
        my $err = $?;
        if ( $err != 0 )
        {
            $logger->log('info', "Restore security context of $new_file failed (rc = $err).");
        }
    }

    return 1;
}

#
# traverse symlink and return the actual file name.
#   $_[0]:  filename
#   ret:    string  - actual file name
#           undef   - failed
#
sub TraverseSymLink
{
    my $filename = shift;

    (defined($filename) and $filename ne '') or return $filename;

    my @known_links = ();
    push(@known_links, $filename);
    while (defined(my $target = readlink($filename)))
    {
        # if target is a relative path but symlink is absolute path,
        # then we need to add dirname in front of target.
        if ($target =~ m|^[^/]|)
        {
            if ($filename =~ m|^/|)
            {
                my $dir = dirname $filename;
                $target = "$dir/$target";
            }
        }
        # check if target file is in the known link list. this is
        # for preventing self-reference and endless-loop of reference.
        foreach (@known_links)
        {
            if ($target eq $_)
            {
                ffdebug "self reference found. stop following the symlink.";
                return $filename;
            }
        }
        $filename = $target;
        push(@known_links, $filename);
    }

    return $filename;
}

#
# File::Temp is not available on all the platforms we need to run on,
# so create our own mkstemp.
#
sub mkstemp($)
{
    my ($template) = @_;
    my $filename;
    my $fh = &Symbol::gensym;
    my $suffix = $$ . sprintf(".%04x", int(rand(65536)));

    ($filename = $template) =~ s/X*$/$suffix/;
    open($fh, "+> $filename") || FATAL_OUT "$filename: $!";
    return ($fh, $filename);
}

#
# Clean up leftover files in previous run. If map process is terminated
# abnormally, a temp file may be left in system.
# temp file name format is file.pid.xxxx, for example
# centrifydc.conf.10000.89ab
#   file: filename
#   pid:  pid
#   xxxx: 4-digit random hex number
#
# $_[0]:    filename
#
sub DoCleanUp($)
{
    my $file = $_[0];

    defined($file) or return;

    fftrace("check leftover file for $file");
    my $file_dir = dirname($file);
    my $file_base = basename($file);
    (-e $file_dir) or return;

    opendir(DIR, $file_dir);
    my @files = readdir(DIR);
    closedir(DIR);

    foreach (@files)
    {
        if ($_ =~ m/^$file_base\.\d+\.[a-fA-F0-9]{4}$/)
        {
            my $file_tmp = "$file_dir/$_";
            ffdebug("Remove leftover temp file $file_tmp.");
            unlink($file_tmp);
        }
    }
}

#
# Convert backslashes and escape special characters. 
#
# Multiple continuous backslash characters before the special characters will 
# be converted to a single backslash character.
#
# Special characters such as newline character '\n' will be converted to two 
# characters '\' and 'n'. The reason is that special characters such as '\n' 
# will corrupt centrifydc.conf by adding newline in parameters. 
#
#   $_[0]:  string
#   ret:    modified string with special characters escaped
#
sub EscapeSpecialChars($)
{
    my $data = $_[0];

    my $special_chars = {
        'n' => '\n',
    };

    foreach my $char (keys %$special_chars)
    {
        # Convert multiple continuous backslashes before the special characters 
        # to a single backslash (\)
        while ($data =~ m/\\\\$char/)
        {
            $data =~ s/\\\\$char/\\$char/g;
        }

        # Convert special characters (e.g. '\n' -> "\\n")
        # Because newline character '\n' will corrupt centrifydc.conf 
        # (Bug 13122)
        #
        # NOTE:
        # Keep this conversion for potential backward compatability issues.
        # Newline characters should not be saved in registry data in the first 
        # place.
        #
        $data =~ s/$special_chars->{$char}/\\$char/gos;
    }

    return $data;
}

#
# Convert backslashes and escape special characters. Previously all registry 
# data are converted in Registry.pm when the data is loaded. The purpose is 
# to convert multiple backslash characters to one backslash character.
#
# But for AD values, e.g. NTLM, full DN, and canonical name, we don't want to 
# do any conversion. We want backslash characters in centrifydc.conf to be 
# exactly the same as in GP GUI.
#
# Examples for normal values:
#
#   GP GUI:             \\\\\\\n
#   centrifydc.conf:    \n (two characters)
#
# Examples for AD values:
#   
#   GP GUI:           domain\\name
#   centrifydc.conf:  domain\\name
#
# Therefore we moved the conversion from Registry.pm to here so we can indicate 
# AD and other values via custom keyword ADVALUE in mapper script. 
#
# If the registry data is a AD value, the data will be kept unchanged when 
# mapped and written to e.g. centrifydc.conf. For other values, multiple 
# continuous backslashes will be converted into one backslash and special 
# characters are escaped before mapped.
#
#   $_[0]:  value map
#   $_[1]:  file value
#   $_[2]:  registry data
#   ret:    modified registry data
#
sub ConvertRegData($$$)
{
    my ($value_map, $file_value, $reg_data) = @_;
    my $convert_data = 1;

    # Do not convert registry data if marked as AD value
    # Because we need to keep special characters used in AD name formats 
    # (Bug 32652)
    if (defined($value_map->{$file_value}{'advalue'}))
    {
        if ($value_map->{$file_value}{'advalue'})
        {
            $convert_data = 0;
        }
    }
    
    if ($convert_data)
    {
        $reg_data = EscapeSpecialChars($reg_data);
    }

    return $reg_data;
}

#
# Get a named value from all three registry groups (current,
# previous, and local).
#
sub GetNamedRegistryValues($$$$$)
{
    my ($file, $file_value, $reg_class, $reg_key, $reg_value) = @_;
    my $value_map = $file->{value_map};

    foreach my $reg_group (@reg_group_keys_order)
    {
        my $reg_data_key = $reg_group_keys{$reg_group};
	my ($reg_type, $reg_data) = CentrifyDC::GP::Registry::Query($reg_class,
	    $reg_key, $reg_group, $reg_value);

	if (defined($reg_data))
        {
            $reg_data = ConvertRegData($value_map, $file_value, $reg_data);
            
            foreach my $type (@{$value_map->{$file_value}{reg_type}})
            {
                if ($reg_type eq $type)
                {
                    $value_map->{$file_value}{$reg_data_key} = $reg_data;
                    $value_map->{$file_value}{reg_actual_type} = $reg_type;
                    last;
                }
            }
	}
    }
}

#
# Get all the values under a registry key, in all three registry
# groups (current, previous, and local), and store them as new
# values in the value map, with the registry value name appended
# to the base file value name passed in.
#
sub GetAllRegistryValues($$$$)
{
    my ($file, $file_value, $reg_class, $reg_key) = @_;
    my $value_map = $file->{value_map};

    foreach my $reg_group (@reg_group_keys_order)
    {
        my $reg_data_key = $reg_group_keys{$reg_group};
        my @reg_values = CentrifyDC::GP::Registry::Values($reg_class,
            $reg_key, $reg_group);

        foreach my $reg_value (@reg_values)
        {
            my $new_file_value;

            $new_file_value = $file_value;
            $new_file_value .= $file->{hierarchy_separator};
            $new_file_value .= $reg_value;

	    my ($reg_type, $reg_data) =
		CentrifyDC::GP::Registry::Query($reg_class, $reg_key,
		    $reg_group, $reg_value);

	    if (defined($reg_data))
	    {
                $reg_data = ConvertRegData($value_map, $new_file_value, $reg_data);
		
                $value_map->{$new_file_value}{value_type} = "named";
		$value_map->{$new_file_value}{reg_class} = $reg_class;
		$value_map->{$new_file_value}{reg_value} = $reg_value;
		$value_map->{$new_file_value}{reg_type} = [ $reg_type ];
		$value_map->{$new_file_value}{reg_actual_type} = $reg_type;
                $value_map->{$new_file_value}{$reg_data_key} = $reg_data;
		$value_map->{$new_file_value}{active} =
		    $value_map->{$file_value}{active};
	    }

            #
            # If this is a value from the current registry settings,
            # add the new file value to the list of registry values,
            # so we can add them all to the file if necessary.
            #
            if ($reg_group eq "current")
            {
                push(@{$value_map->{$file_value}{reg_values}}, $new_file_value);
            }
        }
    }
}

#
# Get all the values under a registry key, in all three registry
# groups (current, previous, and local), and store them as a list
# under a single file_value.
#
sub GetListRegistryValues($$$$$)
{
    my ($file, $file_value, $reg_class, $reg_key, $list_separator) = @_;
    my $value_map = $file->{value_map};

    foreach my $reg_group (@reg_group_keys_order)
    {
        my $reg_data_key = $reg_group_keys{$reg_group};
        my @reg_values = CentrifyDC::GP::Registry::Values($reg_class,
            $reg_key, $reg_group);
	my @reg_data_list = ();

        foreach my $reg_value (@reg_values)
        {
	    my ($reg_type, $reg_data) =
		CentrifyDC::GP::Registry::Query($reg_class, $reg_key,
		    $reg_group, $reg_value);

	    if (defined($reg_data))
	    {
                $reg_data = ConvertRegData($value_map, $file_value, $reg_data);
                
                foreach my $type (@{$value_map->{$file_value}{reg_type}})
                {
                    if ($reg_type eq $type)
                    {
                        push (@reg_data_list, $reg_data);
                        $value_map->{$file_value}{reg_actual_type} = $reg_type;
                        last;
                    }
                }
	    }
        }

	$value_map->{$file_value}{$reg_data_key} = join($list_separator,
	    @reg_data_list);
    }
}

#
# Load all the registry keys that are needed to map this file.
# If $unmap is 1, we're unmapping (reverting to locally
# configured values), so we skip the current and previous 
# registry groups.
#
sub LoadRegistryData($$)
{
    my ($file, $user) = @_;
    my $value_map = $file->{value_map};

    #
    # Load the registry files.
    #
    CentrifyDC::GP::Registry::Load($user);

    foreach my $file_value (keys(%{$value_map}))
    {
        my $reg_key = $value_map->{$file_value}{reg_key};
        my $reg_class = $value_map->{$file_value}{reg_class};
        my $value_type = $value_map->{$file_value}{value_type};
        my $reg_value;

        #
        # This value may get its data from a different registry
        # value; this is used for settings that are controlled by
        # another setting (e.g. one UI field to control the
        # meaning of one or more other fields, and ultimately
        # which values get stored into the system configuration
        # files.
        #
        if ($value_map->{$file_value}{data_value} ne "")
        {
            $reg_value = $value_map->{$file_value}{data_value};
        }
        else
        {
            $reg_value = $value_map->{$file_value}{reg_value};
        }

        #
        # Copy the appropriate registry values into $file->{value_map}.
        #
        if ($value_type eq "all")
        {
            GetAllRegistryValues($file, $file_value, $reg_class, $reg_key);
        }
        elsif ($value_type eq "list" && $reg_value eq "")
        {
            my $list_separator;

            if (defined ($value_map->{$file_value}{list_separator}))
            {
                $list_separator = $value_map->{$file_value}{list_separator};
            }
            else
            {
                $list_separator = $file->{list_separator};
            }
            GetListRegistryValues($file, $file_value, $reg_class, $reg_key,
                $list_separator);
        }
        else
        {
            GetNamedRegistryValues($file, $file_value, $reg_class, $reg_key,
                $reg_value);
        }
    }
}



#
# Map a value from the registry to the file.  Depending on what's
# currently set, we may take the current registry value, the
# local value (which was probably just taken from the file as
# we read it), or the default value.
#
sub MapValue($$$$$$)
{
    my ($file, $file_value, $file_data, $user, $unmap, $tmp) = @_;
    my $value_map = $file->{value_map};
    my $written = 0;

    # If value is not supported on specific system or version, it will
    #   not be mapped.
    my $unsupported_sys = $value_map->{$file_value}{unsupported_sys};
    if (defined($unsupported_sys))
    {
        foreach my $sys (@{$unsupported_sys})
        {
            if (defined($sys))
            {
                if ($sys eq "$system-$version" || $sys eq "$system")
                {
                    ffdebug("Skipping $value_map->{$file_value}{reg_value}\n");
                    return 1;
                }
            }
        }
    }

    my $reg_data;
    my $prev_data;

    if ($unmap)
    {
        $prev_data = $value_map->{$file_value}{reg_data};
    }
    else
    {
        $reg_data = $value_map->{$file_value}{reg_data};
        $prev_data = $value_map->{$file_value}{prev_data};
    }

    my $reg_key = $value_map->{$file_value}{reg_key};
    my $reg_type = (defined $value_map->{$file_value}{reg_actual_type}) ?
      $value_map->{$file_value}{reg_actual_type} :
        $value_map->{$file_value}{reg_type}[0];
    my $reg_class = $value_map->{$file_value}{reg_class};
    my $local_data = $value_map->{$file_value}{local_data};
    my $value_type = $value_map->{$file_value}{value_type};
    my $reg_value = $value_map->{$file_value}{reg_value};

    #
    # data is a list, but in registry it's a single value instead
    # of a list, for example:
    #    pam.allow.groups: group1, group2,...,groupn
    # need to add double quote for each item.
    #
    my $file_data_unquoted;
    my $file_data_quoted;
    my $named_list_separator;
    if ($value_map->{$file_value}{named_list})
    {
        if (defined ($value_map->{$file_value}{named_list_separator}))
        {
            $named_list_separator = $value_map->{$file_value}{named_list_separator};
        }
        else
        {
            $named_list_separator = $file->{named_list_separator};
        }

        if (defined($file_data) and $file_data ne '')
        {
            $file_data_unquoted = $file_data;
            $file_data_unquoted =~ s/"//g;

            $file_data_quoted = $file_data;
            $file_data_quoted =~ s/"//g;
            $file_data_quoted = "\"$file_data_quoted\"";
            $file_data_quoted =~ s/$named_list_separator/"$named_list_separator"/g;
        }
    }

    if (defined($file_data))
    {
        my $new_local_data;

        #
        # Split REG_MULTI_SZ strings into an array of values.
        # Please notice that we need to use multi_sz_join instead of
        # multi_sz_split.
        #
        # Suppose the registry data is
        #   line1,line2,line3
        # and multi_sz_split is ',', multi_sz_join is '\n', then this setting
        # will be split into an array (line1, line2, line3) first, and
        # will end up in file as
        #   line1
        #   line2
        #   line3
        # To translate this file data back to array, we need to use
        # multi_sz_join '\n' to split it.
        #
        if ($reg_type eq 'REG_MULTI_SZ' && defined($file->{multi_sz_join}))
        {
            #
            # we want to preserve the trailing empty fields, so set
            # split LIMIT to -1.
            #
            $file_data = [split(/$file->{multi_sz_join}/, $file_data, -1)];
        }

        #
        # Convert the data from the file to our internal format
        # for possible storage in the Local Policy registry,
        # and comparison with data from the Group Policy
        # registry.
        #
        foreach my $expr (@{$file->{file_data_expr}{$reg_type}},
            @{$value_map->{$file_value}{file_data_expr}})
        {
            #
            # The file_data_expr expressions expect these variable
            # names.
            #
            my $value = $file_value;
            my $data;

            if (ref($file_data) eq "ARRAY")
            {
                foreach $data (@{$file_data})
                {
                    eval($expr);

                    if ($@)
                    {
                        print(STDERR "$@\n");
                        last;
                    }
                }
            }
            else
            {
                $data = $file_data;
                eval($expr);
                $file_data = $data;

                if ($@)
                {
                    print(STDERR "$@\n");
                }
            }
        }

        #
        # If specific on/off data values are used in the file, convert
        # them to the registry data values.
        #
        if (defined($value_map->{$file_value}{file_valueon}))
        {
            my $valueon;
            my $valueoff;

            if (defined($value_map->{$file_value}{valueon}))
            {
                $valueon = $value_map->{$file_value}{valueon};
                $valueoff = $value_map->{$file_value}{valueoff};
            }
            else
            {
                $valueon = 1;
                $valueoff = 0;
            }

            if ($file_data eq $value_map->{$file_value}{file_valueon})
            {
                $file_data = $valueon;
            }
            else
            {
                $file_data = $valueoff;
            }
        }

        if ($value_map->{$file_value}{value_type} eq "list")
        {
            #
            # The data is a list, split it up and compare each
            # element.
            #
            my $list_expr;
            my $list_separator;

            if (defined ($value_map->{$file_value}{list_expr}))
            {
                $list_expr = $value_map->{$file_value}{list_expr};
            }
            else
            {
                $list_expr = $file->{list_expr};
            }

            if (defined ($value_map->{$file_value}{list_separator}))
            {
                $list_separator = $value_map->{$file_value}{list_separator};
            }
            else
            {
                $list_separator = $file->{list_separator};
            }

            my @file_list = split (/$list_expr/o, $file_data);
            my @reg_list = split (/$list_expr/o, $reg_data);
            my @prev_list = split (/$list_expr/o, $prev_data);
            my @local_list = split (/$list_expr/o, $local_data);

            my @tmp = grep {
                my $data = $_;
                grep (/$data/, @file_list)
            } @local_list;

            @local_list = (@tmp, grep {
                my $data = $_;
                grep (/$data/, (@prev_list, @tmp)) == 0
            } @file_list);
            $new_local_data = join ($list_separator, @local_list);

            if ($value_map->{$file_value}{list_merge})
            {
                @reg_list = (@local_list, grep {
                        my $data = $_;
                        grep (/$data/, @local_list) == 0
                    } @reg_list);
                $reg_data = join ($list_separator, (@reg_list));

                if (@prev_list)
                {
                    @prev_list = (@local_list, grep {
                            my $data = $_;
                            grep (/$data/, @local_list) == 0
                        } @prev_list);
                    $prev_data = join ($list_separator, (@prev_list));
                }
            }

            if ($new_local_data ne $local_data)
            {
                #
                # The data from the file does not match the previous
                # registry data (either because this is the first time
                # we've mapped this file value, or because the data in
                # the file has been changed).  Save the file data to the
                # Local Policy registry.
                #
                if ($reg_value eq "")
                {
                    my $value;

                    foreach $value (CentrifyDC::GP::Registry::Values($reg_class,
                            $reg_key, $LOCAL_GROUP))
                    {
                        CentrifyDC::GP::Registry::Delete($reg_class, $reg_key,
                            $LOCAL_GROUP, $value);
                    }

                    foreach $value (@local_list)
                    {
                        CentrifyDC::GP::Registry::Store($reg_class, $reg_key,
                            $LOCAL_GROUP, $value, $reg_type, $value);
                        fftrace("Stored in local policy file: registry key=$reg_key; value=$value");
                    }
                }
                else
                {
                    CentrifyDC::GP::Registry::Store($reg_class, $reg_key,
                        $LOCAL_GROUP, $reg_value, $reg_type, $new_local_data); 
                    fftrace("Stored in local policy file: registry key=$reg_key; reg_value=$reg_value; local_data=$new_local_data");
                }

                $value_map->{$file_value}{local_data} = $new_local_data;
                $local_data = $new_local_data;
            }
        } # data is a list
        elsif (ref($file_data) eq "ARRAY")
        {
            #
            # data is REG_MULTI_SZ
            #
            if ((ref($prev_data) ne 'ARRAY' || join(' ', sort(@{$file_data})) ne
                        join(' ', sort(@{$prev_data}))) &&
                (ref($local_data) ne 'ARRAY' || join(' ', sort(@{$file_data})) ne
                        join(' ', sort(@{$local_data}))))
            {
                $new_local_data = $file_data;
            }
        }
        else
        {
            if ($value_map->{$file_value}{named_list})
            {
                #
                # data is a list, but in registry it's a single value instead
                #
                if ($file_data_unquoted ne $prev_data && $file_data_unquoted ne $local_data)
                {
                    $new_local_data = $file_data_unquoted;
                }
            } # named_list
            elsif ($file_data ne $prev_data && $file_data ne $local_data)
            {
                #
                # normal data (named)
                #
                $new_local_data = $file_data;
            }
        }

        if (defined($new_local_data))
        {
            #
            # The data from the file does not match the previous
            # registry data (either because this is the first time
            # we've mapped this file value, or because the data in
            # the file has been changed).  Save the file data to the
            # Local Policy registry.
            #

            CentrifyDC::GP::Registry::Store($reg_class, $reg_key,
                $LOCAL_GROUP, $reg_value, $reg_type, $new_local_data);
            fftrace("Stored in local policy file: registry key=$reg_key; reg_value=$reg_value; local_data=$new_local_data");
            $value_map->{$file_value}{local_data} = $new_local_data;
            $local_data = $new_local_data;
        }
    } # if (defined($file_data))

    #
    # If we've already written a value for this setting,
    # just return.  This happens after the value is saved
    # as local data, which means that the last setting in
    # the file (if it appears multiple times) is what gets
    # saved.  That allows for a commented-out version of
    # a setting to precede a real setting; the registry
    # value will be output just after the commented-out
    # version, but the real setting later in the file
    # will get saved.
    #
    if ($value_map->{$file_value}{done})
    {
        return 1;
    }

    #
    # If the value has test code to determine if it's active
    # (should be added to the file), check it now.  If the
    # value isn't active, mark it done and return.  That will
    # cause any setting that happens to be there to be
    # removed from the file (after being saved as local
    # data above, if necessary).
    #
    if ($value_map->{$file_value}{active} ne "")
    {
        if (! eval($value_map->{$file_value}{active}))
        {
            $new_values->{$file_value} = undef;
            $value_map->{$file_value}{done} = 1;
            return 1;
        }
    }

    #
    # Fall back to the local setting if there's nothing in the registry.
    # If the current file setting matches the previous registry setting,
    # it came from the registry and should be removed from the file
    # entirely if there's no saved local setting.  Setting $written to 1
    # will cause the current line (if any) to be removed from the file,
    # replaced by $local_data if it's set.
    #
    if (!defined($reg_data))
    {
        if (defined($prev_data))
        {
            my $changed = 1;

            if (ref($prev_data) eq "ARRAY")
            {
                if (scalar(@{$file_data}) == scalar(@{$prev_data}))
                {
                    $changed = 0;

                    for (my $i = 0; $i < scalar(@{$prev_data}); $i++)
                    {
                        if ($file_data->[$i] ne $prev_data->[$i])
                        {
                            $changed = 1;
                            last;
                        }
                    }
                }
            }
            else
            {
                if ($value_map->{$file_value}{named_list})
                {
                    #
                    # for named list, need to compare the actual setting, so
                    # quotes won't be included
                    #
                    if ($file_data_unquoted eq $prev_data)
                    {
                        $changed = 0;
                    }
                }
                elsif ($file_data eq $prev_data)
                {
                    $changed = 0;
                }
            }

            if (! $changed)
            {
                if (defined($local_data))
                {
                    $reg_data = $local_data;
                }
                else
                {
                    $new_values->{$file_value} = undef;
                    $written = 1;
                }
            }
        }
    }

    #
    # for named list, add quote to registry data
    #
    if ($value_map->{$file_value}{named_list})
    {
        if (defined($reg_data) && $reg_data ne '')
        {
            $reg_data =~ s/"//g;
            $reg_data = "\"$reg_data\"";
            $reg_data =~ s/$named_list_separator/"$named_list_separator"/g;
        }
    }

    #
    # If the value has changed, write it out to the file.
    #
    if (defined($reg_data) && $reg_data ne $file_data)
    {
        #
        # The file_data_expr expressions expect these variable
        # names.
        #
        my $value = $file_value;
        my $data = $reg_data;

        #
        # Convert the data from the file to our internal format
        # for possible storage in the Local Policy registry,
        # and comparison with data from the Group Policy
        # registry.
        #
        foreach my $expr (@{$file->{reg_data_expr}{$reg_type}},
            @{$value_map->{$file_value}{reg_data_expr}})
        {
            if (ref($reg_data) eq "ARRAY")
            {
                foreach $data (@{$reg_data})
                {
                    eval($expr);

                    if ($@)
                    {
                        print(STDERR "$@\n");
                        last;
                    }
                }
            }
            else
            {
                $data = $reg_data;
                eval($expr);
                $reg_data = $data;

                if ($@)
                {
                    print(STDERR "$@\n");
                }
            }
        }

        #
        # Join REG_MULTI_SZ arrays into a single string.
        #
        if ($reg_type eq 'REG_MULTI_SZ' && defined($file->{multi_sz_join}))
        {
            $data = join($file->{multi_sz_join}, @{$reg_data});
        }

        #
        # If specific on/off data values are used in the file, convert
        # the registry value to the correct file value.
        #
        if (defined($value_map->{$file_value}{file_valueon}))
        {
            my $valueon;
            my $valueoff;

            if (defined($value_map->{$file_value}{valueon}))
            {
                $valueon = $value_map->{$file_value}{valueon};
                $valueoff = $value_map->{$file_value}{valueoff};
            }
            else
            {
                $valueon = 1;
                $valueoff = 0;
            }

            if ($data eq $valueon)
            {
                $data = $value_map->{$file_value}{file_valueon};
            }
            else
            {
                $data = $value_map->{$file_value}{file_valueoff};
            }
        }

        $new_values->{$value} = $data;

        # Now write the value to the file.
        (my $write_data = $file->{'write_data'}) =~ s/(['"])/\\$1/g;
        $write_data = '$data' unless defined($write_data);
        eval "print(\$tmp \"$write_data\")";
        $written = 1;
    }

    #
    # If we wrote new data to the file, or we're keeping an existing
    # value from the file, mark this value done.  The other case is
    # where we've found a commented-out version of a value with no
    # setting in the registry; if we mark it done in that case, later
    # settings in the file will be deleted, which is not what we want.
    #
    if ($written || defined($file_data))
    {
        $value_map->{$file_value}{done} = 1;
    }

    return $written;
}



#
# Perform the mapping for a single file.
#
sub DoMap($$$)
{
    my ($file, $user, $unmap) = @_;
    my $value_map = $file->{value_map};

    LoadRegistryData($file, $user);

    if (defined($file->{pre_command}))
    {
        eval($file->{pre_command});

        if ($@)
        {
            print(STDERR "$@\n");
        }
    }

    #
    # Process some "macro" settings in the file description.
    # These are purely for the convenience of the person
    # writing the description.
    #

    if (defined($file->{multi_sz_separator}))
    {
        $file->{multi_sz_split} = $file->{multi_sz_separator}
            unless defined($file->{multi_sz_split});
        $file->{multi_sz_join} = eval("\"$file->{multi_sz_separator}\"")
            unless defined($file->{multi_sz_join});
    }

    #
    # Default values
    #
    $file->{multi_sz_split} = '\n'
        unless defined($file->{multi_sz_split});
    $file->{multi_sz_join} = "\n"
        unless defined($file->{multi_sz_join});

    #
    # If the file needs it, change the input record delimiter
    # from the default of of \n.  If the magic value
    # "<ENTIRE_FILE>" is specified, set the delimiter to
    # "undefined" which tells perl to read the entire file at
    # once.
    #
    local $/;

    if (defined($file->{newline}))
    {
        if ($file->{newline} eq "<ENTIRE_FILE>")
        {
            $/ = undef;
        }
        else
        {
            $/ = $file->{newline};
        }
    }
    else
    {
        $/ = "\n";
    }

    #
    # Open the input file, and a temporary to hold the new
    # contents as we build them.
    #
    my $path;

    if (defined($file->{sys_path}))
    {
        if (ref($file->{sys_path}{"$system-$version"}) eq "ARRAY")
        {
            foreach my $tmp_path (@{$file->{sys_path}{"$system-$version"}})
            {
                if (-e $tmp_path)
                {
                    $path = $tmp_path;
                    last;
                }
            }
        }
        else
        {
            my $tmp_path = $file->{sys_path}{"$system-$version"};
            if (-e $tmp_path)
            {
                $path = $tmp_path;
            }
        }

        # Not found in $system-$version. Try $system.
        if (!defined($path))
        {
            if (ref($file->{sys_path}{"$system"}) eq "ARRAY")
            {
                foreach my $tmp_path (@{$file->{sys_path}{"$system"}})
                {
                    if (-e $tmp_path)
                    {
                        $path = $tmp_path;
                        last;
                    }
                }
            }
            else
            {
                my $tmp_path = $file->{sys_path}{"$system"};
    
                if (-e $tmp_path)
                {
                    $path = $tmp_path;
                }
            }
        }
    } # <- defined $file->(sys_path)

    if (!defined($path))
    {
        if (ref($file->{path}) eq "ARRAY")
        {
            foreach my $tmp_path (@{$file->{path}})
            {
                if (-e $tmp_path)
                {
                    $path = $tmp_path;
                    last;
                }
            }

            if (!defined($path))
            {
                $path = @{$file->{path}}[0];
            }
        }
        else
        {
            $path = $file->{path};
        }
    }

    if (! -e $path && !defined($file->{create}))
    {
        ffdebug("$path not exist. skip.");
        return;
    }

    #
    # Follow any symbolic links.
    #
    $path = TraverseSymLink($path);

    DoCleanUp($path);

    my $lock;
    my $locktmp;
    my $lockfile;
    my $tries = 0;
    my $maxtries = $file->{max_lock_tries};
    $maxtries = $DEFAULT_MAXTRIES unless defined($maxtries);

    if (defined($file->{lock}))
    {
        #
        # Get the lockfile name.  It might be based on $path, so
        # use eval to expand variables.
        #
        eval("\$lockfile = \"$file->{lock}\"");
    }

    if (defined($lockfile) && $lockfile ne "flock")
    {
        DoCleanUp($lockfile);
        # Create a temporary lock file to move into place.
        ($lock, $locktmp) = mkstemp($lockfile . ".XXXXXXXX");
        push(@tmpfiles, $locktmp);
        flock($lock, LOCK_EX);
        print($lock "$$\n");
    }

    while (1)
    {
        # First create the external lock file, if any.
        if (defined($lockfile) && $lockfile ne "flock")
        {
            #
            # If lockfile exists, check if it's expired (not accessed in 60 seconds).
            # If it's expired, try to remove it. if can't remove, fail.
            #
            if (-e $lockfile)
            {
                my $now = time();
                my $atime = (stat($lockfile))[8];
                if ($now - $atime > 60)
                {
                    ffdebug("Lockfile [$lockfile] exists but is expired. Remove:  atime: [$atime]  now: [$now]");
                    if (! unlink($lockfile))
                    {
                        ffdebug("Cannot remove expired lockfile [$lockfile]. Abort.");
                        return;
                    }
                }
                else
                {
                    ffdebug("Lockfile [$lockfile] exists and is not expired:  atime: [$atime]  now: [$now]");
                    next;
                }
            }

            if (! link ($locktmp, $lockfile))
            {
                next;
            }

            unlink($locktmp);
            push(@tmpfiles, $lockfile);
        }

        # Now try to open or create the file.
        if (-e $path)
        {
            if (!open(INFILE, "< $path"))
            {
                if (-e $path || !defined($file->{create}))
                {
                    FATAL_OUT "$path: $!";
                }

                # The file has been removed since we checked; try again.
                next;
            }
        }
        else
        {
            if (!defined($file->{create}))
            {
                return;
            }

            if (!sysopen(INFILE, $path, O_RDONLY|O_CREAT|O_EXCL,
                    oct($file->{create})))
            {
                if (! -e $path)
                {
                    FATAL_OUT "$path: $!";
                }

                # The file has been created since we checked; try again.
                next;
            }
        }

        # Now lock the file itself, if needed.
    if ($lockfile eq "flock")
    {
        if (! flock(INFILE, LOCK_EX|LOCK_NB))
        {
            close(INFILE);
            next;
        }
    }

        # The file is open and locked.
        last;
    }
    continue
    {
        $tries++;

        if ($tries >= $maxtries)
        {
            FATAL_OUT ("Cannot lock $path");
        }

        sleep 1;
    }

    my ($tmp, $tmpfile) = mkstemp($path . ".XXXXXXXX");
    push(@tmpfiles, $tmpfile);

    #
    # Set the ownership and permissions on the new file to be the
    # same as the old.
    #
    my (undef, undef, $mode, undef, $uid, $gid) = stat(INFILE);
    chmod($mode, $tmpfile);
    chown($uid, $gid, $tmpfile);

    my $copy_input;
    #
    # Indicates whether current line is multi line or not.
    # If a line ends with \, then it's a multi line and need to be joined
    # with next line.
    #
    my $multi_line = 0;
    # Indicates whether multi line is comment or not.
    my $multi_line_comment = 0;
    # Joined multi line.
    my $joined_line = "";
    my $multi_line_comment_marker = "";
    my $prevpos = 0;

    $original_values = {};
    $new_values = {};

    while (<INFILE>)
    {
        my $file_value;
        my $file_data;

        my $line = $_;
        my $comment = 0;
        my $current_comment_marker = "";
        $copy_input = 1;
        #
        # Check to see if this is a comment line.  If it is,
        # remove the comment marker and process the rest of
        # the line as a setting.  That will match a commented-out
        # version of a setting, and cause the real value to be
        # output just after it.
        #
        foreach my $comment_marker (@{$file->{comment_markers}})
        {
            if ($line =~ /^$comment_marker/)
            {
                $comment = 1;
                $line =~ s/^$comment_marker\s*//;
                $current_comment_marker = $comment_marker;
                last;
            }
        }

        #
        # Check if line ends with odd number of \.  If so, join this line
        # with next line.
        #
        # For example:
        #
        #   value: line1,\
        #          line2,\
        #          line3
        #
        # becomes:
        #
        #   value: line1,line2,line3
        #
        # If a line ends with odd number of \ is followed by a comment line,
        # then it's an invalid entry, and mapper will remove the last \.
        #
        # For example:
        #
        #   value: line1,\
        #          line2,\
        #   #      line3
        #
        # becomes:
        #
        #   value: line1,line2
        #   #      line3
        #
        if ($multi_line)
        {
            if ($comment == $multi_line_comment)
            {
                #
                # current and previous lines are both comment or setting
                #
                chomp($line);
                $line =~ s/^\s*//;
                #
                # if line ends with odd number of \, then need to join next line
                #
                $line =~ m/[^\\]*(\\*)$/;
                if (length($1) & 1)
                {
                    $line =~ s/\\$//;
                    $copy_input = 0;
                    $joined_line = $joined_line . $line;
                    next;
                }
                else
                {
                    # reach the end of a multi-line setting
                    $line = $joined_line . $line;
                }
            }
            else
            {
                #
                # Crossed comment boundary. Process multi-line setting and
                # rewind file position to previous line.
                #
                $line = $joined_line;
                seek(INFILE, $prevpos, 0);
            }
            if ($multi_line_comment)
            {
                $comment = 1;
                $_ = "$multi_line_comment_marker " . $line;
            }
            else
            {
                $comment = 0;
                $_ = $line;
            }
            chomp($_);
            $_ .= "\n";
            $multi_line = 0;
            $multi_line_comment = 0;
            $multi_line_comment_marker = '';
        }
        else
        {
            foreach my $expr (@{$file->{match_expr}})
            {
                ( $file_value, $file_data ) =
                    eval("if (\$line =~ $expr) { ( \$1, \$2 ); }");
                last if ($file_value ne "" || $file_data ne "");
            }

            if ($file_value eq "" && $file_data eq "")
            {
                next;
            }

            $line =~ m/[^\\]*(\\*)$/;
            if (length($1) & 1)
            {
                $line =~ s/\\$//;
                $copy_input = 0;
                $multi_line = 1;
                chomp($line);
                $line =~ s/^\s*//;
                $joined_line = $line;
                if ($comment)
                {
                    $multi_line_comment = 1;
                    $multi_line_comment_marker = $current_comment_marker;
                }
                next;
            }
        }

        #
        # Parse the input line into a value name and associated
        # data.  If none of the match expressions matches,
        # skip the line (copying it to the temp file verbatim).
        #
        foreach my $expr (@{$file->{match_expr}})
        {
            ( $file_value, $file_data ) =
                eval("if (\$line =~ $expr) { ( \$1, \$2 ); }");
            last if ($file_value ne "" || $file_data ne "");
        }

        if ($file_value eq "" && $file_data eq "")
        {
            next;
        }


        if ($comment)
        {
            #
            # We found a commented-out version of a setting.
            # Output it, and undefine $file_data so we'll
            # always output the registry data if it's set.
            # This places the value from the registry right
            # below the commented-out version of the setting.
            #
            print($tmp $_);
            $copy_input = 0;
            undef($file_data);
        }
        else
        {
            #
            # Found actual setting. Save into hash so that
            # they can be compare to the new setting later.
            #
            $original_values->{$file_value} = $file_data;
        }

        #
        # If values within the file are hierarchical, first check
        # this value to see if it falls under any of the values
        # we're modifying.  If it does, and the value is
        # specified to include all sub-values, write all the
        # values from the registry here.  This groups
        # registry-configured values with locally-configured
        # values under the same key, and allows us to remove the
        # locally-configured values if necessary (i.e. the parent
        # value is not marked "additive").
        #
        if (! $comment && defined($file->{parent_expr}))
        {
            my $parent = $file_value;

            while ($parent =~ s/$file->{parent_expr}/$1/)
            {
                if (defined($value_map->{$parent}) &&
                    $value_map->{$parent}{value_type} eq "all")
                {
                    my $reg_class = $value_map->{$parent}{reg_class};
                    my $reg_key = $value_map->{$parent}{reg_key};
                    my $reg_type = $value_map->{$parent}{reg_type};
                    my $reg_value = $2;

                    #
                    # If file value is different from previous registry value
                    # and local registry value, save it
                    # as a local policy setting, to be restored if the
                    # value is deleted from Group Policy, or when we
                    # leave the domain.
                    #
                    if ($file_data ne $value_map->{$file_value}{prev_data} &&
                        $file_data ne $value_map->{$file_value}{local_data})
                    {
                        CentrifyDC::GP::Registry::Store($reg_class, $reg_key,
                            $LOCAL_GROUP, $reg_value, $reg_type, $file_data);
                    }

                    if (! $unmap)
                    {
                        foreach my $value (@{$value_map->{$parent}{reg_values}})
                        {
                            MapValue($file, $value, undef, $user, $unmap, $tmp);
                        }
                    }

                    #
                    # If the value is not marked ADDITIVE,
                    # delete any local values under this key.
                    # Otherwise the values from Group Policy
                    # are added to the local values.
                    #
                    if (! $value_map->{$parent}{additive} || ($unmap &&
                                defined($value_map->{$file_value}{reg_data})))
                    {
                        $copy_input = 0;
                    }

                    last;
                }
            }
        }

        #
        # If we have a mapping for this value, replace it with
        # the data from the registry.
        #
        if (defined($value_map->{$file_value}))
        {
            #
            # It's possible that some settings have duplicated entries.
            # For example,
            #     one.setting: true
            #     one.setting: false
            # If its value is found in registry, then we'll modify the first
            # entry and remove all duplicated entries.
            # If its value is not found in registry, then all entries are
            # kept intact.
            #
            if (MapValue($file, $file_value, $file_data, $user, $unmap, $tmp))
            {
                $copy_input = 0;
            }
        }
    } continue {
        # Save position
        $prevpos = tell(INFILE);

        #
        # Copy the line if we haven't replaced it.
        #
        if ($copy_input)
        {
            fftrace("Writting to temporary config file: $_");
            print($tmp $_);
        }
    }

    #
    # Add any values that weren't found earlier to the end of the file.
    #
    foreach my $file_value (sort(keys(%{$value_map})))
    {
        my $reg_data;

        if ($unmap)
        {
            $reg_data = $value_map->{$file_value}{local_data};
        }
        else
        {
            $reg_data = $value_map->{$file_value}{reg_data};
        }

        if (($value_map->{$file_value}{value_type} eq "named" ||
                $value_map->{$file_value}{value_type} eq "list") &&
                defined($reg_data) && ! $value_map->{$file_value}{done})
        {
            MapValue($file, $file_value, undef, $user, $unmap, $tmp);
        }
    }

    close($tmp);

    #
    # Update the local policy files.  Don't bother if we're reverting to
    # the local policy, since nothing will change.
    #
    if (! $unmap)
    {
        CentrifyDC::GP::Registry::SaveGroup($LOCAL_GROUP);
    }

    #
    # Compare new settings with original settings. If any of the
    # settings get changed, then file has changed. Also get post
    # actions/commands of these settings.
    #
    my $post_actions = {};
    my $post_commands = {};
    my $file_changed = 0;

    foreach my $key (keys %$new_values)
    {
        my $value_changed = 0;

            #
            # Compare original setting and new setting. Can't use $a eq $b
            # because it cannot handle undef correctly.
            #
            my $oldval = $original_values->{$key};
            my $newval = $new_values->{$key};
            if (defined($newval))
            {
                if (! defined($oldval))
                {
                    $value_changed = 1;
                }
                else
                {
                    if ($newval ne $oldval)
                    {
                        $value_changed = 1;
                    }
                }
            }
            else
            {
                if (defined($oldval))
                {
                    $value_changed = 1;
                }
            }

        if ($value_changed)
        {
            ffdebug("property updated: $key: [$oldval] -> [$newval]");
            $file_changed = 1;

            my $acts = $value_map->{$key}{post_action};
            if (defined($acts))
            {
                if (ref($acts) eq 'ARRAY')
                {
                    foreach my $act (@$acts)
                    {
                        fftrace("add post action for $key: $act");
                        $post_actions->{$act} = 1;
                    }
                }
                else
                {
                    fftrace("add post action for $key: $acts");
                    $post_actions->{$acts} = 1;
                }
            }
            my $commands = $value_map->{$key}{post_command};
            if (defined($commands))
            {
                if (ref($commands) eq 'ARRAY')
                {
                    foreach my $command (@$commands)
                    {
                        fftrace("add post command for $key: $command");
                        $post_commands->{$command} = 1;
                    }
                }
                else
                {
                    fftrace("add post command for $key: $commands");
                    $post_commands->{$commands} = 1;
                }
            }
        }
    }

    undef $original_values;
    undef $new_values;

    #
    # If the file has changed, move the new one into place and run
    # the post command.  Otherwise, just remove the temporary file
    # and leave things alone.
    #
    if ($file_changed)
    {
        ffdebug("$path changed");
        unlink($path . ".bak");
        link($path, $path . ".bak") || FATAL_OUT $!;
        rename_file($tmpfile, $path) || FATAL_OUT $!;

        # revert the file to back out the changes if verify failed
        if (defined($file->{verify_command}))
        {
            my $ret = eval($file->{verify_command});

            if ($ret)
            {
                rename($path . ".bak", $path);
                ffdebug("Verify failed, revert the change applied to $path");
                print(STDERR "$@\n");
            }
        }

        # get file's post commands
        my $commands = $file->{post_command};
        if (defined($commands))
        {
            if (ref($commands) eq 'ARRAY')
            {
                foreach my $command (@$commands)
                {
                    fftrace("add post command: $command");
                    $post_commands->{$command} = 1;
                }
            }
            else
            {
                fftrace("add post command: $commands");
                $post_commands->{$commands} = 1;
            }
        }

        # run post commands
        foreach my $cmd (keys %$post_commands)
        {
            eval($cmd);

            if ($@)
            {
                ffdebug("Post command failed: $cmd");
                print(STDERR "$@\n");
            }
        }

        # get file's post actions
        my $acts = $file->{post_action};
        if (defined($acts))
        {
            if (ref($acts) eq 'ARRAY')
            {
                foreach my $act (@$acts)
                {
                    fftrace("add post action: $act");
                    $post_actions->{$act} = 1;
                }
            }
            else
            {
                fftrace("add post action: $acts");
                $post_actions->{$acts} = 1;
            }
        }

        # create post action files (so that zzreload.pl and watchdog can do
        # the actual action)
        foreach my $act (keys %$post_actions)
        {
            my $action_file = $POST_ACTION_FILES{$act};

            if (defined($action_file))
            {
                open (FH, ">$action_file");
                close (FH);
            }

        }
    }
    else
    {
        unlink($tmpfile);
    }

    #
    # Defer the close until here in case we locked the file.
    #
    if (defined($lockfile) && $lockfile ne "flock")
    {
        unlink($lockfile);
    }

    if (defined($lock))
    {
        close($lock);
    }

    close(INFILE);
    return 0;
}

#
# Map a set of files from their registry values to the appropriate
# file configuration.
#
sub Map($$)
{
    my ($file, $user) = @_;

    DoMap($file, $user, 0);
}

#
# Undo the mapping performed by Map(), reverting to the saved
# "Local Policy" (the values that were read from the files most
# recently).
#
sub UnMap($$)
{
    my ($file, $user) = @_;

    DoMap($file, $user, 1);
}

sub END()
{
    #
    # Clean up any leftover temporary files.
    #
    foreach my $file (@tmpfiles)
    {
        unlink($file);
    }
}

1;
