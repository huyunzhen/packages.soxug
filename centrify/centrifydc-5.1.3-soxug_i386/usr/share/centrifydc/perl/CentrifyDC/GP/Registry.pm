#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Registry access module.
#
# This module accesses the on-disk copy of the Group Policy registry
# settings as they are copied over by the adclient daemon.
#
use strict;

package CentrifyDC::GP::Registry;
my $VERSION = "1.0";
require 5.000;

use Exporter;
my @ISA = qw(Exporter);
my @EXPORT_OK = qw(Load, Save, Query, Store, Values);

use File::Path;
use File::Find;
use CentrifyDC::Config;
use CentrifyDC::Logger;
use CentrifyDC::GP::GPIsolation qw(GP_REG_FILE_CURRENT GP_REG_FILE_PREVIOUS GP_REG_FILE_LOCAL);
use Symbol;

use constant DEFAULT_REG_PATH                => '/var/centrifydc/reg';

use constant REG_NONE                        =>  0;
use constant REG_SZ                          =>  1;
use constant REG_EXPAND_SZ                   =>  2;
use constant REG_BINARY                      =>  3;
use constant REG_DWORD                       =>  4;
use constant REG_DWORD_LITTLE_ENDIAN         =>  4;
use constant REG_DWORD_BIG_ENDIAN            =>  5;
use constant REG_LINK                        =>  6;
use constant REG_MULTI_SZ                    =>  7;
use constant REG_RESOURCE_LIST               =>  8;
use constant REG_FULL_RESOURCE_DESCRIPTOR    =>  9;
use constant REG_RESOURCE_REQUIREMENTS_LIST  => 10;
use constant REG_QWORD                       => 11;
use constant REG_QWORD_LITTLE_ENDIAN         => 11;

#
# There appear to be some types that Microsoft uses that aren't
# fully documented.  The one we've tripped over thus far is using
# value 17 rather than 07 for REG_MULTI_SZ.
#
use constant REG_TYPE_NAMES => qw(
        REG_NONE
        REG_SZ
        REG_EXPAND_SZ
        REG_BINARY
        REG_DWORD
        REG_DWORD_BIG_ENDIAN
        REG_LINK
        REG_MULTI_SZ
        REG_RESOURCE_LIST
        REG_FULL_RESOURCE_DESCRIPTOR
        REG_RESOURCE_REQUIREMENTS_LIST
        REG_QWORD
        REG_TYPE_12
        REG_TYPE_13
        REG_TYPE_14
        REG_TYPE_15
        REG_TYPE_16
        REG_MULTI_SZ
        REG_TYPE_18
        REG_TYPE_19
        REG_TYPE_20
);

my $ROOT;
my $CLASS;
my %registry;

my $ROOT_SUBKEY;    # root directory of specified registry key for GetSubKeys
my @SUBKEYS;        # array of sub registry keys for GetSubKeys
my $GROUP_SUBKEY;   # group (current/previous/local) for GetSubKeys

#
# set up syslog and debug
#
my $logger = CentrifyDC::Logger->new('com.centrify.gp.Registry');
my $DEBUG = $logger->level();

my %file_group = (
    &GP_REG_FILE_CURRENT  => "current",
    &GP_REG_FILE_PREVIOUS => "previous",
    &GP_REG_FILE_LOCAL    => "local",
);

my %group_file = (
    "current"  => GP_REG_FILE_CURRENT,
    "previous" => GP_REG_FILE_PREVIOUS,
    "local"    => GP_REG_FILE_LOCAL,
);

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

sub FullKey($$$)
{
    my ($class, $key, $group) = @_;

    return lc($class) . "/" . lc($key) . "/" . lc($group) ;
}

sub KeyDirectory($$)
{
    my ($class, $key) = @_;

    return $ROOT . "/" . lc($key);
}

