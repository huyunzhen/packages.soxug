#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2007-2014 Centrify Corporation. All rights reserved.
#
# Configure sshd settings.
#
#  This mapper script will update sshd_config, then verify it using "sshd -t".
#  If new configuration is valid, it will restart sshd; else original settings
#  will be restored.
#
#  If multiple openssh package are installed on one system, there is no easy
#  way to figure out which one is actually in use. This mapper will search for
#  Centrify openssh first, if not found, it will try to search other
#  pre-defined location. It will only use the first file it found.
#
#  Notice: This mapper will try to find a safe way to restart sshd (i.e. not
#  disconnect already established session), so it will not use killall -HUP.
#  If there's no safe way to restart sshd, it will simply create a log entry,
#  saying that "ssh policy will not take effect until ssh daemon is restarted".
#
##############################################################################

use strict;

use lib '/usr/share/centrifydc/perl';

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug RunCommand GetTempDirPath);
use CentrifyDC::GP::Mapper;
use CentrifyDC::GP::Registry;


# >>> DATA >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $TEMP_DIR = GetTempDirPath(0);
defined($TEMP_DIR) or FATAL_OUT();


my $is_sshd_config_valid = 0;



# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# Try to restart sshd. If sshd is not running or sshd configuration file
# bad option, then sshd won't be restarted.
#
# Return value is not used by caller.
#
#   ret:    0   - successful
#           1   - failed to restart sshd or configuration file error
#           2   - cannot find convenient way to restart sshd
#
sub ::restart_sshd()
{
    if ($is_sshd_config_valid == 0)
    {
        WARN_OUT("sshd configuration file contains bad option. Rollback to original setting. Will not restart sshd.");
        return 1;
    }

    my $system = `uname -s`;
    chomp $system;
    my $command;
    my $sshd_start_script;
    my $ret = 0;

    my @sshd_start_scripts = ("/etc/init.d/centrify-sshd",  # Centrify ssh
                        "/sbin/init.d/centrify-sshd", # Centrify ssh for SunOS/HP-UX
                        "/etc/init.d/sshd",           # SunOS/IRIX/IRIX64/Linux
                        "/sbin/init.d/secsh");        # HP-UX
    foreach my $sshd_start_script (@sshd_start_scripts)
    {
        if (-x $sshd_start_script)
        {
            # Instead of restart, we stop sshd first and then start.
            # If sshd is not running, it will not be started.
            $command = "$sshd_start_script stop && $sshd_start_script start";
            last;
        }
    }

    if (! defined($command))
    {
        if ($system eq "AIX")
        {
            if (-x "/usr/bin/stopsrc" && -x "/usr/bin/startsrc")
            {
                my $subsystem_name = "sshd";
                if (-x "/usr/share/centrifydc/sbin/sshd")
                {
                    # if Centrify openssh is installed, use it.
                    $subsystem_name = "centrify-sshd";
                }
                $command = "/usr/bin/stopsrc -s $subsystem_name && /usr/bin/startsrc -s $subsystem_name";
            }
        }
        elsif ($system eq "IRIX" || $system eq "IRIX64")
        {
            my $pidfile = "/etc/ssh/sshd.pid";
            if (-e $pidfile && -x "/sbin/cat")
            {
                $command = "kill -HUP `/sbin/cat $pidfile`";
            }
            else
            {
                # killall will disconnect established session, so we'll
                # not use it.
                # $command = "killall -HUP sshd";
                $command = "echo ssh daemon configuration file is updated, new settings will take effect once sshd restarts.";
            }
        }
        elsif ($system eq "SunOS")
        {
            my $pidfile = "/var/run/sshd.pid";
            if (-x "/usr/sbin/svcadm")
            {
                $command = "/usr/sbin/svcadm restart ssh";
            }
            elsif (-e $pidfile && -x "/usr/bin/cat")
            {
                $command = "kill -HUP `/usr/bin/cat $pidfile`";
            }
            else
            {
                # pkill will disconnect established session.
                # $command = "pkill -HUP sshd";
                $command = "echo ssh daemon configuration file is updated, new settings will take effect once ssh daemon restarts.";
            }
        }
        elsif ($system eq "Darwin")
        {
            $command = "echo No need to restart ssh daemon on Mac OS X.";
        }
    }

    if (defined($command))
    {
        DEBUG_OUT("Restart ssh daemon to apply ssh policy: [$command]");
        my $rc = RunCommand($command);
        if (! defined($rc) or $rc ne '0')
        {
            DEBUG_OUT("ssh daemon restart failed. ssh policy will not take effect until ssh daemon is restarted.");
            $ret = 1;
        }
        else
        {
            DEBUG_OUT("ssh daemon restarted successfully. ssh group policy is applied.");
            $ret = 0;
        }
    }
    else
    {
        WARN_OUT("Cannot find a convenient method to restart ssh daemon. ssh policy will not take effect until ssh daemon is restarted.");
        $ret = 2;
    }

    return $ret;
}

