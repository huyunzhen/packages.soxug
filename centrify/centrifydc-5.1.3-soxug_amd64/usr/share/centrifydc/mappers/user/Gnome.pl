#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Machine/user mapper script to apply Gnome Desktop settings.
#
# This script check root privilege and gconftools-2 existence at start, then
# dump and parse all GConf settings and schemas of current system at runtime.
# Once all GConf settings and schemas have been loaded into the build-in hash,
# compare each GConf setting with virtual registry, and decide which group value
# should be applied.
#
#   Map:     Apply Gnome Desktop Group Policy settings
#   Unmap:   Restore local Gnome Desktop settings
#
# Parameters: <map|unmap> <username> <mode>
#   map|unmap   action to take
#   username    username
#   mode        should be "login|refresh|force"
#
# Exit value:
#   0   Normal
#   1   Error
#   2   Usage
#
##############################################################################


use strict;
use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug RunCommand WriteFile GetTempDirPath);
use CentrifyDC::GP::RegHelper;


# >>> DATA >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $TEMP_DIR = GetTempDirPath(0);
defined($TEMP_DIR) or FATAL_OUT();


my @dirs = ('/bin', '/usr/bin', '/usr/local/bin', '/opt/bin', '/opt/gnome/bin');
my $gconftool = "gconftool-2";

my $REGKEY = "software/policies/centrify/gnome";
my $STATIC_CACHE = "/usr/share/centrifydc/mappers/gnomecache/gconf_static_cache.dat";
my $DYNAMIC_CACHE = "/usr/share/centrifydc/mappers/gnomecache/gconf_dynamic_cache.dat";


# >>> SUBROUTINE >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

sub CheckPrivilege();
sub CheckGConftool();
sub LoadCache();
sub Trim($);
sub GConftoolErr($$);
sub RemoveDuplicateItems($);
sub GetGConfSetting($$);
sub GetGConfSchema($$);
sub SetGConfSetting($$$$);
sub RestoreGConfSetting($$$$$$);
sub ProcessManagementKey($$$$$);
sub ProcessGConfKey($$$$$$);
sub DoMap($$$);

#
# Check if user run this script with root privilege.
#
#   return: 1           - with root privilege
#           undef       - no root privilege
#
sub CheckPrivilege()
{
    ($> != 0) && ($< != 0) ? return undef : return 1;
}

#
# Check if gconftool-2 is installed in current system.
#
#   return: 1           - installed
#           undef       - not installed
#
sub CheckGConftool()
{
    foreach my $path (@dirs)
    {
        my $file = "$path/$gconftool";
        if (-e $file && -x $file)
        {
            $gconftool = $file;
            return 1;
        }
    }
    
    return undef;
}

#
# Load the specific cache file.
#
#   $_[0]:  hash reference of the gconf cache. 
#   $_[1]:  cache file will be loaded to cache hash. 
#   return: 1           - successful
#           undef       - failed
#
sub LoadCacheFile($$)
{
    my ($cache, $file) = @_;
    
    if (open(FILE, $file) == 0)
    {
        DEBUG_OUT("Can not load cache file: $file");
        return undef;
    }

    my @lines = <FILE>;
    foreach my $line (@lines)
    {
        chomp($line);
        
        my @items = split(':', $line);
        if (scalar(@items) == 5)
        {
            my $key = $items[0];
            
            $cache->{$key}->{type} = $items[1];
            $cache->{$key}->{list_type} = $items[2];
            $cache->{$key}->{car_type} = $items[3];
            $cache->{$key}->{cdr_type} = $items[4];
        }
    }
    
    close(FILE);
    
    return 1;
}

#
# Load cache file(s) contain data type of each GConf Keys.
#
#   return: hash reference of the gconf cache   - successful
#           undef                               - failed
#
sub LoadCache()
{
    my %cache;
    
    # Load static cache
    my $result = LoadCacheFile(\%cache, $STATIC_CACHE);
    if (!defined($result))
    {
        DEBUG_OUT("Can not load static cache.");
    }
    
    # Load dynamic cache
    my $result = LoadCacheFile(\%cache, $DYNAMIC_CACHE);
    if (!defined($result))
    {
        DEBUG_OUT("Can not load dynamic cache.");
    }
    
    return \%cache;
}

#
# Strip whitespace(s) from the beginning and end of a string.
#
#   $_[0]:  The source string 
#   return: The string removed whitespace(s)
#
sub Trim($)
{
    my $str = shift;
    
    if ($str) {
      $str =~ s/^\s+//;
      $str =~ s/\s+$//;
    }
    
    return $str;
}

