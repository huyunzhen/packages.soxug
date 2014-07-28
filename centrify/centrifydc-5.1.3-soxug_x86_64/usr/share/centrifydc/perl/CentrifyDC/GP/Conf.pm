##############################################################################
#
# Copyright (C) 2011-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl Configuration file module.
#
##############################################################################

use strict;

package CentrifyDC::GP::Conf;
my $VERSION = '1.0';
require 5.000;

use vars qw(@ISA @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(GetSettingFromFile GetSettingFromStr GetAllSettingsFromConfFile UpdateConf);

use Fcntl qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN O_RDONLY O_CREAT O_EXCL);
use File::Basename;

use CentrifyDC::GP::General qw(:debug ReadFile TraverseSymLink RunCommand);

use constant DEFAULT_CONF_SEP               => '\s:=';
use constant DEFAULT_CONF_COMMENT_MARKER    => '#';
use constant DEFAULT_CONF_MATCH_EXPR        => '/^\s*([^\s:=]+)[:=]\s*(.*)/';

my $DEFAULT_MAXTRIES = 3;

my @tmpfiles;
my $original_values;

sub GetSettingFromFile($$;$);
sub GetSettingFromStr($$;$);
sub GetAllSettingsFromConfFile($;$);
sub DoCleanUp($);
sub mkstemp($);
sub rename_file($$);
sub UpdateConf($$$;$);



#
# Get a param setting from file.
#
#   $_[0]:  filename
#   $_[1]:  param. if empty or undef, return contents of the whole file
#   $_[2]:  separator (optional)
#
#   ret:
#       $1:
#           1       - successful
#           undef   - failed
#       $2:
#           string  - param setting.
#           undef   - param not found.
#
sub GetSettingFromFile($$;$)
{
    my ($file, $param, $sep) = @_;

    defined($file) or return undef;
    $file =~ s/^\s*//;
    $file =~ s/\s*$//;

    (-e $file) or return undef;
    (-f $file) or return undef;
    (-r $file) or return undef;

    defined($param) or $param = '';

    DEBUG_OUT("Get param setting [%s] from [%s]", $param, $file);

    defined($sep) or $sep = DEFAULT_CONF_SEP;
    ($sep ne '') or $sep = DEFAULT_CONF_SEP;
    $sep =~ s/^\[//;
    $sep =~ s/\]$//;

    #
    # if param is empty, return contents of the whole file.
    #
    if ($param eq '')
    {
        my $str = ReadFile($file);
        if (defined($str))
        {
            return (1, $str);
        }
        else
        {
            ERROR_OUT("Cannot get param setting from [%s]: file read error", $file);
            return undef;
        }
    }

    my $rc = open(FILE, "<$file");
    if (! $rc)
    {
        ERROR_OUT("Cannot open [%s]: %s", $file, $!);
        return undef;
    }

    #
    # parse the file line by line to get param setting.
    #
    my $data;
    my $multiline = 0;

    while (<FILE>)
    {
        my $line = $_;
        chomp($line);

        if ($multiline)
        {
            $line =~ s/^\s*//;
            $line =~ m/[^\\]*(\\*)$/;
            if (length($1) & 1)
            {
                $line =~ s/\\$//;
                $data = $data . $line;
            }
            else
            {
                #
                # reach the end of a multi-line setting
                #
                $data = $data . $line;
                $multiline = 0;
            }
        }
        else
        {
            if ($line =~ m/^\s*$param\s*[$sep]\s*(.*)$/)
            {
                $data = $1;
                $data =~ m/[^\\]*(\\*)$/;
                if (length($1) & 1)
                {
                    $data =~ s/\\$//;
                    $multiline = 1;
                }
            }
        }
    }

    $rc = close(FILE);
    if (! $rc)
    {
        DEBUG_OUT("Cannot close [%s]: %s", $file, $!);
    }

    DEBUG_OUT("[%s]: [%s]", $param, $data);
    return (1, $data);
}

