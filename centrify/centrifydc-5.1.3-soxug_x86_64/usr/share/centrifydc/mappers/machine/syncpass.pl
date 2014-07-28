#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2008-2014 Centrify Corporation. All rights reserved.
#
# Machine mapper script to synchronize mapped user's password by putting
#  password hash into local shadow file.
#
#  Supported OS: Solaris / HP-UX (Untrusted Mode) / Linux / AIX
#
#  The script first gets a list of mapped local users that need to sync
#  password from pam.sync.mapuser property in centrifydc.conf, then gets
#  the associated AD users from pam.mapuser.<localuser> properties in
#  centrifydc.conf. It then uses   adquery user -H <ADuser>   to get
#  password hash and update password field of local shadow file for mapped
#  local users.
#
#  The script uses pwck to validate the shadow file before and after updating
#  it. If validation fails before update, the script will report error and
#  quit; if validation fails after update, the script will report error and
#  restore original shadow file from backup.
#
#  The script will not restore old password when leaving domain.
#
#  The script will not read registry settings or update centrifydc.conf.
#  Instead, it will get setting from centrifydc.conf. The generic mapper,
#  centrifydc.conf.pl, is responsible for updating pam.sync.mapuser property
#  in centrifydc.conf.
#
#
#  Map:     update password field in local shadow file for mapped local users
#           based on pam.sync.mapuser property
#              Not Configured: do nothing
#              Enable:         update
#              Disable:        do nothing
#
#  Unmap:   do nothing
#
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

use File::Copy;

use CentrifyDC::GP::Args;
use CentrifyDC::GP::General qw(:debug RunCommand ReadFile WriteFile IsEqual);
use CentrifyDC::GP::Mapper;
use CentrifyDC::Config;

my $ostype;             # Operating System's Name
my $HOSTNAME;           # Host Name
my $ZONE;               # Zone Name that this machine joined to
my %mapping;            # mapping list, local users as key, AD users' passwords as hash
my @local;              # A list of items for local shadow file
my $pwck;               # password checking tools
my $pwconv_cmd;         # pwconv command
my $yes_cmd;            # yes command

my $appdix;             # suffix for backup, prevent overwritten to existing backup file.

my @supported_platforms = qw(sunos solaris hp-ux linux aix);

sub ConvertToShadow();
sub UpdateAIX();
sub UpdateNormalShadowFile();
sub UpdateLocalShadow();
sub ReadLocalShadow();
sub GetMappingList();
sub ParseOutZoneName();
sub GetSystemInfo();
sub GetADPassword($);
sub CheckPlatform();
sub CheckCommands();



# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# Convert from passwd to shadow file (for non-AIX platforms).
#
#   Return: 1       - successful
#           undef   - failed
#
sub ConvertToShadow()
{
    ($ostype eq 'aix') and return 1;

    DEBUG_OUT("Convert passwd to shadow passwd");

    my $yes_cmd_full = $yes_cmd;
    if ($ostype eq 'hp-ux')
    {
        #
        # According to QA, pwconv on HPUX 11.23 expects "yes" instead of the 
        # default "y" returned by the yes command. On HPUX 11.11 and 11.31, 
        # pwconv expects nothing.
        #
        $yes_cmd_full = "$yes_cmd yes";
    }

    #
    # may not be safe to use RunCommand function, as RunCommand also
    # uses pipe to get command output.
    #
    my $cmd = "$yes_cmd_full | $pwconv_cmd";
    DEBUG_OUT("run command: [$cmd]");

    system($cmd);

    my $ret = $? >> 8;
    if ($? == -1)
    {
        ERROR_OUT("Failed to execute command [$cmd]: $!");
    }
    elsif ($? & 127)
    {
        # command terminated by signal
        ERROR_OUT("Command [$cmd] terminated by signal " . ($? & 127));
        $ret = undef;
    }
    else
    {
        DEBUG_OUT("Command returns $ret");
    }

    if($ret != 0)
    {
        ERROR_OUT("pwconv error: can't convert from passwd to shadow!");
        return undef;
    }

    return 1;
}