#
# Check if error occured after run gconftool-2 command against GConf Key.
#
#   $_[0]:  gconftool-2 command output  
#   $_[0]:  GConf Key the gconftool-2 command run against
#   return: 1          - error occured
#           0          - no error occured
#
sub GConftoolErr($$)
{
    my ($msg, $key) = @_;
    
    if (index($msg, "No value set for \`$key") != -1)
    {
        return 1;
    }
    
    if (index($msg, "Failed to get value for \`$key") != -1)
    {
        return 1;
    }
    
    if (index($msg, "No schema known for \`$key") != -1)
    {
        return 1;
    }
    
    if (index($msg, "No value to set for key: \`$key") != -1)
    {
        return 1;
    }
    
    if (index($msg, "Must specify a type when setting a value") != -1)
    {
        return 1;
    }
    
    return 0;
}

#
# Remove duplicate items from array.
#
#   $_[0]:  reference of source array 
#   return: output array
#
sub RemoveDuplicateItems($)
{
    my ($array) = shift;

    my %hash;
    @hash{@$array} = ();

    return sort keys %hash;
}

#
# Load system setting of a group of gconf keys.
#
#   $_[0]:  username 
#   $_[1]:  reference of gconf key array 
#   return: hash reference contained gconf settings     - successful
#           undef                                       - failed
#
sub LoadGConfSettings($$)
{
    my ($user, $keys) = @_;
    
    my %gconf_settings;
    
    # Place gconftool command in temp shell script file, since directly call sudo
    # with huge number parameters will cause 'Argument list too long' failure.
    my $temp_cmd_file = "$TEMP_DIR/gnome.sh";
    # When SELinux enabled, privileged script running with sudo must have hashbang.
    my $cmd_str = "#!/bin/sh\n";
    $cmd_str .= "$gconftool -g " . join(' ', @$keys);
    
    if (WriteFile($temp_cmd_file, $cmd_str) != 1) {
        ERROR_OUT("Failed to write Gnome temp command file.");
        return undef;
    }
    
    chmod(0755, $temp_cmd_file);
    
    my $cmd = "sudo -u '$user' '$temp_cmd_file'";
    my ($ret, $output) = RunCommand($cmd);
    unlink($temp_cmd_file);
    
    if ($ret != 0)
    {
        return undef;
    }
    
    my $count = @$keys;
    my @lines = split('\n', $output);
    
    for (my $index = 0; $index < $count; $index++)
    {
        my $key = $keys->[$index];
        my $data = $lines[$index];
        
        if ((index($data, "No value set for \`$key") != -1) ||
            (index($data, "Failed to get value for \`$key") != -1))
        {
            next;
        }
        
        $gconf_settings{$key} = $data;
    }
    
    return \%gconf_settings;
}

#
# Get GConf setting of the specific GConf Key and specific user.
#
#   $_[0]:  Username 
#   $_[1]:  GConf Key 
#   return: GConf setting  - successful
#           undef          - failed
#
sub GetGConfSetting($$)
{
    my ($user, $key) = @_;
    
    my ($ret, $output) = RunCommand("sudo -u '$user' $gconftool -g $key");
    
    if ($ret || GConftoolErr($output, $key))
    {
        return undef;
    }
    
    chomp($output);
    
    return $output;
}

#
# Add new item in GConf data type cache file.
#
#   $_[0]:  Cache file 
#   $_[1]:  GConf Key
#   $_[1]:  Hash contains data type info of this GConf Key, which will be
#           added to cache file.
#
#   Defination of data type hash:
#   my $schema = {
#                    type => xxx,
#                    list_type => xxx,
#                    car_type => xxx,
#                    cdr_type => xxx,
#                };
#   
#   return: 1           - successful
#           undef       - failed
#
sub UpdateCacheFile($$$)
{
    my ($file, $key, $schema) = @_;
    
    if (open(FILE, ">>$file") == 0)
    {
        DEBUG_OUT("Can not update cache file: $file");
        return undef;
    }

    print FILE "$key:$schema->{type}:$schema->{list_type}:$schema->{car_type}:$schema->{cdr_type}\n";
    
    close(FILE);
    
    return 1;
}

