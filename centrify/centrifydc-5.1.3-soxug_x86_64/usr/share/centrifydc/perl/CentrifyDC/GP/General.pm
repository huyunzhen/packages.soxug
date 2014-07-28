##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl mapper script general purpose module.
#
##############################################################################

use strict;

package CentrifyDC::GP::General;
my $VERSION = '1.0';
require 5.000;

use vars qw(@ISA @EXPORT_OK %EXPORT_TAGS $GP_DEBUG $GP_TRACE $GP_LOG_PRINT_TO_STDOUT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(FATAL_OUT ERROR_OUT WARN_OUT INFO_OUT DEBUG_OUT TRACE_OUT IsDebugOn IsTraceOn
                RunCommand RunCommandWithTimeout ChangeOwner CreateDir ReadFile WriteFile GetFullPath GetTempDirPath CreateTempFile TraverseSymLink
                IsEqual IsEmpty  AddElementsIntoArray RemoveElementsFromArray DiffTwoArray);
%EXPORT_TAGS = (
    'debug'     => [qw(FATAL_OUT ERROR_OUT WARN_OUT INFO_OUT DEBUG_OUT TRACE_OUT IsDebugOn IsTraceOn)],
    'system'    => [qw(RunCommand RunCommandWithTimeout ChangeOwner CreateDir ReadFile WriteFile GetFullPath GetTempDirPath CreateTempFile TraverseSymLink)],
    'general'   => [qw(IsEqual IsEmpty AddElementsIntoArray RemoveElementsFromArray DiffTwoArray)]);

use POSIX qw(:sys_wait_h :signal_h);

use IPC::Open3;
use File::Spec;
use Symbol qw(gensym);

use Fcntl qw(LOCK_EX LOCK_NB LOCK_UN O_RDWR O_CREAT O_EXCL);
use File::Basename qw(basename dirname);
use File::Path qw(mkpath);
use File::Copy qw(move);
use File::stat qw(lstat);

use CentrifyDC::Logger;
use CentrifyDC::GP::Lock;

#
# other than the system wide log level in centrifydc.conf, we can also set
# log settings for all gp mappers or an individual mapper.
#
# to set gp mappers log level to DEBUG, and mac_mapper_network.pl to TRACE:
#
#   log: INFO
#   log.gp.mappers: DEBUG
#   log.gp.mappers.mac_mapper_network.pl: TRACE
#
# if log level is TRACE, then the output of system command will also be logged
# (need to use RunCommand)
#
# sometimes developer may want to print log message to stdout:
#
#   gp.mappers.print_log_to_stdout: 1
#
# or
#
#   gp.mappers.print_log_to_stdout.mac_mapper_network.pl: 1
#
$GP_DEBUG = 0;              # debug level
$GP_TRACE = 0;              # trace level (more information)
$GP_LOG_PRINT_TO_STDOUT = 0; # print all log entries to stdout. for debug

my $KILL_TIMEOUT = 2;
my $MAX_OUTPUT_LINES = 1000;


my $TEMP_DIR_NON_ROOT_WRITABLE_PATH = '/tmp';
my $TEMP_DIR_NON_ROOT_READABLE_PATH = '/var/centrify/tmp';
my $TEMP_DIR_NON_ROOT_READABLE_PERM = 0755;
my $TEMP_DIR_NON_ROOT_READABLE_UID = 0;
my $TEMP_DIR_NON_ROOT_READABLE_GID = 0;

#
# Define if the directory path should be skipped for path fixing
#
#   hash ref key:       full directory path
#   hash ref value:     can be skipped (1) or not (0)
#
#   e.g. '/var' => '1',
#
my $fix_path_exception_list = {
    '/var' => '1',
};

my $TEMP_FILE_NAME_TRY_COUNT = 10;



my $gp_logger;

sub __InitLogger();

# debug
sub FATAL_OUT;  # fatal error occured. exit 1. tell user how to enable debug log if not enabled
sub ERROR_OUT;  # log error message
sub WARN_OUT;   # log warning message
sub INFO_OUT;   # log info message
sub DEBUG_OUT;  # log debug message
sub TRACE_OUT;  # log trace message
sub IsDebugOn();
sub IsTraceOn();
sub _Log;

# system
sub _TimedWait($$);
sub RunCommandWithTimeout($$);
sub RunCommand($;$);
sub ChangeOwner($$);    # change file's owner to specified user
sub CreateDir($;$);     # create dir and set owner
sub ReadFile($);        # read file into a string
sub WriteFile($$;$);    # write string into file
sub GetFullPath($);     # return full path of a given file
sub GetTempDirPath($);  # return temp dir path
sub CreateTempFile($);  # create a temp file and return file handler/name
sub TraverseSymLink($); # traverse symlink and return the actual file

# general
sub IsEqual;    # compare two variable/hash/array/scalar
sub _IsEqual;
sub IsEmpty($);
sub AddElementsIntoArray($$);
sub RemoveElementsFromArray($$);
sub DiffTwoArray($$);



#
# get log setting from centrifydc.conf and init logger.
#
sub __InitLogger()
{
    my $program_name = basename $0;

    $gp_logger = CentrifyDC::Logger->new('');

    my @log_entries = ('log', 'log.gp.mappers', "log.gp.mappers.${program_name}");
    foreach my $log_entry (@log_entries)
    {
        my $property = $CentrifyDC::Config::properties{$log_entry};
        if (defined($property))
        {
            $gp_logger->level($property);
            if ($property eq 'DEBUG')
            {
                $GP_DEBUG = 1;
                $GP_TRACE = 0;
            }
            elsif ($property eq 'TRACE')
            {
                $GP_DEBUG = 1;
                $GP_TRACE = 1;
            }
            else
            {
                $GP_DEBUG = 0;
                $GP_TRACE = 0;
            }
        }
    }

    my @redirect_entries = ('gp.mappers.print_log_to_stdout', "gp.mappers.print_log_to_stdout.${program_name}");
    foreach my $redirect_entry (@redirect_entries)
    {
        my $property = $CentrifyDC::Config::properties{$redirect_entry};
        if (defined($property))
        {
            if ($property eq '0')
            {
                $GP_LOG_PRINT_TO_STDOUT = 0;
            }
            else
            {
                $GP_LOG_PRINT_TO_STDOUT = 1;
            }
        }
    }
}



# >>> DEBUG >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# log fatal error message and exit 1. if debug log is not enabled, tell user how to
# enable it.
#
#   @_:  message (optional)
#
#   exit:   1
#
sub FATAL_OUT
{
    my $program_name = basename $0;

    my $loglevel = 'info';

    my $first = shift;
    if (defined($first))
    {
        $first = ">>> " . $first;
        unshift(@_, $first);
        _Log($loglevel, @_);
    }
    else
    {
        _Log($loglevel, ">>> A problem occured while running $0");
    }

    if (! $GP_DEBUG)
    {
        _Log($loglevel, 'Please enable debug log by adding the following line into /etc/centrifydc/centrifydc.conf:');
        _Log($loglevel, "log.gp.mappers.${program_name}\: DEBUG");
        _Log($loglevel, 'Use TRACE instead of DEBUG will give you the most detailed information.');
    }

    exit(1);
}

#
# log error message
#
# filename, line number, and parent subroutine will be added in front of the
# actual error message
#
#   @_:  message
#
sub ERROR_OUT
{
    my $first = shift;

    my $filename = (caller(0))[1];
    my $line = (caller(0))[2];
    my $subroutine = defined(caller(1)) ? (caller(1))[3] : 'main';

    $first = ">>> $filename : $line : $subroutine : $first";
    unshift(@_, $first);

    _Log('info', @_);
}

sub WARN_OUT
{
    _Log('info', @_);
}

sub INFO_OUT
{
    _Log('info', @_);
}

sub DEBUG_OUT
{
    $GP_DEBUG and _Log('debug', @_);
}

sub TRACE_OUT
{
    $GP_TRACE and _Log('trace', @_);
}

sub IsDebugOn()
{
    return $GP_DEBUG;
}

sub IsTraceOn()
{
    return $GP_TRACE;
}

#
# log message and print to stdout if necessary
#
#   $_[0]:  log level
#   @_:  log message
#
sub _Log
{
    defined($_[1]) or return;

    my $loglevel = shift;
    my $format = shift;

    # For outputing the quotes in loginfo,we must use "\" to escape the quotes.
    my $msg = sprintf($format, @_);
    $msg =~ s/\"/\\"/g;
    $gp_logger->log($loglevel, $msg);

    $GP_LOG_PRINT_TO_STDOUT or return;
    print STDOUT "$msg\n";
}

# <<< DEBUG <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> SYSTEM >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# Wait for the specified number of seconds for a child process to finish.
#
#   $_[0]:  pid
#   $_[1]:  timeout (seconds)
#
sub _TimedWait($$)
{
    my ($pid, $timeout) = @_;

    my ($ret, $error);

    eval
    {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        my $rc = waitpid($pid, 0);
        $ret = $? >> 8;
        alarm 0;
    };

    $error = $@;

    if ($error)
    {
        if ($error ne "alarm\n")   # propagate unexpected errors
        {
            ERROR_OUT("process $pid died unexpectedly: $error");
        }
    }

   return ($ret, $error);
}

#
# run command with specified timeout
#
# if command doesn't finish in specified time, send SIGTERM and wait for 2
# seconds; if still doesn't finish, send SIGKILL and wait for 2 seconds;
# if still doesn't finish, fail.
#
# in scalar context, return command return value.
# in list context, return command return value and command output.
# If lock seed is specified, a lockfile will be created to ensure
# no other process is running the same command. lockfile name is
# generated from the seed
#
#   $_[0]:  command
#   $_[1]:  timeout (seconds)
#
#   return: 
#       in scalar context:
#           number  - return value of the command
#           undef   - failed
#       in list context:
#       $1: 
#           number  - return value of the command
#           undef   - failed
#       $2:
#           string  - command output
#
sub RunCommandWithTimeout($$)
{
    my ($cmd, $timeout) = @_;

    defined($cmd) or return undef;
    defined($timeout) or return undef;

    DEBUG_OUT("Run command [%s] with timeout [%s] seconds", $cmd, $timeout);

    my $pid = open3(gensym, \*PH, \*PH, $cmd);

    my $iszombie = 0;
    my ($ret, $error) = _TimedWait($pid, $timeout);

    if ($error)
    {
        DEBUG_OUT("Command [%s] taking too long, sending SIGTERM", $cmd);
        kill(SIGTERM, $pid);
    
        (undef, $error) = _TimedWait($pid, $KILL_TIMEOUT);
    }

    if ($error)
    {
        DEBUG_OUT("Command [%s] is not responding to SIGTERM, sending SIGKILL", $cmd);
        kill(SIGKILL, $pid);
    
        (undef, $error) = _TimedWait($pid, $KILL_TIMEOUT);
    }

    if ($error)
    {
        ERROR_OUT("Command [%s] is not responding to SIGKILL", $cmd);
        $iszombie = 1;
    }

    my @output = <PH>;

    my $openfail = 0;
    foreach my $line (@output)
    {
        if ($line =~ m/^open3:/g)
        {
            ERROR_OUT("Fail to run command using open3: %s", $line);
            $openfail = 1;
            last;
        }
    }

    if (! $openfail)
    {
        if (! defined($ret))
        {
            if ($iszombie)
            {
                ERROR_OUT("Command [%s] takes too long to run and cannot be killed", $cmd);
            }
            else
            {
                ERROR_OUT("Command [%s] takes too long to run and is killed", $cmd);
            }
        }
    }

    # only log output when loglevel is TRACE
    if ($GP_TRACE)
    {
        if (! IsEmpty(\@output))
        {
            my $i = 1;
            TRACE_OUT(" command return: $ret");
            TRACE_OUT(" command output:");
            foreach my $line (@output)
            {
                my $str = $line;
                chomp $str;
                TRACE_OUT("%s", " | $str");
                $i++;
                if ($i > $MAX_OUTPUT_LINES)
                {
                    TRACE_OUT("  ... command output too long. truncate.");
                    last;
                }
            }
        }
    }

    wantarray() ? (return ($ret, join('', @output))) : (return $ret);
}

#
# run command
#
# in scalar context, return command return value.
# in list context, return command return value and command output.
# If lock seed is specified, a lockfile will be created to ensure
# no other process is running the same command. lockfile name is
# generated from the seed
#
#   $_[0]:  command
#   $_[1]:  lock seed (optional)
#
#   return: 
#       in scalar context:
#           number  - return value of the command
#           undef   - failed
#       in list context:
#       $1: 
#           number  - return value of the command
#           undef   - failed
#       $2:
#           string  - command output
#
sub RunCommand($;$)
{
    my ($cmd, $lockfile) = @_;

    my $ret;

    DEBUG_OUT("run command: [%s]", $cmd);
    if (defined($lockfile))
    {
        TRACE_OUT(" lockfile: [%s]", $lockfile);
        my $dir = dirname $lockfile;
        if (defined($dir))
        {
            if (! -d $dir)
            {
                TRACE_OUT(" create dir [%s]", $dir);
                eval
                {
                    umask 0022;
                    mkpath($dir, 0, 0755);
                };
                if ($@)
                {
                    ERROR_OUT("Cannot create dir [%s]: %s", $dir, $@);
                    return undef;
                }
            }
        }
        if (! open(CMDLCK, ">$lockfile"))
        {
            ERROR_OUT("Cannot open lockfile [%s]", $lockfile);
            return undef;
        }
        if (! flock(CMDLCK, LOCK_EX|LOCK_NB))
        {
            ERROR_OUT("Cannot lock lockfile [%s]", $lockfile);
            return undef;
        }
    }

    my $rc;

    # include both STDOUT and STDERR
    $rc = open(OUTPUT, "$cmd 2>&1 |");
    if (! $rc)
    {
        ERROR_OUT("Cannot open pipe for command [%s]: %s", $cmd, $!);
        return undef;
    }

    my @output = <OUTPUT>;

    $rc = close(OUTPUT);
    #
    # need to grab $? right after closing the pipe, because logger module
    # will use system command
    #
    $ret = $? >> 8;
    if ($? & 127)
    {
        # command terminated by signal
        ERROR_OUT("Command [%s] terminated by signal %s", $cmd, $? & 127);
        $ret = undef;
    }
    else
    {
        TRACE_OUT(" return: [$ret]");
    }
    if (! $rc)
    {
        #
        # If the file handle came from a piped open, close will additionally
        # return false if one of the other system calls involved fails,
        # or if the program exits with non-zero status.
        # If the only problem was that the program exited non-zero,
        # $! will be set to 0 .
        #
        if ($!)
        {
            WARN_OUT("Cannot close pipe");
        }
    }


    # only log output when loglevel is TRACE
    if ($GP_TRACE)
    {
        if (! IsEmpty(\@output))
        {
            TRACE_OUT(" command output:");
            foreach my $line (@output)
            {
                my $str = $line;
                chomp $str;
                TRACE_OUT("%s", " | $str");
            }
        }
    }

    if (defined($lockfile))
    {
        flock(CMDLCK, LOCK_UN);
        close(CMDLCK);
        unlink($lockfile);
    }

    wantarray() ? (return ($ret, join("", @output))) : (return $ret);
}

#
# change file's owner to specified user
#
#   $_[0]:  file
#   $_[1]:  user
#
#   return: 1       - successful
#           undef   - failed
#
sub ChangeOwner($$)
{
    my ($file, $user) = @_;

    if (! defined($file))
    {
        ERROR_OUT("File not defined");
        return undef;
    }
    if (! -e $file)
    {
        ERROR_OUT("File [$file] not exist");
        return undef;
    }

    if (! defined($user))
    {
        ERROR_OUT("User not defined");
        return undef;
    }

    my ($fileuid, $filegid) = (stat $file)[4, 5];
    my ($uid, $gid) = (getpwnam($user))[2, 3];
    if (! defined($uid) || ! defined($gid))
    {
        ERROR_OUT("Cannot get uid/gid of user [$user]");
        return undef;
    }

    if ($uid ne $fileuid || $gid ne $filegid)
    {
        TRACE_OUT("Change owner of [$file] to [$user] $uid:$gid");
        if (! chown($uid, $gid, $file))
        {
            ERROR_OUT("Cannot change ownership of [$file]");
            return undef;
        }
    }

    return 1;
}

#
# create directory and set owner if user is specified
#
#   $_[0]:  dir
#   $_[1]:  user (optional)
#
#   return: 1       - successful
#           undef   - failed
#
sub CreateDir($;$)
{
    my ($dir, $user) = @_;

    if (! defined($dir))
    {
        ERROR_OUT("Dir not defined");
        return undef;
    }

    if (! -d $dir)
    {
        # if dir not exist, create
        if (! -e $dir)
        {
            TRACE_OUT("create dir [$dir]");
            my $rc;
            eval
            {
                umask 0022;
                $rc = mkpath($dir, 0, 0755);
            };
            if ($@)
            {
                ERROR_OUT("Cannot create dir [$dir]: $@");
                return undef;
            }
            if (! $rc)
            {
                ERROR_OUT("Cannot create dir [$dir]");
                return undef;
            }
        }
        else
        {
            ERROR_OUT("[$dir] exists but is not a directory");
            return undef;
        }
    }

    # set dir's ownership
    if (defined($user))
    {
        if (! defined(ChangeOwner($dir, $user)))
        {
            ERROR_OUT("Cannot change owner of [$dir]");
            return undef;
        }
    }

    return 1;
}

#
# read file into a string, or return undef if file not exist or read failed.
#
#   $_[0]:  filename
#
#   ret:    string  - file content
#           undef   - failed or no such file
#
sub ReadFile($)
{
    my $file = $_[0];

    TRACE_OUT("read [$file]");

    if (! -e $file)
    {
        DEBUG_OUT("Read [$file]: file not exist. return undef");
        return undef;
    }
    if (-d $file)
    {
        ERROR_OUT("Cannot read [$file]: $file is a directory");
        return undef;
    }
    if (! -r $file)
    {
        ERROR_OUT("Cannot read [$file]: no permission");
        return undef;
    }

    my @content_list;
    my $rc;

    $rc = open(FILE, "<$file");
    if (! $rc)
    {
        ERROR_OUT("Cannot open [$file]: $!");
        return undef;
    }

    @content_list = <FILE>;

    $rc = close(FILE);
    if (! $rc)
    {
        WARN_OUT("Cannot close [$file]: $!");
    }

    return (join "", @content_list);
}

#
# write string into file
#
# create a temp file, write into it, replace the original file and restore
# file attributes.
#
# need to use lockfile to prevent race condition. lock file can be specified
# or let the function decide by itself.
#
#   $_[0]:  file name
#   $_[1]:  string
#   $_[2]:  lock file name (optional)
#
#   return: 1       - successful
#           undef   - failed
#
sub WriteFile($$;$)
{
    my ($file, $content, $lockfile) = @_;

    DEBUG_OUT("Write [$file]");

    if (-d $file)
    {
        ERROR_OUT("Cannot write $file: $file is a directory");
        return undef;
    }

    my ($fh, $temp_file) = CreateTempFile($file);
    defined($fh) or return undef;
    TRACE_OUT(" temp file: [$temp_file]");

    my $is_file_exists = 0;
    my ($mode, $uid, $gid);
    if (-e $file)
    {
        $is_file_exists = 1;
        ($mode, $uid, $gid) = (stat $file)[2, 4, 5];
        $mode = $mode & 07777;
        TRACE_OUT("Backup $file stat:  mode: [%04o]  uid: [%d]  gid: [%d]", $mode, $uid, $gid);
    }
    else
    {
        # create parent dir if not exist
        my $dir = dirname $file;
        if (defined($dir))
        {
            if (! -d $dir)
            {
                TRACE_OUT(" create dir [$dir]");
                eval
                {
                    umask 0022;
                    mkpath($dir, 0, 0755);
                };
                if ($@)
                {
                    ERROR_OUT("Cannot create dir [$dir]: $@");
                    return undef;
                }
            }
        }
    }

    my $lock;
    if (defined($lockfile))
    {
        # use specified lockfile
        $lock = CentrifyDC::GP::Lock->new($lockfile, 1);
    }
    else
    {
        $lock = CentrifyDC::GP::Lock->new($file);
    }
    if (! defined($lock))
    {
        ERROR_OUT("Cannot obtain lock");
        return undef;
    }
    TRACE_OUT(" lock file: [" . $lock->file() . "]");

    defined($content) or $content = '';
    my $rc;

    # write file
    $rc = print $fh $content;
    if (! $rc)
    {
        ERROR_OUT("Cannot write to $temp_file: $!");
        return undef;
    }

    $rc = close($fh);
    if (! $rc)
    {
        WARN_OUT("Cannot close $temp_file: $!");
    }

    # set file attribute
    if ($is_file_exists)
    {
        if (! chmod($mode, $temp_file))
        {
            ERROR_OUT("Cannot set mode for [$temp_file].");
            return undef;
        }
        if (! chown($uid, $gid, $temp_file))
        {
            ERROR_OUT("Cannot set ownership for [$temp_file].");
            return undef;
        }
    }

    $rc = rename($temp_file, $file);
    if (! $rc)
    {
        ERROR_OUT("Cannot rename $temp_file to $file: $!");
        return undef;
    }

    return 1;
}

#
# get full path of a given file
#
# can't glob the filename directly, because if file doesn't exist, glob
# will fail. to make it work, use getpwnam to get user's home dir
#
# example: ~root/filename
# first glob ~root, then combine the result with /filename
# result will be /var/root/filename
#
#   $_[0]:  filename
#
#   ret:    string  - full path
#           undef   - failed
#
sub GetFullPath($)
{
    my $file = $_[0];

    defined($file) or return undef;

    ($file =~ m|^\~|) or return $file;

    TRACE_OUT("get full path of [$file]");

    my $file_path = $file;
    # extract ~username from file path
    ($file_path =~ s%^\~(.*?)(/.*)%$2%) or return $file;

    my $dir;
    if ($1)
    {
        $dir =(getpwnam($1))[7];
    }
    else
    {
        $dir = $ENV{HOME} || $ENV{LOGDIR} || (getpwuid($>))[7];
    }
    if (! defined($dir))
    {
        ERROR_OUT("Cannot get full path of [$file]");
        return undef;
    }

    $file_path = $dir . $2;

    TRACE_OUT("full path: [$file_path]");

    return $file_path;
}

#
# fix path if not exists or has unexpected permission and ownership
#
# the rationle of checking and fixing temp directory is that, if the temp 
# directory is world writable, attackers can easily insert a symlink using the 
# same file name as the temp file to be written. If the temp file is written by 
# root, then the file in which the symlink is pointed to (e.g. /etc/passwd) 
# will be overwritten. If the temp file has ownership and permission changed by 
# root, then attackers can gain access to root protected files.
#
# therefore, we will use non-world writable temp directory to protect against 
# symlink attack. We will ensure the whole temp directory path is secure. If 
# not, we will try to fix it as described below:
#
# We will check directory per level in path (e.g. /var/centrify/tmp):
#   1. if the directory doesn't exist. Go to (4).
#   2. if this is a symlink, delete it. Go to (4).
#   3. if it exists, check if permission and ownership are OK (*). If OK, 
#      finish. If not, correct permission and ownership as described in (*).
#   4. Create it
#   5. Set permission and ownership as described in (*)
#      
#   (*) Good permission and ownership mean:
#       group=root, owner=root, permission=0755
#
# Exceptions:
#   - we cannot remove /var in Mac because it is a symlink to /private/var by 
#     default. For this reason, we will skip checking symlink for well-known 
#     system pre-defined directory. However, we should still check the 
#     ownership and permission of the destinated directories to ensure the 
#     whole path is secure.
#
# NOTE:
# since now a number of perl scripts will call GetTempDirPath() using root or 
# normal user privileges. Please make sure this subroutine is safe in both 
# cases.
#
#
#   $_[0]:  directory path to be fixed (assume in format /dir1/dir2/dir3)
#   $_[1]:  expected file permission of the directory
#   $_[2]:  expected owner (in uid) of the directory
#   $_[3]:  expected group (in gid) of the directory
#
#   return: 1       - success
#           undef   - failed
#
sub FixPath($$$$)
{
    my ($path, $perm, $uid, $gid) = @_;

    my $ret = 1;
    my $process_mask = 0;
    my $mkdir_flag = 0;
    my $subPath = '';

    my $rc;
    my $file_type;


    # NOTE:
    # Logs are printed in INFO when they are attempting to fix path, and ERROR 
    # when failed to complete the fix. We assume path fixing will not be run 
    # all the times unless there are something weird on customer's machine


    # backup and clear umask
    $process_mask = umask(0);
    
    # remove leading slash for split
    my $index = index($path, '/');
    $path = substr($path, 1) if ($index == 0);
    
    # check directory per level in path
    my @dirs = split('/', $path);
    foreach my $dir (@dirs) 
    {
        $mkdir_flag = 0;

        while (1)
        {
            $subPath = join('/', $subPath, $dir);

            # check if the directory path should be skipped
            if (exists $fix_path_exception_list->{$subPath})
            {
                if ($fix_path_exception_list->{$subPath})
                {
                    TRACE_OUT("Skip fixing [$subPath]...");
                    last;
                }
            }

            # 1. check if file exists
            if (! -e $subPath)
            {
                $mkdir_flag = 1;
                last;
            }

            # 2. check if file should be deleted (e.g. symlink)
            if (-l $subPath)
            {
                INFO_OUT("[$subPath] exists, but is a symlink. Delete.");
                $rc = unlink($subPath);
                if (!$rc)
                {
                    ERROR_OUT("Failed to delete symlink [$subPath]: $!");
                    $ret = undef;
                    last;
                }
                else
                {
                    $mkdir_flag = 1;
                }

                last;
            }
            else
            {
                # we expect file is a directory from now on. if not (e.g. a 
                # plain file), we will leave
                #
                # NOTE:
                # we may need to remove non-directory file if this subroutine is to 
                # use to fix /tmp
                if (! -d $subPath)
                {
                    ERROR_OUT("Cannot fix path as non-directory file is found [$subPath]");
                    $ret = undef;
                    last;
                }
            }

            # 3. check permission and ownership
            # use lstat to ensure symlink is checked
            my $sb = lstat($subPath);
            if (!defined $sb)
            {
                ERROR_OUT("Failed to get permission and ownership [$subPath]");
                $ret = undef;
                last;
            }

            # fix permission
            if (($sb->mode & 0777) != $perm)
            {
                INFO_OUT("Changing permission from %04o to %04o [$subPath]...", ($sb->mode & 0777), $perm);
                $rc = chmod($perm, $subPath);
                if ($rc != 1)
                {
                    ERROR_OUT("Failed to change permission from %04o to %04o [$subPath]", ($sb->mode & 0777), $perm);
                    $ret = undef;
                    last;
                }
            }

            # fix ownership
            if ($sb->uid != $uid || $sb->gid != $gid)
            {
                INFO_OUT("Changing ownership from UID %d GID %d to UID %d GID %d [$subPath]...", $sb->uid, $sb->gid, $uid, $gid);
                $rc = chown($uid, $gid, $subPath);
                if ($rc != 1)
                {
                    ERROR_OUT("Failed to change ownership from UID %d GID %d to UID %d GID %d [$subPath]", $sb->uid, $sb->gid, $uid, $gid);
                    $ret = undef;
                    last;
                }
            }

            # do block is not a real loop in perl, so we use while loop
            # break here to ensure this block will only run once
            last;
        }

        if ($ret && $mkdir_flag eq 1)
        {
            while (1)
            {
                # 4. make directory with correct permission
                # have to be atomic to ensure the directory is created with 
                # expected permission
                INFO_OUT("Creating directory [$subPath]...");
                $rc = mkdir($subPath, $perm);
                if (!$rc)
                {
                    ERROR_OUT("Failed to create directory [$subPath]: $!");
                    $ret = undef;
                    last;
                }

                # 5. set ownership
                INFO_OUT("Setting ownership to UID %d GID %d [$subPath]...", $uid, $gid);
                $rc = chown($uid, $gid, $subPath);
                if ($rc != 1)
                {
                    ERROR_OUT("Failed to set ownership to UID %d GID %d [$subPath]", $uid, $gid);
                    $ret = undef;
                    last;
                }

                # do block is not a real loop in perl, so we use while loop
                # break here to ensure this block will only run once
                last;
            }
        }

        # leave if already failed
        last if (!defined($ret));
    }

    # we need to reset umask before exit
    umask($process_mask);

    return $ret;
}

#
# return temp dir path
#
# If does not need to be non-root writable, we will return CDC's secure temp 
# directory (i.e. /var/centrify/tmp).
#
# If need to be non-root writeable instead, we will return public temp 
# directory (i.e. /tmp).
#
# WARNING:
# We will attempt to fix CDC directories to ensure the path is secure. Beware 
# when call this function with root privilege.
# 
#
#   $_[0]:  whether temp dir needs to be non-root writable
#           (0: not needed, 1: needed)
#
#   return: string  - if found valid temp dir path
#           undef   - if not found or path does not fulfill requirements
#
sub GetTempDirPath($)
{
    my $nonRootWritable = $_[0];

    my $dir = undef;
    my $perm;
    my $uid;
    my $gid;

    if (!$nonRootWritable)
    {
        $dir = $TEMP_DIR_NON_ROOT_READABLE_PATH;
        $perm = $TEMP_DIR_NON_ROOT_READABLE_PERM;
        $uid = $TEMP_DIR_NON_ROOT_READABLE_UID;
        $gid = $TEMP_DIR_NON_ROOT_READABLE_GID;

        $dir = undef if (!FixPath($dir, $perm, $uid, $gid));
    }
    else
    {
        # we assume /tmp has the expected permission and ownership
        $dir = $TEMP_DIR_NON_ROOT_WRITABLE_PATH;
        
        $dir = undef if (! -d $dir);
    }

    defined($dir) or ERROR_OUT("Failed to get temp directory path");
    return $dir;
}

#
# create a temp file and return file handler and filename.
# the filename is generated by appending pid or time to the end of source
# filename
#
# cannot use File::Temp because it causes weird error on Mac OS X and it's
# not in Perl 5.0
#
#   $_[0]:  seed string
#
#   return:
#       $1: 
#           file handler  - file handler of temp file
#           undef   - failed
#       $2:
#           string  - temp file name
#           undef   - failed
#
sub CreateTempFile($)
{
    my $file = $_[0];

    my $file_temp = undef;
    my $fh = gensym;

    my $tmp;
    my $rc;

    # generate temp file name
    # avoid using pid to make file name less predictable
    foreach (1..$TEMP_FILE_NAME_TRY_COUNT)
    {
        # use random number as suffix
        $tmp = $file . sprintf(".%04x", int(rand(65536)));
        if (! -e $tmp)
        {
            $file_temp = $tmp;
            last;
        }
        else
        {
            # try to remove symlink which conflicts with our temp file
            if (-l $tmp)
            {
                $rc = unlink($tmp);
                if ($rc)
                {
                    $file_temp = $tmp;
                    last;
                }
                else
                {
                    DEBUG_OUT("Cannot delete symlink [$tmp]: $!");
                    next;
                }
            }
            else
            {
                TRACE_OUT("File already exists [$tmp]");
            }
        }
    }

    if (defined($file_temp))
    {
        # NOTE: Setting O_CREAT|O_EXCL prevents the file from being opened if 
        # it is a symbolic link. It does not protect against symbolic links in 
        # the file's path. 
        #
        # NOTE: It is warned that in some UNIX systems, sysopen will fail when 
        # file descriptors exceed a certain value (typically 255) due to the 
        # use of fdopen() C library function.
        #
        # We will use a permission of 0600 because:
        # - We usually create temp file for self use only.
        # - In case we want the temp file to do sth extra, we can chmod to 
        #   relax the permission after creation.
        #
        my $rc = sysopen($fh, $file_temp, O_RDWR|O_CREAT|O_EXCL, 0600);
        if(! $rc)
        {
            ERROR_OUT("Cannot open temp file [$file_temp]: $!");
            return (undef, undef);
        }
        else
        {
            return ($fh, $file_temp);
        }

    }
    else
    {
        ERROR_OUT("Cannot create temp file for [$file]");
        return (undef, undef);
    }
}

#
# traverse symlink and return the actual file name.
#
#   $_[0]:  filename
#
#   ret:    string  - actual file name
#           undef   - failed
#
sub TraverseSymLink($)
{
    my $filename = $_[0];

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
                DEBUG_OUT("self reference found. stop following the symlink.");
                return $filename;
            }
        }
        $filename = $target;
        push(@known_links, $filename);
    }

    return $filename;
}

