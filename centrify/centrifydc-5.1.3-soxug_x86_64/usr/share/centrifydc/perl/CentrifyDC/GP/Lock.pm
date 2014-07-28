##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl mapper script lock module.
#
# This module create a lock file based on a given file name and lock it.
# If lock can not be created, the constructor will return undef.
#
# On destruction, the lock file will be released and deleted.
#
# There are two ways to create a lock:
#
#   1. specify the file that need to be lock protected. constructor will
#      generate a lock file name based on the given file.
#   2. specify the lock file name directly.
#
# To create a new Lock for file /etc/authorization:
#
#   my $lock = CentrifyDC::GP::Lock->new('/etc/authorization');
#
# To create a new Lock with specified lock file /tmp/authorization.lck:
#
#   my $lock = CentrifyDC::GP::Lock->new('/tmp/authorization.lck', 1);
#
# To get lock file name:
#
#   $lock->lockfile();
#
##############################################################################

use strict;

package CentrifyDC::GP::Lock;
use CentrifyDC::Logger;

my $VERSION = '1.0';
require 5.000;

use Symbol qw(gensym);
use Fcntl qw(LOCK_EX LOCK_NB LOCK_UN O_RDWR O_CREAT O_EXCL S_ISREG);
use File::stat qw(lstat);

sub new($$;$);
sub file($);
sub DESTROY($);



#
# set up syslog and debug
#
my $logger = CentrifyDC::Logger->new('com.centrify.gp.Lock');
my $DEBUG = $logger->level();


#
# create instance
#
#   $_[0]:  self
#   $_[1]:  file name
#   $_[2]:  file name is lock file name (optional)
#
#   return: self    - successful
#           undef   - failed
#
sub new($$;$)
{
    my ($invocant, $source_file, $is_lockfile) = @_;
    my $class = ref($invocant) || $invocant;

    defined($source_file) or return undef;

    my $file = $source_file;

    if (! $is_lockfile)
    {
        # filename can not contain invalid characters, space, and ~
        $file =~ s%[ ~/\\\[\]:;\|=,\+\*\?<>"]%%mg;
        ($file ne '') or return undef;

        # limit the length of filename
        (length($file) > 200) and $file = substr($file, 0, 200);
        
        # assume lock file will require write permission from current user only
        my $temp_dir = CentrifyDC::GP::General::GetTempDirPath(0);
        defined($temp_dir) or return undef;
        
        $file = $temp_dir . '/' . $file . '.lock';
    }

    my $fh = gensym;

    # NOTE: Setting O_CREAT|O_EXCL prevents the file from being opened if 
    # it is a symbolic link. It does not protect against symbolic links in 
    # the file's path. 
    #
    # NOTE: It is warned that in some UNIX systems, sysopen will fail when 
    # file descriptors exceed a certain value (typically 255) due to the 
    # use of fdopen() C library function.
    #
    # We will use a permission of 0600 because:
    # - We create lock file for self use only.
    #
    if (! -e $file)
    {
        my $rc = sysopen($fh, $file, O_RDWR|O_CREAT|O_EXCL, 0600);
        if(! $rc)
        {
            $logger->log('info', ">>> Cannot create lock file [$file]: $!");
            return undef;
        }
    }
    else
    {
        #
        # check permission, ownership, etc. to ensure the file is ours
        #
        # use lstat to ensure symlink is checked instead of the target file 
        # behind the link
        #
        my $sb = lstat($file);
        if (!defined $sb)
        {
            $logger->log('info', ">>> Lock file already exists but cannot get file information [$file]");
            return undef;
        }

        my $uid = $>;   # effective uid
        my $gid = $);   # effective gid
        
        if ($sb->uid != $uid ||
            $sb->gid != $gid ||
            ($sb->mode & 0777) != 0600 ||
            $sb->size > 0 ||
            !S_ISREG($sb->mode))
        {
            $logger->log('info', ">>> Lock file already exists but not ours [$file]");
            return undef;
        }

        #
        # open file only if it is ours, because we will delete the file when 
        # this lock object is destructed.
        #
        # we add the open file logic here to handle cases in which previous 
        # lock file is not cleared after use (e.g. adclient crashes during GP 
        # update).
        #
        my $rc = sysopen($fh, $file, O_RDWR, 0600);
        if(! $rc)
        {
            $logger->log('info', ">>> Cannot open lock file [$file]: $!");
            return undef;
        }
    }

    # request an exlcusive lock in a non-blocking manner
    my $rc = flock($fh, LOCK_EX|LOCK_NB);
    if (! $rc)
    {
        $logger->log('info', ">>> Failed to request an exclusive lock on file [$file]: $!");
        return undef;
    }

    my $self = {
        file    => $file,
        fh      => $fh,
    };

    bless($self, $class);

    return $self;
}

#
# get lock file name
#
#   $_[0]:  self
#
#   return: string  - lock file name
#
sub file($)
{
    return $_[0]->{file};
}

#
# destructor. release lock, close lock file and delete it
#
#   $_[0]:  self
#
sub DESTROY($)
{
    my $self = $_[0];

    flock($self->{fh}, LOCK_UN);
    close($self->{fh});
    unlink($self->{file});
}

1;