#
# Try to find sshd and validate the modified sshd_config using "sshd -t".
# If file or keys are invalid, will revert sshd_config.
#
#   ret:    0   - correct
#           1   - incorrect
#           2   - cannot find sshd to verify
#
sub ::verify_sshd_config()
{
    my $ret = 0;
    my $system = `uname -s`;
    chomp $system;
    my $command;

    my @sshd_paths = ("/usr/share/centrifydc/sbin/sshd", # Centrify ssh
                        "/usr/sbin/sshd",           # AIX/HP-UX/SunOS/Darwin/Linux
                        "/usr/lib/ssh/sshd",        # SunOS
                        "/usr/local/sbin/sshd",     # AIX/SunOS
                        "/usr/freeware/sbin/sshd",  # IRIX/IRIX64
                        "/opt/ssh/sbin/sshd");      # HP-UX
    foreach my $sshd_path (@sshd_paths)
    {
        if (-x $sshd_path)
        {
            $command = $sshd_path . " -t";
            last;
        }
    }

    if (defined($command))
    {
        DEBUG_OUT("Validate sshd configuration file and keys: $command");
        my $rc = RunCommand($command);
        if (! defined($rc) or $rc ne '0')
        {
            WARN_OUT("sshd configuration file contains bad option. ssh policy will not be applied.");
            $ret = 1;
        }
        else
        {
            $is_sshd_config_valid = 1;
            DEBUG_OUT("sshd configuration file is correct.");
            $ret = 0;
        }
    }
    else
    {
        WARN_OUT("Cannot find ssh daemon to verify configuration file. ssh policy will not be applied.");
        $ret = 2;
    }

    return $ret;
}