#
# Update AIX's local shadow file, in /etc/security/passwd
#
#   Return: 1   - success
#           0   - failed
#
sub UpdateAIX()
{
    # checking existing shadow file. But we'll do nothing if it has problem
    # as it's quite normal
    TRACE_OUT("Check shadow file");
    my ($prerc, $preout) = RunCommand("$pwck");
    if ($prerc ne '0' )
    {
        DEBUG_OUT("$pwck failed with the following message: $preout");
    }

    # backup existing shadow file
    my $orgShadow = "/etc/security/passwd";
    my $bakShadow = "/etc/security/passwd.$appdix";
    TRACE_OUT("Backup shadow file $orgShadow to $bakShadow");
    if (!copy($orgShadow, $bakShadow) )
    {
        ERROR_OUT("Can't backup shadow: $! .");
        return 0;
    }

    # generate content for updated shadow file
    my $shadowStr = '';
    foreach my $u( @local)
    {
        if( (! $u->[2]) && exists $mapping{$u} )
        {
            $u->[2] = time();
        }

        my $val = $u->[0];
        $shadowStr .= "$val:\n"; # name
        $val = $u->[1];
        $shadowStr .= "\tpassword = $val\n"; # password hash

        if($u->[2] || $u->[3] )  # update lastudpate and flags or not
        {
            $val = $u->[2];
            $shadowStr .= "\tlastupdate = $val\n"; # last update
            $val = $u->[3];
            $shadowStr .= "\tflags = $val\n"; # flags
        }

        $shadowStr .= "\n";
    }

    # update local shadow file
    DEBUG_OUT("Update shadow file");
    WriteFile($orgShadow, $shadowStr)
        or (ERROR_OUT("Can't write to shadow file.") and return 0);

    # checking the updated shadow file. If failed, keep the previously backuped copy.
    TRACE_OUT("Verify new shadow file");
    my ($rc, $output) = RunCommand("$pwck");
    if (!IsEqual($rc, $prerc))
    {
        if ($rc ne '0')
        {
            WARN_OUT("After updating shadow, $pwck failed with the following message: $output" );
            WARN_OUT("shadow file may be broken after syncing user's shadow password." );
            WARN_OUT("keep the original shadow file " . $bakShadow);
        }
        else
        {
            WARN_OUT("Before updating shadow file, $pwck failed. After update, $pwck passed. Original shadow file is saved as $bakShadow");
        }
    } 
    else 
    {
        TRACE_OUT("New shadow file verified. Remove backup");
        unlink($bakShadow);
    }

    return 1;
}

#
# Update normal shadow file in /etc/shadow
#
#   Return: 1   - success
#           0   - failed
#
sub UpdateNormalShadowFile()
{
    # checking existing shadow file
    TRACE_OUT("Check shadow file");
    my ($prerc, $preout) = RunCommand("$pwck");
    if ($prerc ne '0' )
    {
        DEBUG_OUT("$pwck failed with the following message: $preout");
    }

    # backup
    my $orgShadow = "/etc/shadow";
    my $bakShadow = "/etc/shadow.$appdix";
    TRACE_OUT("Backup shadow file $orgShadow to $bakShadow");
    copy($orgShadow, $bakShadow)
        or ( ERROR_OUT("Can't backup shadow: $!.") and return 0 );

    # generate new content
    my $shadowStr = '';
    foreach my $k (@local)
    {
        $shadowStr .= join(":", @$k);
    }

    # update shadow file
    DEBUG_OUT("Update shadow file");
    WriteFile($orgShadow, $shadowStr)
        or ( ERROR_OUT("can't write to shadow file!") and return 0 );

    # checking the updated shadow file. If failed, keep the previously backuped copy.
    TRACE_OUT("Verify new shadow file");
    my ($rc, $output) = RunCommand("$pwck");
    if (!IsEqual($rc, $prerc))
    {
        if ($rc ne '0')
        {
            WARN_OUT("After updating shadow, $pwck failed with the following message: $output" );
            WARN_OUT("shadow file may be broken after syncing user's shadow password." );
            WARN_OUT("keep the original shadow file " . $bakShadow);
        }
        else
        {
            WARN_OUT("Before updating shadow file, $pwck failed. After update, $pwck passed. Original shadow file is saved as $bakShadow");
        }
    } 
    else 
    {
        TRACE_OUT("New shadow file verified. Remove backup");
        unlink($bakShadow);
    }

    return 1;
}

#
# Update local shadow file
#
#   Return: 1   - success
#           0   - failed
#
sub UpdateLocalShadow()
{
    if($ostype eq 'aix') # saved in /etc/security/passwd, for AIX
    {
        return UpdateAIX();
    }
    else  # saved in /etc/shadow, for linux, hpux and solaris
    {
        return UpdateNormalShadowFile();
    }

    return 1;
}