sub ProcessRegistryFile()
{
    my $base;
    my $group;
    my $key;

    #
    # Skip files we don't recognize.
    #
    ($base = $File::Find::name) =~ s,.*/([^/]*)$,\1,;
    $group = $file_group{$base};

    if (!defined($group))
    {
        return;
    }

    if ($File::Find::dir =~ m{$ROOT/(.*)})
    {
        $key = lc($1);
    }
    else
    {
        # Not our kind of path.
        return;
    }

    if (! open (REG, "< $File::Find::name"))
    {
        ffdebug("Fatal: Exiting-Cannot read $File::Find::name: $!");
        die("Cannot read $File::Find::name: $!");
    }

    fftrace("Processing Unix Registry file: $File::Find::name");
    while (<REG>)
    {
        chomp;
        fftrace("Processing Unix Registry line: $_");
        my ($value, $type, undef, $data) = $_ =~ /([^;]*);([^;]*);([^;]*);(.*)/;
        fftrace("Parsed Unix Registry line as : value=$value; type=$type; data=$data");

        $type = (REG_TYPE_NAMES)[$type];
        $type = 'REG_UNKNOWN' unless defined($type);

        #
        # Convert the data from the file-based format to our internal
        # representation.
        #
        foreach ($type)
        {
            /REG_DWORD|REG_QWORD/ && do {
                $data =~ s/^0*([0-9])/\1/;
                last;
            };

            /REG_MULTI_SZ/ && do {
                #
                # we want to preserve the trailing empty fields, so set
                # split LIMIT to -1.
                #
                $data = [split(/(?!"),(?!")|",(?!")|(?!"),",/, $data, -1)];
                foreach my $value (@{$data})
                {
                    $value =~ s/","/,/g;
                }
            };
        }

        Store($CLASS, $key, $group, $value, $type, $data);
    }

    close (REG);
    return 1;
}

#
# get all sub registry keys under specified registry key
#
#   $_[0]:  root registry key
#   $_[1]:  registry group.
#           if defined, only get registry keys that have settings for this
#           registry group.
#           if not defined, get registry keys that have settings for any
#           registry group.
#   $_[2]:  user.
#           if defined, get registry keys for specified user
#           if not defined, get machine registry keys
#
#   return: array   - sub registry keys
#           undef   - failed
#
sub GetSubKeys($$$)
{
    my ($root_key, $group, $user) = @_;

    $GROUP_SUBKEY = $group;

    my $options = {
        no_chdir    => 1,
        wanted      => \&ProcessSubKeys,
    };

    if (defined($user))
    {
        $ROOT_SUBKEY = $CentrifyDC::Config::properties{'gp.reg.directory.user'};
        $ROOT_SUBKEY = DEFAULT_REG_PATH . "/users" unless (defined($ROOT_SUBKEY));
        $ROOT_SUBKEY .= "/" . $user;
    }
    else
    {
        $ROOT_SUBKEY = $CentrifyDC::Config::properties{'gp.reg.directory.machine'};
        $ROOT_SUBKEY = DEFAULT_REG_PATH . "/machine" unless (defined($ROOT_SUBKEY));
    }
    #
    # some older Perl modules fail and print message
    # to stderr if the directory does not exist.
    #
    if (! stat($ROOT_SUBKEY)) {
        $logger->log('info', "Directory $ROOT_SUBKEY does not exist: $!");
        return undef;
    }

    my $root_dir = $ROOT_SUBKEY . "/" . lc($root_key);

    # find calls ProcessSubKeys repeatedly, and
    # ProcessSubKeys uses @SUBKEYS to record the subkeys
    # So need to reset it before calling find.
    @SUBKEYS = ();
    
    find($options, $root_dir);

    return @SUBKEYS;
}

sub ProcessSubKeys() 
{
    my $base;
    my $group;
    my $key;

    ($base = $File::Find::name) =~ s,.*/([^/]*)$,\1,;
    $group = $file_group{$base};

    #
    # Skip files we don't recognize.
    #
    if (!defined($group))
    {
        return;
    }

    if (defined($GROUP_SUBKEY) && $group ne $GROUP_SUBKEY)
    {
        return;
    }

    if ($File::Find::dir =~ m{$ROOT_SUBKEY/(.*)})
    {
        $key = lc($1);
    }
    else
    {
        # Not our kind of path.
        return;
    }

    push(@SUBKEYS, $key);

    return 1;
}

sub Load($)
{
    my ($user) = @_;
    my $dir;
    my $root_stat_dir;
    my $options = {
        no_chdir        => 1,
        wanted          => \&ProcessRegistryFile,
    };

    if (defined($user))
    {
	$ROOT = $CentrifyDC::Config::properties{'gp.reg.directory.user'};
	$ROOT = DEFAULT_REG_PATH . "/users" unless (defined($ROOT));
	$ROOT .= "/" . $user;
	$CLASS = "user";
    }
    else
    {
	$ROOT = $CentrifyDC::Config::properties{'gp.reg.directory.machine'};
	$ROOT = DEFAULT_REG_PATH . "/machine" unless (defined($ROOT));
	$CLASS = "machine";
    }
    #
    # some older Perl modules fail and print message
    # to stderr if the directory does not exist.
    #
    $root_stat_dir = stat($ROOT);
    if (!$root_stat_dir) {
        $logger->log('info', "Directory $ROOT does not exist: $!");
        return 0;
    }
    find($options, $ROOT);
    return 1;
}