#
# Get schema of the specific GConf Key.
# If the schema exists in cache, return it directly.
# Otherwise, get this schema at runtime, then add it to dynamic cache
# and return it.
#
#   $_[0]:  Hash reference of GConf data type cache
#   $_[1]:  GConf Key
#   return: Hash reference contained the GConf schema   - successful
#           undef                                       - failed
#
sub GetGConfSchema($$)
{
    my ($cache, $key) = @_;
    
    if (defined($cache->{$key}))
    {
        # Exists in cache, return it directly.
        return $cache->{$key};
    }
    
    # Get the schema at runtime.
    my ($ret, $output) = RunCommand("$gconftool --get-schema-name $key");
    if ($ret || GConftoolErr($output, $key))
    {
        # Can not get schema name of this GConf Key.
        return undef;
    }
    
    my $schema_key = $output;
    
    ($ret, $output) = RunCommand("$gconftool -g $schema_key");
    if ($ret || GConftoolErr($output, $key))
    {
        # Can not get schema of this GConf Key.
        return undef;
    }

    if ($output =~ m/Type: (\w+)\s+List Type: (\S+)\s+Car Type: (\S+)\s+Cdr Type: (\S+)/i)
    {
        my $schema = {
                        type => $1,
                        list_type => $2,
                        car_type => $3,
                        cdr_type => $4,
                     };
        
        # Add this schema to dynamic cache
        $ret = UpdateCacheFile($DYNAMIC_CACHE, $key, $schema);
        if (!defined($ret))
        {
            DEBUG_OUT("Failed to add dynamic cache for GConf Key: $key");
        }
        
        return $schema;
    }
    
    return undef;
}

#
# Set GConf setting of the specific GConf Key and specific user.
# Unset this GConf setting when you specify $_[3] as undef.
#
#   $_[0]:  Username 
#   $_[1]:  GConf Key 
#   $_[2]:  Schema of this GConf Key 
#   $_[3]:  Value to be set 
#   return: 1          - successful
#           undef      - failed
#
sub SetGConfSetting($$$$)
{
    my ($user, $key, $schema, $data) = @_;
    
    my $cmd;
    
    if (defined($data))
    {
        # Escape quotes.
        $data =~ s/"/\\"/g;
        
        my $type = $schema->{type};
        
        if ($type eq 'list')
        {
            # For list type, restore leading '[' and ending ']' characters.
            $cmd = "sudo -u '$user' $gconftool -s -t $type --list-type $schema->{list_type} $key \"[$data]\"";
        }
        elsif ($type eq 'car')
        {
            $cmd = "sudo -u '$user' $gconftool -s -t $type --car-type $schema->{car_type} $key \"[$data]\"";
        }
        elsif ($type eq 'cdr')
        {
            $cmd = "sudo -u '$user' $gconftool -s -t $type --cdr-type $schema->{cdr_type} $key \"[$data]\"";
        }
        else
        {
            $cmd = "sudo -u '$user' $gconftool -s -t $type $key \"$data\"";
        }
    }
    else
    {
        $cmd = "sudo -u '$user' $gconftool -u $key";
    }
    
    my ($ret, $output) = RunCommand($cmd);
    if ($ret || GConftoolErr($output, $key))
    {
        # Failed to run this command.
        return undef;
    }
    
    return 1;
}

#
# Restore GConf setting of the specific GConf Key and specific user with the
# value saved in 'local' virtual registry.
#
#   $_[0]:  action ('map' or 'unmap')
#   $_[1]:  class ('User' or 'Machine')
#   $_[2]:  username
#   $_[3]:  key of Gnome management GP
#   $_[4]:  hash reference of GConf data type cache
#   $_[5]:  hash reference of GConf Key system settings
#   return: 1       - successful
#           undef   - failed
#
sub RestoreGConfSetting($$$$$$)
{
    my ($action, $class, $user, $gconf_key, $cache, $gconf_settings) = @_;
    
    DEBUG_OUT("Restore GConf Key setting: user [$user] key [$gconf_key]");
    
    # Create RegHelper instance
    my $reg = CentrifyDC::GP::RegHelper->new($action, $class, $REGKEY, $gconf_key);
    if (!defined($reg))
    {
        DEBUG_OUT("Failed to create RegHelper instance.");
        return undef;
    }
    
    # Load current/previous/local registry setting.
    $reg->load();
    
    my $gconf_data = $gconf_settings->{$gconf_key};
    if (!defined($gconf_data))
    {
        DEBUG_OUT("Can not get system value: user [$user] gconf_key [$gconf_key]");
    }
    
    my $gconf_schema = GetGConfSchema($cache, $gconf_key);
    if (!defined($gconf_schema))
    {
        DEBUG_OUT("Can not get schema: user [$user] gconf_key [$gconf_key]");
        return undef;
    }
    
    my $gconf_type = $gconf_schema->{type};
    
    # For bool type, convert true/false to 1/0.
    if ($gconf_type eq 'bool')
    {
        if ($gconf_data eq 'true')
        {
            $gconf_data = 1;
        }
        else
        {
            $gconf_data = 0;
        }
        
        $reg->{'type'} = 'REG_DWORD';
    }
    
    # For list type, remove leading '[' and ending ']' characters.
    if ($gconf_type eq 'list')
    {
        $gconf_data =~ s/^\[//;
        $gconf_data =~ s/\]$//;
    }
    
    # Skip this key if system setting equals to local registry setting.
    if ($gconf_data eq $reg->{'local'})
    {
        return 1;
    }
    else
    {
        $gconf_data = $reg->{'local'};
    }
    
    my $ret = SetGConfSetting($user, $gconf_key, $gconf_schema, $gconf_data);
    if (!defined($ret))
    {
        DEBUG_OUT("Failed to restore GConf setting: user [$user] gconf_key [$gconf_key] gconf_type [$gconf_type] gconf_data [$gconf_data]");
        return undef;
    }
        
    DEBUG_OUT("GConf setting restored: user [$user] gconf_key [$gconf_key] gconf_type [$gconf_type] gconf_data [$gconf_data]");
    
    return 1;
}