#
# Get a param setting from a long (multi-line) string.
#
#   $_[0]:  string
#   $_[1]:  param. if empty or undef, return the whole string
#   $_[2]:  separator (optional)
#
#   ret:
#       $1:
#           1       - successful
#           undef   - failed
#       $2:
#           string  - param setting
#           undef   - param not found
#
sub GetSettingFromStr($$;$)
{
    my ($str, $param, $sep) = @_;
    my $data;

    defined($str) or return undef;
    defined($param) or $param = '';

    DEBUG_OUT("Get param setting [%s] from string", $param);

    defined($sep) or $sep = DEFAULT_CONF_SEP;
    ($sep ne '') or $sep = DEFAULT_CONF_SEP;
    $sep =~ s/^\[//;
    $sep =~ s/\]$//;

    # if no param, then return the whole string
    ($param ne '') or return (1, $str);

    #
    # parse the string line by line to get param setting.
    #
    # the following one-line method should work:
    #   $str =~  m/.*^\s*$param\s*$sep\s*(.*?[^\\])$/msg;
    # however, it cannot parse the following line correctly:
    #   param:
    # also, the performance is not acceptable when string is long and
    # param contains only one character
    #
    # the following method doesn't have performance issue, but it also
    # cannot handle the above case.
    #   while($str =~ m/^\s*$param\s*$sep\s*(.*?[^\\\$]*)$/msg)
    #   {
    #       $data = $1;
    #   }
    #   $data =~ s/^\s*//msg;
    #   while ($data =~ m/[^\\]*(\\*)\n/)
    #   {
    #       if (length($1) & 1)
    #       {
    #           $data =~ s/\\\n//;
    #       }
    #       else
    #       {
    #           $data =~ s/([^\\]*\\*)\n.*/$1/m;
    #       }
    #   }
    #
    my $multiline = 0;

    foreach (split(/\n/, $str))
    {
        my $line = $_;
        chomp($line);

        if ($multiline)
        {
            $line =~ s/^\s*//;
            $line =~ m/[^\\]*(\\*)$/;
            if (length($1) & 1)
            {
                $line =~ s/\\$//;
                $data = $data . $line;
            }
            else
            {
                #
                # reach the end of a multi-line setting
                #
                $data = $data . $line;
                $multiline = 0;
            }
        }
        else
        {
            if ($line =~ m/^\s*$param\s*[$sep]\s*(.*)$/)
            {
                $data = $1;
                $data =~ m/[^\\]*(\\*)$/;
                if (length($1) & 1)
                {
                    $data =~ s/\\$//;
                    $multiline = 1;
                }
            }
        }
    }

    DEBUG_OUT("[%s]: [%s]", $param, $data);
    return (1, $data);
}

