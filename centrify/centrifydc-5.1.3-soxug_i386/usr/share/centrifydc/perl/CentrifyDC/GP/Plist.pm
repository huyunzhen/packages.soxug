##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify mapper script plist module for Mac OS X.
#
# This module can read plist file, manipulate values and write it back.
#
#
# The standard procedure to use this module is:
#
#   1. create a new instance;
#   2. load plist file or a hash;
#   3. get setting using get;
#   4. set setting using set;
#   5. save modified plist file.
#
#
# To create a new Plist:
#
#   my $plist = CentrifyDC::GP::Plist->new(
#               '/Library/Preferences/.GlobalPreferences.plist'),
#
# To load data from plist file:
#
#   $plist->load();
#
# To load data from a hash:
#
#   $plist->loadHash($hash_reference);
#
# To get Core Foundation object of specified key:
#
#   $plist->get($keys_array_reference);
#
# To get plist filename:
#
#   $plist->filename();
#
# To get all keys under specified keys:
#
#   $plist->getKeys($keys_array_reference);
#
# To set setting:
#
#   $plist->set($keys_array_reference, $key, $data);
#
# To save plist file:
#
#   $plist->save();
#
# To compare if contents of two plists are equal:
#
#   $plist->isEqual($otherplist);
#
##############################################################################

use strict;

package CentrifyDC::GP::Plist;
my $VERSION = '1.0';
require 5.000;

use File::Basename qw(dirname);
use File::Path qw(mkpath);

use Scalar::Util 'blessed';

use Foundation;

use CentrifyDC::GP::Lock;
use CentrifyDC::GP::Mac qw(:objc);
use CentrifyDC::GP::General qw(:debug RunCommand GetTempDirPath);

my $DEFAULTS  = '/usr/bin/defaults';
my $TEST_KEY  = '_CDC_GP_FIND_PLIST_';
my $TEST_DATA = 'TEST';

sub new($$;$$);
sub load($);
sub loadHash($$);
sub save($);
sub get($$;$);
sub filename($);
sub getKeys($$);
sub set($$$$;$);
sub isEqual($$);
sub _trace($);
sub _GetPlistFilePath($;$$);
sub _GetByHostFileNameUsingDefaults($$$);



#
# create instance
#
#   $_[0]:  self
#   $_[1]:  plist file
#
#   return: self    - successful
#           undef   - failed
#
sub new($$;$$)
{
    my ($invocant, $plist_file, $user, $byhost) = @_;
    my $class = ref($invocant) || $invocant;

    if (! defined($plist_file))
    {
        ERROR_OUT("Cannot create Plist instance: plist file undefined");
        return undef;
    }

    my $file = _GetPlistFilePath($plist_file, $user, $byhost);
    if (! defined($file))
    {
        ERROR_OUT("Cannot create Plist instance: cannot get full path of [$plist_file]");
        return undef;
    }

    my $self = {
        original_file => $plist_file,
        file    => $file,
        plist   => undef,
        user    => $user,
        byhost  => $byhost,
    };

    bless($self, $class);

    return $self;
}

#
# load plist file into plist.
#
# if file does not exist, create and empty NSMutableDictionary for plist;
# if load failed (Cocoa error or file is not a valid plist file), return undef.
#
#   $_[0]:  self
#
#   return: 1       - successful
#           2       - file not exist. create an empty plist.
#           undef   - failed
#
sub load($)
{
    my $self = $_[0];

    my $file = $self->{file};

    TRACE_OUT("load [$file]");

    my $plist;

    # if file not exist, create an empty NSMutableDictionary.
    if (! -e $file)
    {
        DEBUG_OUT("Load [$file]: file not exist. Create empty plist.");
        $plist = NSMutableDictionary->dictionary();
        $self->{plist} = $plist;
        return 2;
    }
    if (! -r $file)
    {
        ERROR_OUT("Cannot load [$file]: file not readable");
        return undef;
    }

    eval
    {
        $plist = NSMutableDictionary->dictionaryWithContentsOfFile_($file);
    };
    if ($@)
    {
        ERROR_OUT("Cannot load [$file]: $@");
        return undef;
    }

    if (! $plist)
    {
        ERROR_OUT("Cannot load [$file]: a Cocar error occured");
        return undef;
    }
    elsif(! $$plist)
    {
        ERROR_OUT("Cannot load [$file]: not a valid plist file");
        return undef;
    }

    $self->{plist} = $plist;

    return 1;
}

