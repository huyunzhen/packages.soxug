#!/bin/sh /usr/share/centrifydc/perl/run

##############################################################################
#
# Copyright (C) 2008-2014 Centrify Corporation. All rights reserved.
#
# Machine mapper script to copy file from Active Directory to UNIX system.
# Also works as user mapper script, despite that there's no user policy yet.
#
#   The script copies files from the following locations to any place on
#   UNIX file system with specified filename/ownership/permission:
#    1. SYSVOL of joined domain or trusted domain
#    2. share folder of any Windows machine in joined domain or trusted domain
#
#   The script will not remove or revert copied file.
#
#
#   Copy procedure:
#    1. prepare target directory. if not exist, create
#    2. if target file exists, save file ownership/permission
#    3. use smb to copy file
#    4. set file ownership/permission
#
#
#   Each file has a registry key under:
#       software/policies/centrify/unixsettings/filecopyv2
#
#
#   Registry values:
#
#       source.fqdn         source domain/server name
#                           If file is in SYSVOL, then this value should be
#                           domain name; if file is in a share folder, then
#                           this value should be server name. The script use
#                           [source] to identify its type.
#
#       source              source file name
#                           If starts with /, script will assume it contains
#                           share folder name (/share/dir1/dir2/.../dirn/file)
#                           and treat [source.fqdn] as server name;
#                           If not start with /, script will assume it's
#                           relative path to SYSVOL (dir1/dir2/.../dirn/file)
#                           and treat [source.fqdn] as domain name.
#
#       binary.copied       0/1
#                           1: use binary copy
#                           0: do not use binary copy
#
#       destination         where to copy file. must start with /.
#                           This value can be either directory or file name.
#                           If it ends with /, script will treat it as dir;
#                           if it does not end with /, then script behaves
#                           like UNIX cp command, except that it will create
#                           necessary directory structure.
#                           Example: /dir1/dir2/.../dirn/fileordir
#                            If fileordir does not exist, then treat it as a
#                            file and create /dir1/dir2/.../dirn with default
#                            ownership/permission if necessary;
#                            if fileordir is a file/dir, then copy source file
#                            to this file;
#                            if fileordir is a directory, then copy source file
#                            into this directory.
#                           
#                           directory: file will be copied into this directory
#                           file:      file will be copied as this file
#                           
#
#       use.existing.perms  0/1
#                           1: use target file's uid/gid/perm
#                           0: use specified uid/gid/perm
#
#       use.selected.perms  file's perm, for example 0700
#
#       owner.gid           file's owner gid
#
#       owner.uid           file's owner uid
#
#
#  Map:     copy file based on registry setting
#              Enable:          copy file
#              Disable:         do nothing
#              Not Configured:  do nothing
#
#  Unmap:   do nothing
#
#
# Parameters: <map|unmap> mode
#   map|unmap   action to take
#   mode        not used
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
use CentrifyDC::GP::General qw(:debug IsEmpty RunCommand);
use CentrifyDC::GP::Lock;
use CentrifyDC::GP::Registry;
use CentrifyDC::GP::RegHelper;
use CentrifyDC::SMB;
use File::Path;
use File::Basename;

my $REGKEY_ENABLE = 'software/policies/centrify/unixsettings';
my $REGVAL_ENABLE = 'filecopyv2.enabled';
my $REGKEY_ROOT = 'software/policies/centrify/unixsettings/filecopyv2';
my $BAKFILE_EXT = '.cdc.original';
my $TMPFILE_EXT = '.cdc.copy.tmp';
my $DEFAULT_MODE = '0644';

my @REGKEYS = ();

# hash reference of files to be copied
# => {
#   '0' => an_RegHelper,
#   '1' => an_RegHelper,
#   ...
my %reg_files = ();

my $args;

sub ExpandEnv($);
sub PrepareDest($);
sub CopyFile($);
sub CopyAllFiles();
sub GetFileSetting($);
sub GetSetting($);

sub Map();
sub UnMap();



# >>> SUB >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# expand environment variables in path
# environment variable is the longest alphanumeric (including _) that starts
# with $
#
#   $_[0]:  path
#
#   return: string  - successful
#           undef   - failed
#
sub ExpandEnv($)
{
    my $path = $_[0];

    defined($path) or return undef;

    $path =~ s/\$(\w+)/$ENV{$1}/g;

    return $path;
}

#
# prepare destination. create parent directory if not exist.
#
#   $_[0]:  destination
#
#   return: 1       - successful
#           undef   - failed
#
sub PrepareDest($)
{
    my $dest = $_[0];

    defined($dest) or return undef;

    # create parent directory
    my $dir = dirname($dest);
    if (! -d "$dir")
    {
        DEBUG_OUT("Create $dir");
        eval
        {
            mkpath($dir, 0, 0755);
        };
        if ($@)
        {
            ERROR_OUT("Cannot create $dir: $@");
            return undef;
        }
    }

    return 1;
}