#
# Process Gnome management GP.
# If user enables this GP, all Gnome GP will take effect.
# If user disables this GP, all Gnome GP will be ignored, and mapper script
# will restore all gconf keys defined in 'local' registry group.
#
#   $_[0]:  action ('map' or 'unmap')
#   $_[1]:  class ('User' or 'Machine')
#   $_[2]:  username
#   $_[3]:  key of Gnome management GP
#   $_[4]:  Hash reference of GConf data type cache
#   return: 1       - successful
#           undef   - failed
#
sub ProcessManagementKey($$$$$)
{
    my ($action, $class, $user, $key, $cache) = @_;
    
    DEBUG_OUT("Process Management Key: user [$user] key [$key]");
    
    # Create RegHelper instance
    my $reg = CentrifyDC::GP::RegHelper->new($action, $class, $REGKEY, $key);
    
    if (!defined($reg))
    {
        DEBUG_OUT("Failed to create RegHelper instance.");
        return undef;
    }
    
    # Load current registry setting.
    $reg->load();
    
    my $current = $reg->{'current'};
    my $previous = $reg->{'previous'};
    DEBUG_OUT("Current Management Key setting: current/previous [$current/$previous]");
    
    if ($current != 1)
    {
        if ($previous != 1)
        {
            # Both current/previous setting are not enabled, do nothing.
            return 2;
        }
        
        # If management key is disabled, ignore all Gnome GPs and restore
        # all gconf keys defined in 'local' registry group, then quit.
        my @local_values = CentrifyDC::GP::Registry::Values($class, $REGKEY, 'local');
        
        my $gconf_settings = LoadGConfSettings($user, \@local_values);
        if (!defined($gconf_settings))
        {
            DEBUG_OUT("Failed to load system setting of gconf keys.");
            return undef;
        }
        
        foreach my $gconf_key (@local_values)
        {
            RestoreGConfSetting($action, $class, $user, $gconf_key,
                                $cache, $gconf_settings);
        }
        
        return 3;
    }
    
    return 1;
}