#
# load hash reference into plist
#
#   $_[0]:  self
#   $_[1]:  hash reference
#
sub loadHash($$)
{
    my ($self, $hash) = @_;

    $self->{plist} = ToCF($hash);
}

#
# save plist into plist file
#
# need to use lockfile to prevent race condition, and save and restore file
# attribute if file exists
#
#   $_[0]:  self
#
#   return: 1       - successful
#           undef   - failed
#
sub save($)
{
    my $self = $_[0];

    my $file = $self->{file};

    DEBUG_OUT("Save [$file]");

    my $ret = 1;

    # use defaults to create a plist file if not exist
    if (! -e $file)
    {
        my $command;
        my $user = $self->{user};
        my $original_file = $self->{original_file};
        my $lockfile = "$original_file.lock";
        $lockfile =~ s|/|.|g;

        my $tempdir = GetTempDirPath(0);
        defined($tempdir) or return undef;
        $lockfile = "$tempdir/$lockfile";

        if (defined($user))
        {
            if ($self->{byhost})
            {
                $command = "su - $user -c \"$DEFAULTS -currentHost write '$original_file' '$TEST_KEY' '$TEST_DATA'\"";
            }
            else
            {
                $command = "su - $user -c \"$DEFAULTS write '$original_file' '$TEST_KEY' '$TEST_DATA'\"";
            }
        }
        else
        {
            my $original_domain = $original_file;
            $original_domain =~ s/\.plist$//;
            $command = "$DEFAULTS write '$original_domain' '$TEST_KEY' '$TEST_DATA'";
        }
        my $rc = RunCommand($command, $lockfile);
        if (! defined($rc) or $rc ne'0')
        {
            ERROR_OUT("Cannot write test key into plist [$file]");
            return undef;
        }
    }

    if (! -e $file)
    {
        ERROR_OUT("Cannot create $file");
        return undef;
    }

    # save file attribute
    my ($mode, $uid, $gid) = (stat $file)[2, 4, 5];
    $mode = $mode & 07777;

    # create lockfile
    my $lock = CentrifyDC::GP::Lock->new('plist.' . $file);
    if (! defined($lock))
    {
        ERROR_OUT("Cannot obtain lock");
        return undef;
    }
    TRACE_OUT(" lockfile: [" . $lock->file() . "]");

    # write plist file
    eval
    {
        $ret = $self->{plist}->writeToFile_atomically_($file, NSNumber->numberWithBool_(1));
    };
    if ($@)
    {
        ERROR_OUT("Cannot save [$file]: $@");
        $ret = undef;
    }
    else
    {
        # restore file attribute
        chmod $mode, $file;
        chown $uid, $gid, $file;
    }

    return $ret;
}

#
# get object from plist based on a give key array
# if type is specified, it will check if type matches. return undef if type
# mismatch
#
#    to get "data" in the following dictionary:
#    {
#        key1 = {
#            key2 = {
#                key3 = "data"; 
#            }; 
#        }; 
#    }
#
#    the key array reference should be:
#    [
#            key1,
#            key2,
#            key3,
#    ];
#
#   $_[0]:  self
#   $_[1]:  keys array reference. all array elements should be string
#           if undef, return the original object
#   $_[2]:  type
#
#   return: Core Foundation object - successful
#           undef                  - failed or no such object
#
sub get($$;$)
{
    my ($self, $r_keys, $type) = @_;

    my $object = GetObjectFromNSDictionary($self->{plist}, $r_keys);

    # if type is specified, check if the object is the specified type
    IsCF($object, $type) ? (return $object) : (return undef);
}

#
# get plist filename
#
#   $_[0]:  self
#
#   return: string  - plist filename
#
sub filename($)
{
    my $self = $_[0];

    return $self->{file};
}