# <<< SYSTEM <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> GENERAL >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

# check if two variables are equal.
#
# Both variables can be scalar or reference variables. Supported reference
# types are: SCALAR, ARRAY, and HASH. Other data types are not supported,
# for example, you can't pass hash object to this function.
#
# Two undefined variables are considered equal.
#
#   $_[0]:  variable a
#   $_[1]:  variable b
#   return: 0       - different (or data type unsupported)
#           1       - same
sub IsEqual
{
    my ($a, $b) = @_;

    return _IsEqual($a, $b);
}

# Work function of IsEqual
#   $_[0]:  variable a
#   $_[1]:  variable b
#   @_:     list of parent ref
#   return: 0       - different (or data type unsupported)
#           1       - same
sub _IsEqual
{
    my ($a, $b, @parentref) = @_;

    # if both undefined, then equal
    # if one undefined, then different
    if (defined($a))
    {
        defined($b) or return 0;
    }
    else
    {
        defined($b) ? (return 0) : (return 1);
    }

    my $type = ref($a);

    # different if data type different
    ($type eq ref($b)) or return 0;

    if (! $type)
    {
        ("$a" eq "$b") ? (return 1) : (return 0);
    }
    ("$a" eq "$b") and return 1;

    my %parentrefhash = map { $_, 1 } @parentref;
    if (exists $parentrefhash{$a})
    {
        return 0;
    }
    else
    {
        push(@parentref, $a);
    }

    if ($type eq 'ARRAY')
    {
        # compare number of elements
        (@$a == @$b) or return 0;

        my @arr_a = @$a;
        my @arr_b = @$b;
        while (@arr_a)
        {
            (_IsEqual(pop(@arr_a), pop(@arr_b), @parentref)) or return 0;
        }
    }
    elsif ($type eq 'HASH')
    {
        # compare keys
        my @hashkey_a = sort keys %$a;
        my @hashkey_b = sort keys %$b;
        _IsEqual(\@hashkey_a, \@hashkey_b, @parentref) or return 0;

        # compare values
        foreach my $key (keys %$a)
        {
            _IsEqual($a->{$key}, $b->{$key}, @parentref) or return 0;
        }
    }
    elsif ($type eq 'SCALAR' or $type eq 'REF')
    {
        _IsEqual($$a, $$b, @parentref) or return 0;
    }
    else
    {
        # unsupported reference type
        return 0;
    }

    return 1;
}