#
# Process the specific GConf Key.
#
#   $_[0]:  action ('map' or 'unmap') 
#   $_[1]:  class ('User' or 'Machine') 
#   $_[2]:  username 
#   $_[3]:  GConf Key 
#   $_[4]:  hash reference of GConf data type cache
#   $_[5]:  hash reference of GConf Key system settings
#   return: 1       - successful
#           undef   - failed
#
sub ProcessGConfKey($$$$$$)
{
    my ($action, $class, $user, $gconf_key, $cache, $gconf_settings) = @_;
    
    DEBUG_OUT("Process GConf Key: user [$user] gconf_key [$gconf_key]");
    
    # Create RegHelper instance
    my $reg = CentrifyDC::GP::RegHelper->new($action, $class, $REGKEY, $gconf_key);
    if (!defined($reg))
    {
        DEBUG_OUT("Failed to create RegHelper instance.");
        return undef;
    }
    
    # Load current/previous/local registry setting.
    $reg->load();
    
    if ($action eq 'map')
    {
        # Skip following case(s) when do map.
        if (!defined($reg->{'current'}) && !defined($reg->{'previous'}))
        {
            DEBUG_OUT("'current' and 'previous' group values are not defined, skip: user [$user] gconf_key [$gconf_key]");
            return 1;
        }
    }
    else
    {
        # Skip following case(s) when do unmap.
        if (!defined($reg->{'local'}))
        {
            DEBUG_OUT("'local' group value is not defined, skip: user [$user] gconf_key [$gconf_key]");
            return 1;
        }
    }
    
    my $gconf_data = $gconf_settings->{$gconf_key};
    if (!defined($gconf_data))
    {
        DEBUG_OUT("Can not get system value: user [$user] gconf_key [$gconf_key]");
    }
    
    my $gconf_schema = GetGConfSchema($cache, $gconf_key);
    if (!defined($gconf_schema))
    {
        DEBUG_OUT("Can not get schema: user [$user] gconf_key [$gconf_key]");
        return undef;
    }
    
    # Put system gconf setting into RegHelper.
    my $gconf_type = $gconf_schema->{type};
    
    # For bool type, convert true/false to 1/0.
    if ($gconf_type eq 'bool')
    {
        if ($gconf_data eq 'true')
        {
            $gconf_data = 1;
        }
        
        if ($gconf_data eq 'false')
        {
            $gconf_data = 0;
        }
        
        $reg->{'type'} = 'REG_DWORD';
    }
    
    # For list type, remove leading '[' and ending ']' characters.
    if ($gconf_type eq 'list')
    {
        $gconf_data =~ s/^\[//;
        $gconf_data =~ s/\]$//;
    }
    
    $reg->{'system'} = $gconf_data;
    
    # RegHelper is ready. determine what to do and do it.
    my $group = $reg->getGroupToApply();
    DEBUG_OUT("Registry group to apply: $group");
    
    if ($group)
    {
        # Update system gconf setting.
        my $data = $reg->{$group};
        
        my $ret = SetGConfSetting($user, $gconf_key, $gconf_schema, $data);
        if (!defined($ret))
        {
            DEBUG_OUT("Failed to apply GConf setting: user [$user] gconf_key [$gconf_key] gconf_type [$gconf_type] gconf_data [$data]");
            return undef;
        }
        
        DEBUG_OUT("GConf setting applied: user [$user] gconf_key [$gconf_key] gconf_type [$gconf_type] gconf_data [$data]");
    }
    
    return 1;
}

#
# Map all GConf Keys.
#
#   $_[0]:  action ('map' or 'unmap') 
#   $_[1]:  class ('User' or 'Machine') 
#   $_[2]:  username 
#   return: 1       - successful
#           undef   - failed
#
sub DoMap($$$)
{
    my ($action, $class, $user) = @_;
    
    my $ret = 1;
    
    # Load GConf Key data type cache. 
    my $cache = LoadCache();
    if (!defined($cache))
    {
        DEBUG_OUT("Failed to load gconf cache.");
    }
    
    # Handle Gnome management GP.
    my $result = ProcessManagementKey($action, $class, $user, 'EnableGnomeSettings', $cache);
    if (!defined($result))
    {
        DEBUG_OUT("Failed to process Gnome management GP.");
        return undef;
    }
    else
    {
        if ($result != 1)
        {
            DEBUG_OUT("Gnome GPs were disabled.");
            return 1;
        }
    }
    
    my @current_values = CentrifyDC::GP::Registry::Values($class, $REGKEY, 'current');
    my @previous_values = CentrifyDC::GP::Registry::Values($class, $REGKEY, 'previous');
    my @local_values = CentrifyDC::GP::Registry::Values($class, $REGKEY, 'local');
    
    my @keys = (@current_values, @previous_values, @local_values);
    @keys = RemoveDuplicateItems(\@keys);
    
    # Empty key returned when any group of current/previous/local not exist, remove it.
    @keys = grep(/\S+/, @keys);
    
    # To increase performance, load system setting of all gconf keys in one shell command.
    my $gconf_settings = LoadGConfSettings($user, \@keys);
    if (!defined($gconf_settings))
    {
        DEBUG_OUT("Failed to load system setting of gconf keys.");
        return undef;
    }
    
    foreach my $key (@keys)
    {
        # Skip debug key and management key.
        next if $key eq 'DebugGnomeSettings';
        next if $key eq 'EnableGnomeSettings';
        
        $result = ProcessGConfKey($action, $class, $user, $key,
                                     $cache, $gconf_settings);
        if (!defined($result))
        {
            DEBUG_OUT("Can not process GConf Key: $key");
            next;
        }
    }
    
    return $ret;
}


# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $args = CentrifyDC::GP::Args->new('user');

my $action = $args->action();
my $class = $args->class();
my $user = $args->user();

my $ret = CheckPrivilege();
if (!defined($ret))
{
    FATAL_OUT("Need root privilege to run this program.");
}

$ret = CheckGConftool();
if (!defined($ret))
{
    DEBUG_OUT("$gconftool not found!");
    exit(0);
}

CentrifyDC::GP::Registry::Load($user);
$ret = DoMap($action, $class, $user);

$ret or FATAL_OUT();