#
# get keys from plist based on a give key array
#
#    to get all keys under key2 (key3, key4) in the following dictionary:
#    {
#        key1 = {
#            key2 = {
#                key3 = "data1"; 
#                key4 = "data2"; 
#            }; 
#        }; 
#    }
#
#    the key array reference should be:
#    [
#            key1,
#            key2,
#    ];
#
#   $_[0]:  self
#   $_[1]:  keys array reference. all array elements should be string
#           can be empty or undef
#
#   return: array reference - successful
#           undef           - failed
#
sub getKeys($$)
{
    my ($self, $r_keys) = @_;

    return GetKeysFromNSDictionary($self->{plist}, $r_keys);
}

#
# update plist based on a given key array and a key/data pair.
#
# the data can be a Core Foundation object or a perl string. if type is not
# specified, perl string will be converted to NSString; if type is specified,
# perl string will be converted to the corresponding data type.
#
# the key array includes all parent keys of the key that need to be updated
#    to update "data" in the following dictionary:
#    {
#        key1 = {
#            key2 = {
#                key3 = "data"; 
#            }; 
#        }; 
#    }
#
#    the key array reference should be:
#    [
#            key1,
#            key2,
#    ];
#
#   $_[0]:  self
#   $_[1]:  keys array reference. all array elements should be string
#   $_[2]:  key
#   $_[3]:  data
#   $_[4]:  type (optional)
#
#   return: 1       - successful
#           undef   - failed
#
sub set($$$$;$)
{
    my ($self, $r_keys, $key, $data, $type) = @_;

    my $ret = UpdateNSMutableDictionary($self->{plist}, $r_keys, $key, ToCF($data, $type));

    $ret or ERROR_OUT("Cannot update NSMutableDictionary of plist [$self->{file}]");

    return $ret;
}

#
# check if contents of two plists are equal
#
#   $_[0]:  self
#   $_[1]:  the plist to compare
#
#   return: 1       - equal
#           0       - not equal
#           undef   - cannot compare (different type)
#
sub isEqual($$)
{
    my ($self, $otherplist) = @_;

    if (blessed($otherplist) && $otherplist->isa('CentrifyDC::GP::Plist'))
    {
        if (ToString($self->{plist}) eq ToString($otherplist->get(undef)))
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
        return undef;
    }
}



# >>> PRIVATE >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# create log entry for content of plist
#
#   $_[0]:  self
#
sub _trace($)
{
    my $self = $_[0];

    IsTraceOn() and TRACE_OUT(ToString($self->{plist}));
}

#
# get full path of a given plist file
#
#   $_[0]:  absolute path or domain
#           absolute path: /Library/Preferences/com.apple.screensaver.plist
#           domain:        com.apple.screensaver (no .plist suffix)
#   $_[1]:  username (domain only. ~ for current user) 
#   $_[2]:  ByHost (domain only. 1 for ByHost)
#
#   ret:    string  - full path
#           undef   - failed
#
sub _GetPlistFilePath($;$$)
{
    my ($file, $user, $byhost) = @_;

    defined($file) or return undef;

    # if file is absolute path, return it
    ($file =~ m|^/|) and return $file;

    TRACE_OUT("get full path of plist [$file]");

    # get user's home dir
    my $dir;
    if (defined($user))
    {
        $dir =(getpwnam($user))[7];
    }
    else
    {
        $dir = $ENV{HOME} || $ENV{LOGDIR} || (getpwuid($>))[7];
    }
    if (! defined($dir))
    {
        ERROR_OUT("Cannot get full path of plist [$file]: cannot get home directory of user [$user]");
        return undef;
    }

    my $file_path = $dir . "/Library/Preferences/";

    # file is not byhost setting
    if (! $byhost)
    {
        $file_path .= $file . '.plist';
        TRACE_OUT("full path of plist [$file]: [$file_path]");
        return $file_path;
    }

    #
    # file is byhost setting
    # if defaults command can get setting from specified file and there's
    # only one file in ByHost folder, then this file is the correct one;
    # else need to use defaults command to write the file and figure out
    # which one is in use.
    #
    $file_path .= "ByHost/";
    my $do_write_test = 0;
    my $correct_file;

    DEBUG_OUT("Try to find correct ByHost plist [$file]");
    my $rc = RunCommand("su - $user -c \"$DEFAULTS -currentHost read '$file'\"");
    if (! defined($rc) or $rc ne'0')
    {
        $do_write_test = 1;
    }
    else
    {
        # count number of possible plist files
        opendir(DIR, $file_path);
        my @files = readdir(DIR);
        closedir(DIR);

        my @candidates = ();
        foreach my $candidate (@files)
        {
            # format: com.apple.screensaver.XXXXXX.plist
            if ($candidate =~ m/^$file\.[^\.]+\.plist$/)
            {
                push(@candidates, $candidate);
            }
        }
        if (scalar @candidates == 1)
        {
            $correct_file = pop(@candidates);
        }
        elsif (scalar @candidates > 1)
        {
            $do_write_test = 1;
        }
        else
        {
            ERROR_OUT("No plist file found");
            return undef;
        }
    }

    if ($do_write_test)
    {
        $correct_file = _GetByHostFileNameUsingDefaults($file, $user, $file_path);
    }

    if (defined($correct_file))
    {
        $file_path .= $correct_file;
        TRACE_OUT("full path of ByHost plist [$file]: [$file_path]");
        return $file_path;
    }
    else
    {
        ERROR_OUT("Cannot find ByHost plist file [$file]");
        return undef;
    }
}