#
# check if variable doesn't contain any data.
#
# if variable is undef or is empty array/hash, then it's empty
#
#   $_[0]:  variable
#
#   return: 0       - contains data
#           1       - empty
#
sub IsEmpty($)
{
    my $data = $_[0];

    defined($data) or return 1;

    my $type = ref($data);
    if ($type eq 'ARRAY')
    {
        # at least one element
        (@$data > 0) or return 1;
    }
    elsif ($type eq 'HASH')
    {
        # compare keys
        ((keys %$data) > 0) or return 1;
    }
    elsif ($type eq 'SCALAR')
    {
        return IsEmpty($$data);
    }

    return 0;
}

#
# add elements into an array
# this function will not modify the original array
#
#   $_[0]:  array reference
#   $_[1]:  elements (array reference or scalar)
#
#   return: array reference - successful
#           undef           - failed
#
sub AddElementsIntoArray($$)
{
    my ($array, $elements) = @_;

    if (ref($array) ne 'ARRAY')
    {
        ERROR_OUT("Cannot add elements into array: target is not an array");
        return undef;
    }

    my @new_array = @$array;

    IsEmpty($elements) and return \@new_array;

    my %hash = map { $_, 1 } @$array;
    if (ref($elements))
    {
        if (ref($elements) eq 'ARRAY')
        {
            foreach my $element (@$elements)
            {
                if (! exists($hash{$element}))
                {
                    TRACE_OUT("add [$element] into array");
                    push(@new_array, $element);
                }
            }
        }
        else
        {
            ERROR_OUT("Cannot add elements into array: elements not an array or a scalar");
            return undef;
        }
    }
    else
    {
        if (! exists($hash{$elements}))
        {
            TRACE_OUT("add [$elements] into array");
            push(@new_array, $elements);
        }
    }

    return \@new_array;
}