#
# Read current shadow file, check whether there is an update.
#
#   Return: 2   - success
#           1   - an update is required
#           0   - failed to read shadow file
#
sub ReadLocalShadow()
{
    my $update = 2;
    my $shadow_file;

    if($ostype eq 'aix' )
    {
        # pattern to parse out a shadow item
        my $pat = '\s*(\S+):\s*password = (\S+)\s*(lastupdate = (\S+)\s+flags = (\S*))?';

        # read current shadow file
        $shadow_file = '/etc/security/passwd';
        TRACE_OUT("Read shadow file $shadow_file");
        my $text = ReadFile($shadow_file);
        if (! $text)
        {
            ERROR_OUT("Cannot read shadow file $shadow_file");
            return 0;
        }

        # parse out the shadow file item by item and save
        while($text =~/$pat/smg)
        {
            my @items = ();
            push @items, $1; # username
            push @items, $2; # password hash
            push @items, $4; # last update
            push @items, $5; # flags
            push @local, \@items;

            # whether an update is needed.
            if(exists($mapping{$items[0]}) && $mapping{$items[0]} ne $items[1])
            {
                TRACE_OUT("Add $items[0] into update list.");
                $items[1] = $mapping{$items[0]};
                $update = 1;
            }
        }
    }
    else  # for linux, hpux, solaris
    {
        # read current shadow file
        $shadow_file = '/etc/shadow';
        TRACE_OUT("Read shadow file $shadow_file");
        my $text = ReadFile($shadow_file);
        if (! $text)
        {
            ERROR_OUT("Cannot read shadow file $shadow_file");
            return 0;
        }

        # parse the shadow file item by item and save
        my @content = split(/\n/, $text);
        foreach my $line(@content)
        {
            $line .= "\n";
            my @items = split(/:/, $line);
            push @local, \@items;

            # whether an update is needed.
            if(exists($mapping{$items[0]}) && $mapping{$items[0]} ne $items[1])
            {
                TRACE_OUT("Add $items[0] into update list.");
                $items[1] = $mapping{$items[0]};
                $update = 1;
            }
        }
    }

    if ($update == 1)
    {
        DEBUG_OUT("Need to update shadow file");
    }
    else
    {
        DEBUG_OUT("No need to update shadow file");
    }

    return $update;
}

#
# Get all mapped users, and fetch their associative AD users.
# And then create a mapping list, using mapped users as key and AD users'
# password as value
#
#   Return: 1   - success
#           0   - no mapped users need to sync passwd
#
sub GetMappingList()
{
    # a list of sync mapped users.
    my $syncuser = $CentrifyDC::Config::properties{'pam.sync.mapuser'};
    if (! defined $syncuser or $syncuser eq '' or $syncuser eq "!*")
    {
        DEBUG_OUT("No user need to sync password.");
        return 0;
    }

    # fetch associative AD users and their passwords
    my @tmp= split(/\s+/, $syncuser);
    foreach my $u(@tmp)
    {
        TRACE_OUT("Check sync passwd user [$u]");
        # pam.mapuser.<local name>: <AD name>
        my $name = $CentrifyDC::Config::properties{"pam.mapuser.$u"};
        if(!defined($name))
        {
            TRACE_OUT("No user mapping for [$u]. Skip");
            next;
        }

        TRACE_OUT("Add mapped user [$name]");

        $name =~ s/\$HOSTNAME/$HOSTNAME/g;
        $name =~ s/\$ZONE/$ZONE/g;

        my $password = GetADPassword($name);
        if(defined($password))
        {
            $mapping{$u} = $password;
        }
    }

    if ((keys %mapping) > 0)
    {
        return 1;
    }
    else
    {
        TRACE_OUT("No user need to sync passwd");
        return 0;
    }
}