sub SaveGroup($)
{
    my ($group) = @_;
    my $file = $group_file{$group};
    
    foreach my $key (keys(%registry))
    {
        my $fh;
        my $dir;
        my $class;

        if ($key =~ m{([^/]*)/(.*)/$group$})
        {
            $class = $1;
            $key = $2;
        }
        else
        {
            next;
        }

        $dir = KeyDirectory($class, $key);

        foreach my $value (Values($class, $key, $group))
        {
            my ($type, $data, $value) = Query($class, $key, $group, $value);
            my $size;

            if (! defined($fh))
            {
                $fh = &Symbol::gensym;
                mkpath($dir, 0, 0777);
                open($fh, "> $dir/$file") || die("Cannot write $key: $!");
            }

            #
            # Convert the data from our internal representation to the
            # file-based format, and determine the size.
            #
            foreach ($type)
            {
                /REG_DWORD/ && do {
                    $size = 4;
                    $data = sprintf("%010d", $data);
                    last;
                };

                /REG_QWORD/ && do {
                    $size = 8;
                    $data = sprintf("%020d", $data);
                    last;
                };

                /REG_MULTI_SZ/ && do {
                    foreach my $value (@{$data})
                    {
                        $value =~ s/,/","/g;
                    }
                    $data = join(',', @{$data});
                };

                $size = length($data);
            }

            # Convert the type name to the numeric value.
            eval "\$type = $type";

            printf($fh "%s;%02d;%d;%s\n", $value, $type, $size, $data);
        }

        if (defined($fh))
        {
            close($fh);
        }
    }

    return 1;
}

sub SaveGroupForKey($$$)
{
    my ($class, $key, $group) = @_;
    my $file = $group_file{$group};
    
    my $fh;
    my $dir;

    $dir = KeyDirectory($class, $key);

    foreach my $value (Values($class, $key, $group))
    {
        my ($type, $data, $value) = Query($class, $key, $group, $value);
        my $size;
        if (! defined($fh))
        {
            $fh = &Symbol::gensym;
            mkpath($dir, 0, 0777);
            open($fh, "> $dir/$file") || die("Cannot write $key: $!");
        }

        #
        # Convert the data from our internal representation to the
        # file-based format, and determine the size.
        #
        foreach ($type)
        {
            /REG_DWORD/ && do {
                $size = 4;
                $data = sprintf("%010d", $data);
                last;
            };

            /REG_QWORD/ && do {
                $size = 8;
                $data = sprintf("%020d", $data);
                last;
            };

            /REG_MULTI_SZ/ && do {
                foreach my $value (@{$data})
                {
                    $value =~ s/,/","/g;
                }
                $data = join(',', @{$data});
            };

            $size = length($data);
        }

        # Convert the type name to the numeric value.
        eval "\$type = $type";

        printf($fh "%s;%02d;%d;%s\n", $value, $type, $size, $data);
    }

    if (defined($fh))
    {
        close($fh);
    }
    else
    {
        #
        # No registry setting for specified key. If registry file exists,
        # need to remove this file.
        #
        if (-f "$dir/$file")
        {
            unlink("$dir/$file");
        }
    }

    return 1;
}

sub Query($$$$)
{
    my ($class, $key, $group, $value) = @_;
    my $full_key = FullKey($class, $key, $group);
    my $reg_value = lc($value);

    if (defined($registry{$full_key}{$reg_value}) 
        and scalar @{$registry{$full_key}{$reg_value}})
    {
        return @{$registry{$full_key}{$reg_value}};
    }
    else
    {
        # This will have created a bogus entry in the hash; delete it.
        delete($registry{$full_key}{$reg_value});
        return undef;
    }
}

sub Store($$$$$$)
{
    my ($class, $key, $group, $value, $type, $data) = @_;
    my $full_key = FullKey($class, $key, $group);
    my $reg_value = lc($value);

    @{$registry{$full_key}{$reg_value}} = ($type, $data, $value);
    fftrace("Stored in Registry: Full Key=$full_key; reg_value=$reg_value; group=$group; data=$data");
}

sub Values($$$)
{
    my ($class, $key, $group) = @_;
    my $full_key = FullKey($class, $key, $group);

    if (defined($registry{$full_key}))
    {
	my @values = ();

        foreach my $reg_value (keys(%{$registry{$full_key}}))
	{
	    my ($type, $data, $value) = @{$registry{$full_key}{$reg_value}};
	    push(@values, $value);
	}

	return (@values);
    }
    else
    {
        # This will have created a bogus entry in the hash; delete it.
        delete($registry{$full_key});
        return undef;
    }
}

sub Delete($$$$)
{
    my ($class, $key, $group, $value) = @_;
    my $full_key = FullKey($class, $key, $group);
    my $reg_value = lc($value);

    delete($registry{$full_key}{$reg_value});
}

1;