#
# use defaults command to get basename of byhost plist file
#
#   $_[0]:  domain
#   $_[1]:  username
#   $_[2]:  ByHost directory path
#
#   ret:    string  - basename of byhost plist file
#           undef   - failed
#
sub _GetByHostFileNameUsingDefaults($$$)
{
    my ($file, $user, $byhost_dir) = @_;

    defined($file) or return undef;

    my $tempdir = GetTempDirPath(0);
    defined($tempdir) or return undef;

    my $correct_file;
    my $rc;

    # first write a test key into plist
    DEBUG_OUT("Write test key into ByHost plist [$file]");
    $rc = RunCommand("su - $user -c \"$DEFAULTS -currentHost write '$file' '$TEST_KEY' '$TEST_DATA'\"", "$tempdir/$file.lock");
    if (! defined($rc) or $rc ne'0')
    {
        ERROR_OUT("Cannot write test key into ByHost plist [$file]");
        return undef;
    }

    # check number of possible files. if 1, then it's the correct file
    opendir(DIR, $byhost_dir);
    my @files = readdir(DIR);
    closedir(DIR);

    my @candidates = ();
    foreach my $candidate (@files)
    {
        if ($candidate =~ m/^$file\.[^\.]+\.plist$/)
        {
            push(@candidates, $candidate);
        }
    }

    if (scalar @candidates == 1)
    {
        $correct_file = pop(@candidates);
        TRACE_OUT("ByHost plist file: [$correct_file]");
        $rc = RunCommand("su - $user -c \"$DEFAULTS -currentHost delete '$file' '$TEST_KEY'\"", "$tempdir/$file.lock");
        if (! defined($rc) or $rc ne'0')
        {
            WARN_OUT("Cannot remove test key from ByHost plist [$file]");
        }
        return $correct_file;
    }
    elsif (scalar @candidates == 0)
    {
        ERROR_OUT("Cannot find correct ByHost plist [$file]");
        return undef;
    }

    #
    # more than 1 possible file found. remove test key and compare file size.
    # if file size changed, then it's the correct file.
    #
    my %file_size_old = ();
    foreach my $candidate (@candidates)
    {
        $file_size_old{$candidate} = (stat($byhost_dir . $candidate))[7];
    }
    DEBUG_OUT("Remove test key from ByHost plist [$file]");
    $rc = RunCommand("su - $user -c \"$DEFAULTS -currentHost delete '$file' '$TEST_KEY'\"", "$tempdir/$file.lock");
    if (! defined($rc) or $rc ne'0')
    {
        ERROR_OUT("Cannot remove test key from ByHost plist [$file]");
        return undef;
    }
    foreach my $candidate (@candidates)
    {
        my $candidate_fullpath = $byhost_dir . $candidate;
        if (! -e $candidate_fullpath or $file_size_old{$candidate} ne (stat($candidate_fullpath))[7])
        {
            $correct_file = $candidate;
            TRACE_OUT("ByHost plist file: [$correct_file]");
            return $correct_file;
        }
    }

    ERROR_OUT("Cannot find correct ByHost plist [$file]");
    return undef;
}

# <<< PRIVATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

1;