#
# remove elements from an array
# this function will not modify the original array
#
#   $_[0]:  array reference
#   $_[1]:  elements (array reference or scalar)
#
#   return: array reference - successful
#           undef           - failed
#
sub RemoveElementsFromArray($$)
{
    my ($array, $elements) = @_;

    if (ref($array) ne 'ARRAY')
    {
        ERROR_OUT("Cannot remove elements from array: target is not an array");
        return undef;
    }

    my @new_array = ();

    if (IsEmpty($elements))
    {
        @new_array = @$array;
        return \@new_array;
    }

    my %hash = map { $_, 1 } @$array;
    if (ref($elements))
    {
        if (ref($elements) eq 'ARRAY')
        {
            my @tmp_array = @$array;
            foreach my $element (@$elements)
            {
                # add element only if it's not in the array
                if (exists($hash{$element}))
                {
                    TRACE_OUT("remove [$element] from array");
                    foreach my $array_member (@tmp_array)
                    {
                        IsEqual($array_member, $element) or push(@new_array, $array_member); 
                    }
                    @tmp_array = @new_array;
                    @new_array = ();
                }
            }
            @new_array = @tmp_array;
        }
        else
        {
            ERROR_OUT("Cannot remove elements from array: elements not an array or a scalar");
            return undef;
        }
    }
    else
    {
        if (exists($hash{$elements}))
        {
            TRACE_OUT("remove [$elements] from array");
            foreach my $array_member (@$array)
            {
                IsEqual($array_member, $elements) or push(@new_array, $array_member); 
            }
        }
    }

    return \@new_array;
}