#
# get file copy setting of one file from registry and local file, then
# generate a hash of settings
#
#   $_[0]:  hash reference of registry setting
#
#   return: hash reference  - file copy setting
#                           share:        share folder
#                           src:          full path of source file
#                           src.isdir:    1 for dir, else file
#                           dest:         full path of destination
#                           source.fqdn:  source domain/server name
#                           uid:          uid
#                           gid:          gid
#                           perm:         mode
#                           binary:       use binary copy
#                           isdomain:     source.fqdn is server or domain
#                                         1 for domain, else server
#
#           undef           - failed
#
sub GetFileSetting($)
{
    my $regdata = $_[0];

    my $setting = {};

    $setting->{'source.fqdn'} = $regdata->{'source.fqdn'};
    $setting->{binary} = $regdata->{'binary.copied'};

    #
    # parse source file path
    #
    my $src = $regdata->{source};
    if (! defined($src))
    {
        ERROR_OUT("source file path not specified");
        return undef;
    }
    if ($src =~ m#^/#)
    {
        # source starts with /, treat the format as /share/dir1/dir2/...
        if ($src =~ m#^/([^/]+)(/.+)#)
        {
            $setting->{share} = "$1";
            $setting->{src} = "$2";
        }
        else
        {
            ERROR_OUT("Cannot parse source file path: $src");
            return undef;
        }
        
    }
    else
    {
        # source does not start with /, consider it relative path to SYSVOL
        $setting->{isdomain} = 1;
        $setting->{share} = 'SYSVOL';
        $setting->{src} = $src;
    }

    if ($src =~ m#/$#)
    {
        $setting->{'src.isdir'} = 1;
        $src =~ s#/$##;
    }

    #
    # parse destination, if destination is a dir, append source file name
    #
    my $dest = ExpandEnv($regdata->{destination});
    if (! defined($dest))
    {
        ERROR_OUT("destination not specified");
        return undef;
    }
    if ($dest !~ m#^/#)
    {
        ERROR_OUT("destination must start with /: $dest");
        return undef;
    }
    if ($dest =~ m#/$#)
    {
        # destination ends with /
        $setting->{dest} = $dest . basename($src);
    }
    else
    {
        
        if (-d "$dest")
        {
            # destination is a dir
            $setting->{dest} = $dest . "/" . basename($src);
        }
        else
        {
            # destination is a file
            $setting->{dest} = $dest;
        }
    }

    #
    # get file ownership/permission
    #
    if ($regdata->{'use.existing.perms'})
    {
        if (-f $setting->{dest})
        {
            # if file exists, get its stat
            my ($mode, $uid, $gid) = (stat $setting->{dest})[2, 4, 5];
            $mode = $mode & 07777;
            $setting->{perm} = $mode;
            $setting->{uid} = $uid;
            $setting->{gid} = $gid;
        }
        else
        {
            $setting->{perm} = oct($DEFAULT_MODE);
        }
    }
    else
    {
        $setting->{perm} = oct($regdata->{'use.selected.perms'});
        $setting->{uid}  = $regdata->{'owner.uid'};;
        $setting->{gid}  = $regdata->{'owner.gid'};;
    }

    return $setting;
}

#
# get current registry settings for copyfile gp
#
#   $_[0]:  action  (map/unmap)
#
#   return: 1       - successful
#           undef   - failed
#
sub GetSetting($)
{
    my $action = $_[0];

    my $copyfile_enabled = (CentrifyDC::GP::Registry::Query('machine', $REGKEY_ENABLE, 'current', $REGVAL_ENABLE))[1];

    $copyfile_enabled or return 1;

    #
    # each file has a corresponding registry key, so need to get all keys
    # under REGKEY_ROOT.
    #
    @REGKEYS = CentrifyDC::GP::Registry::GetSubKeys($REGKEY_ROOT, 'current', $args->user());

    foreach my $key (@REGKEYS)
    {
        defined($key) or next;
        $reg_files{$key} = CentrifyDC::GP::RegHelper->new($action, $args->class(), $key, undef, undef);
        $reg_files{$key} or return undef;
        $reg_files{$key}->load('current');
        # ignore empty key
        if (! defined($reg_files{$key}->get('current')))
        {
            TRACE_OUT("ignore empty copyfile key: $key");
            delete $reg_files{$key};
        }
        else
        {
            TRACE_OUT("add copyfile key: $key");
        }
    }

    return 1;
}

#
# copy one file from AD
#
#   $_[0]:  hash reference of file copy setting
#                           share:        share folder
#                           src:          full path of source file
#                           dest:         full path of destination
#                           source.fqdn:  source domain/server name
#                           uid:          uid
#                           gid:          gid
#                           perm:         mode
#                           binary:       use binary copy
#                           isdomain:     source.fqdn is server or domain
#                                         0 for server, 1 for domain
#
#   return: 1       - successful
#           undef   - failed
#
sub CopyFile($)
{
    my $data = $_[0];

    defined($data) or return undef;

    my $rc = 0;
    DEBUG_OUT("Copy from " . ($data->{isdomain} ? "domain " : "server ")
              . $data->{'source.fqdn'}
              . ":  share: [" . $data->{share}
              . "]  file: [" . $data->{src}
              . "]  destination: [" . $data->{dest} . "]");
    my $src;
    if ($data->{isdomain})
    {
        # if copy from sysvol, source should be relative path to SYSVOL
        $src = $data->{src};
    }
    else
    {
        # if copy from share, source should be //server/share/dir/file
        $src = "//" . $data->{'source.fqdn'} . "/" . $data->{share} . $data->{src};
    }

    my $dest = $data->{dest};

    my $lock = CentrifyDC::GP::Lock->new($dest);
    if (! defined($lock))
    {
        ERROR_OUT("Cannot obtain lock for $dest. Skip");
        next;
    }

    # use smb to copy file from AD
    my $smb;
    if ($data->{isdomain})
    {
        $smb = CentrifyDC::SMB->new($data->{'source.fqdn'});
    }
    else
    {
        $smb = CentrifyDC::SMB->new();
    }

    if ($data->{binary})
    {
        $smb->convertCRLF(0);
    }
    else
    {
        $smb->convertCRLF(1);                
    }

    $smb->directory(1);
    $smb->removeDeleted(0);
    $smb->mode($data->{perm});

    if ($data->{'src.isdir'})
    {
        $smb->dirmode(0755);
        $smb->recurse(1);
    }
    else
    {
        $smb->recurse(0);
    }

    DEBUG_OUT("SMB copy from " . ($data->{isdomain} ? "domain " : "server ")
              . $data->{'source.fqdn'}
              . ":  src: [$src]  dest: [$dest]");
    eval
    {
        if ($data->{'src.isdir'})
        {
            $smb->GetModFiles($src, $dest);
        }
        else
        {
            $smb->GetMod($src, $dest);
        }
    };
    if ($@)
    {
        ERROR_OUT("Cannot copy file from AD: $@");
        return undef;
    }

    if (! $data->{'src.isdir'})
    {
        if (! -f $dest)
        {
            ERROR_OUT("Cannot copy file from AD");
            return undef;
        }
    }

    # set uid/gid
    if (defined($data->{uid}))
    {
        TRACE_OUT("chown $dest: " . $data->{uid} . ":" . $data->{gid});
        if ($data->{'src.isdir'})
        {
            $rc = RunCommand("chown -R " . $data->{uid} . ":" . $data->{gid} . " $dest");
            $rc = ($rc == 0) ? 1 : 0;
        }
        else
        {
            $rc = chown $data->{uid}, $data->{gid}, $dest;
        }
        if (! $rc)
        {
            ERROR_OUT("Cannot set uid/gid of $dest");
            return undef;
        }
    }

    # set file permission
    if (defined($data->{perm}))
    {
        TRACE_OUT("chmod $dest: " . $data->{perm});
        if ($data->{'src.isdir'})
        {
            # Tested on Windows DC GUI, we can not choose a directory as the copy
            # source (the copy source must be a single file).
            # But we already handled this scenario (choose directory as copy
            # source) in code.
            # We will not do anything here
            WARN_OUT("Cannot change the permission of directory $dest to [$data->{perm}]");
        }
        else
        {
            $rc = chmod $data->{perm}, $dest;
        }
        if (! $rc)
        {
            ERROR_OUT("Cannot set file permission of $dest to [$data->{perm}]");
            return undef;
        }
    }

    return 1;
}

#
# copy files from Active Directory
#
#   return: 1       - successful
#           undef   - failed
#
sub CopyAllFiles()
{
    my $ret = 1;
    my $rc = 0;

    foreach my $regkey (keys %reg_files)
    {
        my $data = GetFileSetting($reg_files{$regkey}->get('current'));
        if (! scalar keys %$data)
        {
            ERROR_OUT("Cannot process $regkey. Skip");
            next;
        }
        my $dest = $data->{dest};
        $rc = PrepareDest($dest);
        if (! $rc)
        {
            ERROR_OUT("A problem occurred when preparing destination $dest. Skip");
            next;
        }

        $rc = CopyFile($data);
        if (! $rc)
        {
            ERROR_OUT("Cannot copy file from AD");
            next;
        }
    }

    return $ret;
}

#
# map
#
#   return: 1       - successful
#           undef   - failed
#
sub Map()
{
    my $ret = 1;

    $ret = CopyAllFiles();

    return $ret;
}

#
# unmap (do nothing)
#
#   return: 1       - successful
#           undef   - failed
#
sub UnMap()
{
    my $ret = 1;

    return $ret;
}


# >>> MAIN >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

$args = CentrifyDC::GP::Args->new('machine');

CentrifyDC::GP::Registry::Load($args->user());

GetSetting($args->action()) or FATAL_OUT("Cannot get registry setting");

my $ret = 0;

$args->isMap() ? ($ret = Map()) : ($ret = UnMap());

$ret or FATAL_OUT();