#
# Get all settings from a standard conf file.
#
#   $_[0]:  filename
#   $_[1]:  separator (optional)
#
#   ret:    hash reference  - hash reference of param settings.
#           undef           - failed
#
sub GetAllSettingsFromConfFile($;$)
{
    my ($file, $sep) = @_;

    defined($file) or return undef;
    $file =~ s/^\s*//;
    $file =~ s/\s*$//;
    (-e $file) or return undef;
    (-f $file) or return undef;
    (-r $file) or return undef;

    defined($sep) or $sep = DEFAULT_CONF_SEP;
    ($sep ne '') or $sep = DEFAULT_CONF_SEP;
    $sep =~ s/^\[//;
    $sep =~ s/\]$//;

    my $rc = open(FILE, "<$file");
    if (! $rc)
    {
        ERROR_OUT("Cannot open [%s]: %s", $file, $!);
        return undef;
    }

    # parse the file line by line to get param setting.
    my $data;
    my $param;
    my $multiline = 0;
    my $settings = {};

    while (<FILE>)
    {
        my $line = $_;
        chomp($line);

        if ($multiline)
        {
            $line =~ s/^\s*//;
            $line =~ m/[^\\]*(\\*)$/;
            if (length($1) & 1)
            {
                $line =~ s/\\$//;
                $data = $data . $line;
            }
            else
            {
                # reach the end of a multi-line setting
                $data = $data . $line;
                $multiline = 0;
            }
            $settings->{$param} = $data;
        }
        else
        {
            if ($line =~ m/^\s*([^#$sep]*)\s*[$sep]\s*(.*)$/)
            {
                $param = $1;
                $data = $2;
                $data =~ m/[^\\]*(\\*)$/;
                if (length($1) & 1)
                {
                    $data =~ s/\\$//;
                    $multiline = 1;
                }
                $settings->{$param} = $data;
            }
        }
    }

    close(FILE) or DEBUG_OUT("Cannot close [%s]: %s", $file, $!);

    return $settings;
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

    TRACE_OUT("check leftover file for $file");
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
            DEBUG_OUT("Remove leftover temp file %s.", $file_tmp);
            unlink($file_tmp);
        }
    }
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
# rename a file and restore security context of the destination file (for selinux)
#
#   $_[0]:  source file
#   $_[0]:  destination file
#   ret:    1       - successful
#           undef   - failed
#
sub rename_file($$)
{
    my ($old_file, $new_file) = @_;

    if (! defined($old_file) || $old_file eq '')
    {
        ERROR_OUT("Cannot rename file: source file not specified.");
        return undef;
    }
    if (! defined($new_file) || $new_file eq '')
    {
        ERROR_OUT("Cannot rename file: destination file not specified.");
        return undef;
    }

    rename($old_file, $new_file) || return undef;

    # Restore context type if has selinux
    if ( -e "/sbin/restorecon" )
    {
        DEBUG_OUT("Restoring security context of %s", $new_file);
        my ($rc, $output) = RunCommand("/sbin/restorecon '$new_file'");

        if (! defined($rc))
        {
            ERROR_OUT("Fail to restore security context of %s", $new_file);
        }
    }

    return 1;
}

#
# Write settings into conf file.
#
#   $_[0]:  filename
#   $_[1]:  lock file name. if not defined, don't use lock file; if it's
#           'flock', lock the file itself.
#   $_[2]:  hash reference of settings. if hash key is empty string, update the
#           whole file
#   $_[3]:  hash reference of options (optional)
#           possible options:
#               sep => separator between param and setting. default is '\s:='
#
#   ret:
#       1       - successful
#       undef   - failed
#
sub UpdateConf($$$;$)
{
    my ($path, $lockfile, $settings, $options) = @_;
    defined($path) or return undef;
    $path =~ s/^\s*//;
    $path =~ s/\s*$//;

    defined($settings) or return undef;
    (ref($settings) eq 'HASH') or return undef;

    my $sep;
    my $comment_marker;
    my $match_expr;

    if (defined($options) and ref($options) eq 'HASH')
    {
        if (exists($options->{sep}))
        {
            $sep = $options->{sep};
        }
        if (exists($options->{comment_marker}))
        {
            $comment_marker = $options->{comment_marker};
        }
        if (exists($options->{match_expr}))
        {
            $match_expr = $options->{match_expr};
        }

    }

    defined($sep) or $sep = DEFAULT_CONF_SEP;
    ($sep ne '') or $sep = DEFAULT_CONF_SEP;
    $sep =~ s/^\[//;
    $sep =~ s/\]$//;

    defined($comment_marker) or $comment_marker = DEFAULT_CONF_COMMENT_MARKER;
    ($comment_marker ne '') or $comment_marker = DEFAULT_CONF_COMMENT_MARKER;

    defined($match_expr) or $match_expr = DEFAULT_CONF_MATCH_EXPR;
    ($match_expr ne '') or $match_expr = DEFAULT_CONF_MATCH_EXPR;

    DEBUG_OUT("Update %s", $path);

    my $new_settings = {};
    while (my ($key, $value) = each(%$settings))
    {
        DEBUG_OUT("[%s]: [%s]", $key, $value);
        $new_settings->{$key} = $value;
    }

    #
    # Open the input file, and a temporary to hold the new
    # contents as we build them.
    #
    $path = TraverseSymLink($path);

    DoCleanUp($path);

    my $lock;
    my $locktmp;
    my $tries = 0;
    my $maxtries = $DEFAULT_MAXTRIES;

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
                    DEBUG_OUT("Lockfile [%s] exists but is expired. Remove:  atime: [$atime]  now: [$now]", $lockfile);
                    if (! unlink($lockfile))
                    {
                        DEBUG_OUT("Cannot remove expired lockfile [%s]. Abort.", $lockfile);
                        return;
                    }
                }
                else
                {
                    DEBUG_OUT("Lockfile [%s] exists and is not expired:  atime: [$atime]  now: [$now]", $lockfile);
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
                next;
            }
        }
        else
        {
            if (!sysopen(INFILE, $path, O_RDONLY|O_CREAT|O_EXCL))
            {
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
            ERROR_OUT ("Cannot lock %s", $path);
            return undef;
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
    my $prevpos = 0;

    $original_values = {};

    while (<INFILE>)
    {
        my $file_value;
        my $file_data;

        my $line = $_;
        my $comment = 0;
        $copy_input = 1;
        #
        # Check to see if this is a comment line.  If it is,
        # remove the comment marker and process the rest of
        # the line as a setting.  That will match a commented-out
        # version of a setting, and cause the real value to be
        # output just after it.
        #
        if ($line =~ /^$comment_marker/)
        {
            $comment = 1;
            $line =~ s/^$comment_marker\s*//;
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
                $_ = "$comment_marker " . $line;
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
        }
        else
        {
            ( $file_value, $file_data ) = eval("if (\$line =~ $match_expr) { ( \$1, \$2 ); }");

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
                }
                next;
            }
        }

        #
        # Parse the input line into a value name and associated
        # data.  If none of the match expressions matches,
        # skip the line (copying it to the temp file verbatim).
        #
        ( $file_value, $file_data ) = eval("if (\$line =~ $match_expr) { ( \$1, \$2 ); }");

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
        # If we have a mapping for this value, replace it with
        # the data from the registry.
        #
        if (exists($settings->{$file_value}))
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
            if (defined($settings->{$file_value}))
            {
                print($tmp "$file_value: $settings->{$file_value}\n");
                undef($settings->{$file_value});
            }
            $copy_input = 0;
        }
    } continue {
        # Save position
        $prevpos = tell(INFILE);

        #
        # Copy the line if we haven't replaced it.
        #
        if ($copy_input)
        {
#            TRACE_OUT("Writting to temporary config file: $_");
            print($tmp $_);
        }
    }

    #
    # Add any values that weren't found earlier to the end of the file.
    #
    foreach my $file_value (sort(keys(%{$settings})))
    {
        if (exists($settings->{$file_value}))
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
            if (defined($settings->{$file_value}))
            {
                print($tmp "$file_value: $settings->{$file_value}\n");
            }
        }
    }

    close($tmp);

    foreach my $key (keys %$original_values)
    {
        TRACE_OUT("ORIGINAL: [%s]: [%s]", $key, $original_values->{$key});
    }
    foreach my $key (keys %$new_settings)
    {
        TRACE_OUT("NEW: [%s]: [%s]", $key, $new_settings->{$key});
    }

    #
    # Compare new settings with original settings. If any of the
    # settings get changed, then file has changed.
    #
    my $file_changed = 0;

    foreach my $key (keys %$new_settings)
    {
        my $value_changed = 0;

            #
            # Compare original setting and new setting. Can't use $a eq $b
            # because it cannot handle undef correctly.
            #
            my $oldval = $original_values->{$key};
            my $newval = $new_settings->{$key};
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
            DEBUG_OUT("property updated: $key: [$oldval] -> [$newval]");
            $file_changed = 1;
        }
    }

    undef $original_values;

    #
    # If the file has changed, move the new one into place. Otherwise, just
    # remove the temporary file and leave things alone.
    #
    if ($file_changed)
    {
        DEBUG_OUT("%s changed", $path);
        my $path_bak = $path . '.bak';
        unlink($path_bak);
        link($path, $path_bak);
        if (! rename_file($tmpfile, $path))
        {
            ERROR_OUT("Cannot rename %s to %s. restore from backup file %s", $tmpfile, $path, $path_bak);
            unlink($path);
            link($path_bak, $path);
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

    return 1;
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