#
# Parse out the zone name that the machine joined into.
#
#   Return: string  - the zone name
#           undef   - failed to get the zone name
#
sub ParseOutZoneName()
{
    my $rc;
    my $zoneStr;

    ($rc, $zoneStr) = RunCommand("/usr/bin/adinfo -z")
        or (ERROR_OUT("adinfo failed. $zoneStr.") and return undef);
    chomp($zoneStr);

    my @tmp = split(/\//, $zoneStr);
    $zoneStr = $tmp[$#tmp];

    return $zoneStr;
}

#
# Get all necessary system's information
#
sub GetSystemInfo()
{
    my $hostname_cmd;

    if( -f "/bin/hostname" && -x "/bin/hostname" )
    {
        $hostname_cmd = "/bin/hostname";
    }
    elsif( -f "/usr/bin/hostname" && -x "/usr/bin/hostname" )
    {
        $hostname_cmd = "/usr/bin/hostname";
    }
    else
    {
        FATAL_OUT("Failed to resolve hostname: hostname not found");
    }

    chomp($HOSTNAME=`$hostname_cmd`);

    $ZONE = ParseOutZoneName();

    # generate a timestamp to be the suffix of shadow backups
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime();
    $year += 1900;
    $mon += 1;
    my $str = sprintf("%04d%02d%02d.%02d%02d%02d", $year, $mon, $mday, $hour, $min, $sec);

    $appdix = "syncpass.$str.$$.bak";  
}

#
# Get AD User's password via centrify's adquery
#
#   $_[0]:  - An ADUser' full name
#
#   Return: string  - Password hash for the ADUser
#           undef   - Failed to find the password hash
#
sub GetADPassword($)
{
    my $adname = shift;
    my ($rc, $pass) = RunCommand("/usr/bin/adquery user -H '$adname'");
    if($rc ne '0')
    {
        ERROR_OUT("adquery user -H '$adname' failed!");
        return undef;
    }
    chomp($pass);

    # Invalid hashes: x, !, !!, *, and so on
    # Valid hash must be greater than 4 characters.
    if(length($pass) > 4)
    {
        return $pass;
    }

    return undef;
}

#
# Check if current platform is supported
#
#   ret:    1       - supportded
#           undef   - not supported
#
sub CheckPlatform()
{
    my $uname_cmd;

    if( -f "/bin/uname" && -x "/bin/uname" )
    {
        $uname_cmd="/bin/uname";
    }
    elsif( -f "/usr/bin/uname" && -x "/usr/bin/uname" )
    {
        $uname_cmd="/usr/bin/uname";
    }
    else
    {
        FATAL_OUT("Failed to get ostype: uname not found");
    }
    
    chomp($ostype=`$uname_cmd`);
    $ostype = lc($ostype);

    foreach (@supported_platforms)
    {
        ($ostype eq $_) and return 1;
    }

    DEBUG_OUT("Current platform not supported.");
    return undef;
}

#
# Check if all required UNIX commands exists and are executable
#
#   ret:    1       - successful
#           undef   - failed
#
sub CheckCommands()
{
    my $pwck_cmd;

    if($ostype eq 'sunos' || $ostype eq 'solaris' || $ostype eq 'hp-ux')
    {
        $pwck_cmd = "/usr/sbin/pwck";
        $pwck = $pwck_cmd;
    }
    elsif($ostype eq 'linux')
    {
        $pwck_cmd = "/usr/sbin/pwck";
        $pwck = "$pwck_cmd -r";
    }
    elsif($ostype eq 'aix')
    {
        $pwck_cmd = "/usr/bin/pwck";
        $pwck = $pwck_cmd;
    }

    if (! -e $pwck_cmd or ! -x $pwck_cmd)
    {
        ERROR_OUT("Cannot find pwck command");
        return undef;
    }

    if($ostype ne 'aix')
    {
        $pwconv_cmd = '/usr/sbin/pwconv';
        $yes_cmd = '/usr/bin/yes';

        if (! -e $pwconv_cmd or ! -x $pwconv_cmd)
        {
            ERROR_OUT("Cannot find pwconv command");
            return undef;
        }
        if (! -e $yes_cmd or ! -x $yes_cmd)
        {
            ERROR_OUT("Cannot find yes command");
            return undef;
        }
    }

    return 1;
}



# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

my $args = CentrifyDC::GP::Args->new('machine');

if($args->isMap())
{
    CheckPlatform() or exit(0);

    CheckCommands() or FATAL_OUT("Required UNIX command not found. Quit.");

    GetSystemInfo();

    # quit silently if no user need to sync password.
    GetMappingList() or exit(0);

    # quit silently if current platform is not supported
    ConvertToShadow() or exit(0);

    my $rc = ReadLocalShadow();
    if(!$rc)
    {
        FATAL_OUT('Unable to read shadow file.');
    }
    elsif($rc == 1)
    {
        UpdateLocalShadow() or FATAL_OUT('Failed to update shadow file.');
    }
}