#
# compare two array and generate three lists:
#  1. items only in array 1
#  2. items only in array 2
#  3. items in both array 1 and 2
#
# all members in generated arrays are created in this function, not the
# original members of original arrays.
#
# undef and duplicated entry will be ignored.
#
#   $_[0]:  array reference - array 1
#   $_[1]:  array reference - array 2
#
#   return:
#       $1: 
#           array reference - items only in array 1
#       $2:
#           array reference - items only in array 2
#       $3:
#           array reference - items in both array 1 and 2
#
sub DiffTwoArray($$)
{
    my $array_1 = $_[0];
    my $array_2 = $_[1];

    my @a1_temp = ();
    my @a2_temp = ();

    # remove undef and duplicated entry, then sort
    foreach my $value (@$array_1)
    {
        defined($value) or next;
        push @a1_temp, $value;
    }
    my %hash1 = map { $_, 1 } @a1_temp;

    foreach my $value (@$array_2)
    {
        defined($value) or next;
        push @a2_temp, $value;
    }
    my %hash2 = map { $_, 1 } @a2_temp;

    my @a1 = sort keys %hash1;
    my @a2 = sort keys %hash2;

    my $size_a1 = @a1;
    my $size_a2 = @a2;
    my $p1 = 0;         # pointer to a1
    my $p2 = 0;         # pointer to a2
    my $a1only = [];    # a1 only
    my $a2only = [];    # a2 only
    my $both = [];      # in both a1 and a2
 
    if ($size_a2 == 0)
    {
        $a1only = \@a1;
    }
    elsif ($size_a1 == 0)
    {
        $a2only = \@a2;
    }
    else
    {
        # compare two array
        # put items only in a1 into a1only
        # put items only in a2 into a2only
        for ($p1 = 0, $p2 = 0; $p1 < $size_a1; )
        {
            if ($a1[$p1] lt $a2[$p2])
            {
                push @$a1only, $a1[$p1];
                $p1++;
            }
            elsif ($a1[$p1] gt $a2[$p2])
            {
                push @$a2only, $a2[$p2];
                $p2++;
            }
            else
            {
                push @$both, $a1[$p1];
                $p1++;
                $p2++;
            }

            # reach the end of a2
            if ($p2 >= $size_a2)
            {
                for ( ; $p1 < $size_a1; )
                {
                    push @$a1only, $a1[$p1];
                    $p1++;
                }
                last;
            }

            # reach the end of a1
            if ($p1 >= $size_a1)
            {
                for ( ; $p2 < $size_a2; )
                {
                    push @$a2only, $a2[$p2];
                    $p2++;
                }
                last;
            }
        }
    }

    TRACE_OUT("diff two arrays:");
    TRACE_OUT(" a1:      [" . join(" ", @a1) . "]");
    TRACE_OUT(" a2:      [" . join(" ", @a2) . "]");
    TRACE_OUT(" a1 only: [" . join(" ", @$a1only) . "]");
    TRACE_OUT(" a2 only: [" . join(" ", @$a2only) . "]");
    TRACE_OUT(" both:    [" . join(" ", @$both) . "]");

    return ($a1only, $a2only, $both);
}

# <<< GENERAL <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> INIT >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

__InitLogger();

1;