# >>> DATA >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $file = {
    'hierarchy_separator' => '.',
    'list_expr' => ', *| +',
    'list_separator' => ', ',
    'match_expr' => [
      '/([^\s:=]+)[:=]?\s*(.*)/',
    ],
    'comment_markers' => [ '#', ],
    'comment_match_expr' => [
      '/#([^\s:=]+)[:=]?\s*(.*)/',
    ],

    'path' => [
      '/etc/centrifydc/ssh/sshd_config',    # Centrify ssh
      '/usr/local/etc/sshd_config',         # AIX/SunOS
      '/etc/ssh/sshd_config',               # AIX/SunOS/IRIX/IRIX64/Linux
      '/etc/sshd_config',                   # Darwin/SunOS
      '/opt/ssh/etc/sshd_config',           # HP-UX
    ],
    'lock' => "$TEMP_DIR/gp.sshd_config.lock",

    'verify_command' => '::verify_sshd_config()',

    'post_command' => '::restart_sshd()',

    'value_map' => {

      'UsePAM' => {
        'reg_class' => 'machine',

        'reg_key' => 'Software/Policies/Centrify/ssh',
        'reg_value' => 'UsePAM',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'Banner'   => {
        'active'     => '$value_map->{Banner_hidden}{reg_data} ne "0"',
        'default_data' => '/etc/issue',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'Banner',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'Banner_hidden'   => {
        'active'     => '0',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'ssh.banner.enabled',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'ClientAliveCountMax'   => {
        'default_data' => '3',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'ClientAliveCountMax',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'ClientAliveInterval'   => {
        'default_data' => '0',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'ClientAliveInterval',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'AllowGroups'   => {
        'active'     => '$value_map->{AllowGroups_hidden}{reg_data} ne "0"',
        'default_data' => '*',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'AllowGroups',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'AllowGroups_hidden'   => {
        'active'     => '0',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'ssh.allowgroups.enabled',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'AllowUsers'   => {
        'active'     => '$value_map->{AllowUsers_hidden}{reg_data} ne "0"',
        'default_data' => '*',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'AllowUsers',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'AllowUsers_hidden'   => {
        'active'     => '0',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'ssh.allowusers.enabled',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'DenyGroups'   => {
        'active'     => '$value_map->{DenyGroups_hidden}{reg_data} ne "0"',
        'default_data' => '*',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'DenyGroups',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'DenyGroups_hidden'   => {
        'active'     => '0',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'ssh.denygroups.enabled',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'DenyUsers'   => {
        'active'     => '$value_map->{DenyUsers_hidden}{reg_data} ne "0"',
        'default_data' => '*',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'DenyUsers',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'DenyUsers_hidden'   => {
        'active'     => '0',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'ssh.denyusers.enabled',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'GSSAPIAuthentication' => {
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'GSSAPIAuthentication',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'GSSAPIKeyExchange' => {
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'GSSAPIKeyExchange',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'LoginGraceTime'   => {
        'default_data' => '120',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'LoginGraceTime',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'LogLevel'   => {
        'default_data' => 'INFO',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'LogLevel',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'PermitRootLogin'   => {
        'default_data' => 'yes',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'PermitRootLogin',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'Protocol' => {
        'default_data' => '1,2',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'Protocol',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'AuthorizedKeysFile' => {
        'default_data' => '.ssh/authorized_keys',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'AuthorizedKeysFile',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },

      'ApplicationRights' => {
        'active'     => '0', # hidden
        'default_data' => '0',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh',
        'reg_value'  => 'ApplicationRights',
        'reg_type'   => ['REG_DWORD'],
        'value_type' => 'named',
      },

      'ServiceAuthLocation' => {
        'default_data' => '',
        'reg_class'  => 'machine',
        'reg_key'    => 'Software/Policies/Centrify/ssh/ApplicationRights',
        'reg_value'  => 'ServiceAuthLocation',
        'reg_type'   => ['REG_SZ'],
        'value_type' => 'named',
      },


    },

    'write_data' => '$value $data\n',
};

#
# Hard-coded requirements
#

#
# Define if Centrify OpenSSH has to be installed to apply the mapping.
# The group policy value will be removed from the hash ref "$file" if such requirement is not fulfilled.
#
#   hash ref key:       group policy value name
#   hash ref value:     required Centrify OpenSSH (1) or not (0)
#
#   e.g. 'ServiceAuthLocation' => '1',
#
my $requireCentrifyOpenSSH = {
    'ServiceAuthLocation' => '1',
};

#
# Define if a minimum Centrify OpenSSH version has to be installed to apply the mapping.
# The group policy value will be removed from the hash ref "$file" if such requirement is not fulfilled.
#
#   hash ref key:       group policy value name
#   hash ref value:     minimum required Centrify OpenSSH version
#                       (NOTE: major and minor version numbers must be set)
#                       e.g. 4.5.4.112 for "CentrifyDC build 4.5.4-112"
#
#   e.g. 'ServiceAuthLocation' => '4.5.4',
#
my $requireCentrifyOpenSSHVersion = {
    'ServiceAuthLocation' => '4.5.4',
};

#
# Define if OpenSSH has to be installed to apply the mapping.
# The group policy value will be removed from the hash ref "$file" if such requirement is not fulfilled.
#
#   hash ref key:       group policy value name
#   hash ref value:     required OpenSSH (1) or not (0)
#
#   e.g. 'ServiceAuthLocation' => '1',
#
my $requireOpenSSH = {
};

#
# Define if a minimum OpenSSH version has to be installed to apply the mapping.
# The group policy value will be removed from the hash ref "$file" if such requirement is not fulfilled.
#
#   hash ref key:       group policy value name
#   hash ref value:     minimum required OpenSSH version
#                       (NOTE: major and minor version numbers must be set)
#                       e.g. 4.3.2 for "OpenSSH_4.3p2"
#
#   e.g. 'ServiceAuthLocation' => '4.3.2',
#
my $requireOpenSSHVersion = {
};


# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

# NOTE:
# The subroutines above are required by data (e.g. $file), so they are defined
# first. The subroutines here are not required by any data, so they are 
# defined afterwards.

#
# Get Centrify OpenSSH version if it is installed.
#
#   ret:    (1, (a,b,c,d))   - version found
#           (0, undef)       - version not found
#
sub get_system_centrify_openssh_version()
{
    my @ret = (0, undef);
    my $sshd_path = "/usr/share/centrifydc/sbin/sshd";
    my $ssh_version_keyword = "CentrifyDC build";
    my $ssh_version_command = "ssh -V";

    # check if ssh daemon exists
    return @ret unless -x $sshd_path;

    # get ssh version from command
    my ($rc, $commandOutput) = RunCommand($ssh_version_command);
    return @ret unless ($rc eq 0 && defined($commandOutput)) ;

    # verify if the command output has the version keyword
    my $index = index($commandOutput, $ssh_version_keyword);
    return @ret unless $index ne -1;

    # version in the format of [major].[minor].[trivia]-[rev]
    $commandOutput =~ /$ssh_version_keyword (\d+).(\d+).(\d+)-(\d+)/;
    return @ret unless (defined $1 && defined $2 && defined $3 && defined $4);

    my @ssh_version = ($1, $2, $3, $4);
    DEBUG_OUT("Centrify OpenSSH version installed: $1.$2.$3.$4\n");

    @ret = (1, @ssh_version);

    return @ret;
}

sub get_system_openssh_version()
{
    # TODO: To be implemented
    return;
}

sub parse_version_from_text($)
{
    my @ret = (0, undef);

    my $text = $_[0];
    my ($major, $minor, $trivia, $rev) = split(/\./, $text);

    # major and minor numbers are required
    return @ret unless defined $major && defined $minor;
    
    $trivia = 0 unless defined $trivia;
    $rev = 0 unless defined $rev;
    
    TRACE_OUT("Version parsed: $major.$minor.$trivia.$rev\n");

    my @ssh_version = ($major, $minor, $trivia, $rev);
    
    @ret = (1, @ssh_version);
    return @ret;
}

#
# Compare software versions to check if current version passes the 
# minimum version requirement.
#
#   ret:    1   - passed
#           0   - failed
#
sub compare_versions($$)
{
    my @version = @{$_[0]};
    my @version_min = @{$_[1]};
    TRACE_OUT("Current version: @version[0].@version[1].@version[2].@version[3]\n");
    TRACE_OUT("Minimum version: @version_min[0].@version_min[1].@version_min[2].@version_min[3]\n");

    # compare versions
    # same version is regarded as passed
    my $passed_version_check = 0;
    my $i;

    for ($i = 0; $i < 4; $i++)
    {
        if (@version[$i] > @version_min[$i])
        {
            $passed_version_check = 1;
            last;
        }
        elsif (@version[$i] < @version_min[$i])
        {
            $passed_version_check = 0;
            last;
        }
        else
        {
            # check next version digit if equal
            next;
        }
    }

    return $passed_version_check;
}

sub check_centrify_openssh_requirements()
{
    # get Centrify OpenSSH version if installed
    my ($ssh_installed_current, @ssh_version_current) = get_system_centrify_openssh_version();

    # check if Centrify OpenSSH is required
    foreach my $key (keys %$requireCentrifyOpenSSH)
    {
        my $required = $requireCentrifyOpenSSH->{$key};

        # delete hash reference if Centrify OpenSSH is NOT installed
        if ($required ne 0 &&
            $ssh_installed_current eq 0)
        {
            DEBUG_OUT("$key does not meet requirement (Centrify OpenSSH)\n");
            delete $file->{"value_map"}{$key} if exists $file->{"value_map"}{$key};
        }
    }

    # check if required Centrify OpenSSH version is installed
    foreach my $key (keys %$requireCentrifyOpenSSHVersion)
    {
        # do not handle if invalid format
        my ($parse_success, @ssh_version_min) = parse_version_from_text($requireCentrifyOpenSSHVersion->{$key});
        next if not $parse_success;

        # delete hash reference if required Centrify OpenSSH version is NOT installed
        if ($ssh_installed_current eq 0 ||
            compare_versions(\@ssh_version_current, \@ssh_version_min) eq 0)
        {
            DEBUG_OUT("$key does not meet requirement (Centrify OpenSSH version)\n");
            delete $file->{"value_map"}{$key} if exists $file->{"value_map"}{$key};
        }
    }
}

sub check_openssh_requirements()
{
    # TODO: To be implemented
    return;
}

sub check_requirements()
{
    check_centrify_openssh_requirements();
    check_openssh_requirements();
}


# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $args = CentrifyDC::GP::Args->new();

my $user  = $args->user();
my $class = $args->class();

# unset the LIBPATH/LD_LIBRARY_PATH to make both 
# old stock sshd (4.1) which uses stock libcrypto.a/.so and 
# centrify-sshd which uses cdc libcrypto.a/.so happy
exists($ENV{LIBPATH}) && delete $ENV{LIBPATH};
exists($ENV{LD_LIBRARY_PATH}) && delete $ENV{LD_LIBRARY_PATH};

# load registry
CentrifyDC::GP::Registry::Load(undef);
if ($class eq "user")
{
    CentrifyDC::GP::Registry::Load($user);
}

# determine if specific GP data should be proceeded
&check_requirements();

# map or unmap data
if ($args->isMap())
{
    CentrifyDC::GP::Mapper::Map($file, $args->user());
}
else
{
    CentrifyDC::GP::Mapper::UnMap($file, $args->user());
}

