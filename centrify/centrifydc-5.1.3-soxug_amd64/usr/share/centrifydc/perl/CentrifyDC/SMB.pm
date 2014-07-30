#
# Perl module to get and put files via SMB.
#
# Copyright (C) 2005-2014 Centrify Corporation. All rights reserved.
#
use strict;

package CentrifyDC::SMB;
my $VERSION = "1.0";
require 5.000;

use lib '/usr/share/centrifydc/perl';
use POSIX qw(WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG);
use File::Find;
use File::Path;

use constant FILE_NOT_FOUND => 156;
use constant FILE_COPIED    => 157;

my $LISTFILE = ".cdc_smbfiles";
my $ADSMB = "/usr/bin/adsmb";
my $DOMAIN = `/usr/bin/adinfo -d`;
chomp $DOMAIN;

# Valid fields, and their defaults.
my %FIELDS = (
    convertCRLF         => undef, # Convert between LF and CRLF
    dirmode             => undef, # Permissions for created local directories
    directory           => undef, # $src is a directory (for Get[New]Files
    die                 => 1,     # Call die() on error
    flags               => undef, # Flags for adsmb
    includeHidden       => undef, # Include hidden files in {Get,Put}[New]Files
    mode                => undef, # Permissions for created local files.
    recurse             => undef, # {Get,Put}[New]Files recurse into subdirs
    removeDeleted       => undef, # Remove files deleted from $src
    user                => undef, # User to su to, undef = use machine creds
);

# Define an accessor method for each field.
foreach my $member (keys (%FIELDS))
{
    no strict 'refs';
    *$member = sub
    {
        my ($self, $value) = @_;

        if (defined($value))
        {
            $self->{$member} = $value;
        }

        return $self->{$member};
    }
}

# Create a new SMB object.
sub new($;$)
{
    my ($proto, $source_domain) = @_;
    my $class = ref($proto) || $proto;
    if ($source_domain)
    {
        $DOMAIN = $source_domain;
    }    
    my $self = {
        domain          => $DOMAIN,
        listfile        => $LISTFILE,
        adsmb           => $ADSMB,
        %FIELDS,
    };
    bless($self, $class);
    return $self;
}

#
# Parse an SMB path, adding adsmb options as appropriate,
# and returning the path that should be passed to adsmb.
#
sub ParsePath($$)
{
    my ($self, $path) = @_;
    my $share = "sysvol";

    # Convert \ to /, to allow either slash direction.
    $path =~ s#\\#/#og;

    if ($path =~ m#^//([^/]*)(/.*)#o)
    {
        #
        # /server\share\path or /server\%SYSVOL%\path
        #
        # Use the specified server (otherwise the nearest
        # domain controller will be used).
        #
        $self->{adsmbflags} .= " -h $1";
        $path = $2;
    }
    else
    {
        $self->{adsmbflags} .= " -d $self->{domain}";
    }

    if ($path !~ m#^(/|%)#o)
    {
        #
        # No leading \ is interpreted as %SYSVOL%\path.
        #
        $path = '%SYSVOL%/' . $path;
    }

    if ($path =~ m#^/?%SYSVOL%(/.*)#o)
    {
        #
        # %SYSVOL%\path or \%SYSVOL%\path.  The latter is
        # probably from the /server expression above.
        #
        # The path is relative to the domain's sysvol share
        # (\sysvol\domain, e.g. \sysvol\example.com)
        #
        $path = "/" . $self->{domain} . $1;
    }
    elsif ($path =~ m#^/([^/]*)(/.*)#o)
    {
        # \share\path
        $share = $1;
        $path = $2;
    }
    # Otherwise just a filename, assume the sysvol share.

    $self->{adsmbflags} .= " -s '$share'";
    return $path;
}

#
# Set adsmb command-line options based on the fields of
# the info hash passed in.
#
sub SetFlags($)
{
    my ($self) = @_;

    $self->{adsmbflags} = $self->{flags};

    if (! defined($self->{user}))
    {
        $self->{adsmbflags} .= " -m";
    }

    if ($self->{convertCRLF})
    {
        $self->{adsmbflags} .= " -C";
    }
}

#
# Run a command, possibly using su.
#
sub Run($$$)
{
    my ($self, $command, $flags) = @_;

    my $commandLine = "$self->{adsmb} $command $self->{adsmbflags} $flags";
    if ($self->{user})
    {
        $commandLine = "su - $self->{user} -c \"$commandLine\"";
    }

    my @output = `$commandLine`;
    if ($self->{die} && $command ne "dir")
    {
        if (WIFEXITED($?) && WEXITSTATUS($?) != 0 && WEXITSTATUS($?) != FILE_COPIED)
        {
            die("$commandLine failed: " . join($/, @output));
        }
        elsif (WIFSIGNALED($?))
        {
            die("$commandLine died with signal " . WTERMSIG($?));
        }
    }

    return @output;
}

#
# Parse the output of "adsmb dir".
#
sub SMBParseDir($)
{
    my ($line) = @_;

    chomp $line;
    if ($line =~
        /^ +(\d+) +-?(\d)+, +-?(\d)+, +-?(\d)+, +-?(\d)+, +(\d)+ (.+)$/o)
    {
        my $attr = hex($1);
        my $create = $2;
        my $modify = $3;
        my $change = $4;
        my $access = $5;
        my $size = $6;
        my $name = $7;

        return ($attr, $create, $modify, $change, $access, $size, $name);
    }
    else
    {
        # Invalid output format.
        return undef;
    }
}

#
# Run "adsmb dir" on a remote file and return the parsed output.
#
sub Stat($$)
{
    my ($self, $path) = @_;

    my ($line) = Run($self, "dir", "-T -r '$path'");
    return SMBParseDir($line);
}

#
# Traverse a file or directory on an SMB network share, calling
# $self->{function} for each file found.  If $src is a file,
# $self->{function} is simply called on that one file.
#
sub TraverseSMB($$$)
{
    my ($self, $src, $dest) = @_;

    my $path = $src;
    $path .= "/*";

    # Clear the list of remote filenames.
    my %found;

    if (defined($self->{dirmode}) && ! -d $dest)
    {
        eval {
            if ($self->{user})
            {
                # Use perl's mkpath; not all systems support mkdir -p.
                my $output = `su - $self->{user} -c '/usr/share/centrifydc/perl/run -e "use File::Path; mkpath(\\\"$dest\\\", 0, $self->{dirmode});"' 2>&1`;
                if (!WIFEXITED($?) || WEXITSTATUS($?) != 0)
                {
                    die($output);
                }
            }
            else
            {
                mkpath($dest, 0, $self->{dirmode})
            }

        };
        if ($@)
        {
            if ($self->{die})
            {
                die("Cannot create $dest: " . $@);
            }

            return;
        }
    }

    # Get the list of files.
    my @lines = Run($self, "dir", "-T -r '$path'");
    foreach my $line (@lines)
    {
        my $attr;
        my $name;
        my $newSrc = $src;
        my $newDest = $dest;

        ($attr, undef, undef, undef, undef, undef, $name) = SMBParseDir($line);
        if (!defined($name))
        {
            # Invalid output format.
            next;
        }

        next if ($name eq "." || $name eq "..");
        $found{$name} = 1;

        # Append the name within the directory to both source and dest.
        $newSrc .= "/$name";
        $newDest .= "/$name";

        if (! $self->{includeHidden} && ($attr & 0x02))
        {
            # Skip hidden files.
            next;
        }

        if (($attr & 0x10))
        {
            # Traverse a subdirectory.
            next unless ($self->{recurse});

            # recurse
            TraverseSMB($self, $newSrc, $newDest);
        }
        else
        {
            &{$self->{function}}($self, $newSrc, $newDest);
        }
    }

    #
    # Remove any files that were previously copied and have now been
    # deleted from the source directory.
    #
    if ($self->{removeDeleted})
    {
        RemoveDeleted($self, $dest, $dest, \&DeleteLocalFile, \%found);
    }
}

#
# Process an SMB file or directory.  If it's a file, just call the
# function; otherwise traverse the SMB directory tree.
#
sub ProcessSMBFileOrDir($$$)
{
    my ($self, $src, $dest) = @_;

    my $directory = $self->{directory};
    if (!defined($directory))
    {
        my ($attr) = Stat($self, $src);
        if ($attr & 0x10)
        {
            $directory = 1;
        }
    }

    if ($directory)
    {
        TraverseSMB($self, $src, $dest);
    }
    else
    {
        # A single file, just call the function.
        &{$self->{function}}($self, $src, $dest);
    }
}

#
# Remove destination files that have been deleted from the source.
#
sub RemoveDeleted($$$$$)
{
    my ($self, $markDir, $removeDir, $function, $found) = @_;

    open(FILES, "< $markDir/$self->{listfile}");

    while (<FILES>)
    {
        chomp;

        if (!defined($found->{$_}))
        {
            &{$function}($self, undef, "$removeDir/$_");
        }
    }

    close(FILES);

    if (scalar keys %$found)
    {
        open(FILES, "> $markDir/$self->{listfile}");
        print(FILES join($/, sort(keys(%{$found}))));
        print(FILES $/) if (scalar(keys(%{$found})) != 0);
        close(FILES);
    }
    else
    {
        unlink("$markDir/$self->{listfile}");
    }
}

#
# Traverse a file or directory on the local system, calling
# $self->{function} for each file found.  If $src is a file,
# $self->{function} is simply called on that one file.
#
sub TraverseLocal($$$)
{
    my ($self, $src, $dest) = @_;
    my %findOptions;
    my %found;

    if (! -d $src)
    {
        &{$self->{function}}($self, $src, $dest);
        return;
    }

    $findOptions{wanted} = sub
    {
        ProcessLocal($self, $src, $dest, \%found);
    };

    $findOptions{preprocess} = sub
    {
        if (! $self->{recurse} && $File::Find::dir ne $src)
        {
            return undef;
        }

        if ($self->{dirmode})
        {
            (my $dir = $File::Find::dir) =~ s/^$src//;
            MkSMBPath($self, $dest . $dir);
        }

        return @_;
    };

    if ($self->{removeDeleted})
    {
        $findOptions{postprocess} = sub
        {
            (my $dir = $File::Find::dir) =~ s/^$src//;
            RemoveDeleted($self, $src . $dir, $dest . $dir, \&DeleteSMBFile,
                \%{$found{$src . $dir}});
        }
    }

    find(\%findOptions, $src);
}

#
# Process a local file or directory found by the find() call above,
# calling the specified function for each one.
#
sub ProcessLocal($$$)
{
    my ($self, $src, $dest, $found) = @_;

    # Skip our file list and the current directory, and
    # anything that's not a file or directory..
    return if ($_ eq $self->{listfile} || $_ eq "." || (! -d $_ && ! -f $_));

    # Skip hidden files unless they're wanted.
    return if (! $self->{includeHidden} && /^\./);

    # Mark the file as found.
    $found->{$File::Find::dir}{$_} = 1;

    if (-d $_)
    {
        # Nothing to do for directories, other than check whether
        # recursion is enabled.
        if (! $self->{recurse})
        {
            $File::Find::prune = 1;
        }

        return;
    }

    # Build the full source and destination directory names.
    (my $dir = $File::Find::dir) =~ s/^$src//;
    $src .= $dir;
    $dest .= $dir;

    # Now call the specified function.
    &{$self->{function}}($self, $src . "/" . $_, $dest . "/" . $_);
}

# Worker function for getting a file from a network share.
sub GetFile($$$$)
{
    my ($self, $src, $dest, $command) = @_;

    Run($self, "$command", "-r '$src' -l '$dest'");

    if (WIFEXITED($?) && WEXITSTATUS($?) == FILE_COPIED)
    {
        if (defined($self->{mode}))
        {
            chmod($self->{mode}, $dest);
        }
    }
}

# Get a file from a network share, public and internal versions.
sub Get($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $src = ParsePath($self, $src);
    GetFile($self, $src, $dest, "get");
}

sub SMBGet($$$)
{
    my ($self, $src, $dest) = @_;

    GetFile($self, $src, $dest, "get");
}

# Get a file if it has been changed since the last time it was copied,
# public and internal versions.
sub GetNew($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $src = ParsePath($self, $src);
    GetFile($self, $src, $dest, "getnew");
}

#
# Get a file if local/remote file's modify time is different (which
# means at least one file is changed),
# public and internal versions.
#
sub GetMod($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $src = ParsePath($self, $src);
    GetFile($self, $src, $dest, "getmod");
}

sub SMBGetNew($$$)
{
    my ($self, $src, $dest) = @_;

    GetFile($self, $src, $dest, "getnew");
}

sub SMBGetMod($$$)
{
    my ($self, $src, $dest) = @_;

    GetFile($self, $src, $dest, "getmod");
}

#
# Get a file or directory from a network share, using the specified
# function.
#
sub SMBGetFiles($$$$)
{
    my ($self, $src, $dest, $function) = @_;

    SetFlags($self);
    $src = ParsePath($self, $src);
    $self->{function} = $function;

    ProcessSMBFileOrDir($self, $src, $dest);
}

#
# Get a file or directory from a network share, using the specified
#
sub GetFiles($$$)
{
    my ($self, $src, $dest) = @_;
    return SMBGetFiles($self, $src, $dest, \&SMBGet);
}

#
# Get a file or directory from a network share if it has been changed
# since the last time it was copied.
#
sub GetNewFiles($$$)
{
    my ($self, $src, $dest) = @_;
    return SMBGetFiles($self, $src, $dest, \&SMBGetNew);
}

#
# Get a file or directory from a network share if local/remote file's
# modify time is different (which means at least one file is changed).
#
sub GetModFiles($$$)
{
    my ($self, $src, $dest) = @_;
    return SMBGetFiles($self, $src, $dest, \&SMBGetMod);
}

# Worker function for putting a file onto a network share.
sub PutFile($$$$)
{
    my ($self, $src, $dest, $command) = @_;

    Run($self, "$command", "-r '$dest' -l '$src'");
}

# Put a file onto a network share, public and internal versions.
sub Put($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $dest = ParsePath($self, $dest);
    PutFile($self, $src, $dest, "put");
}

sub SMBPut($$$)
{
    my ($self, $src, $dest) = @_;

    PutFile($self, $src, $dest, "put");
}

# Put a file if it has been changed since the last time it was copied,
# public and internal versions.
sub PutNew($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $dest = ParsePath($self, $dest);
    PutFile($self, $src, $dest, "putnew");
}

sub SMBPutNew($$$)
{
    my ($self, $src, $dest) = @_;

    PutFile($self, $src, $dest, "putnew");
}

#
# Put a file or directory from a network share.
#
sub PutFiles($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $dest = ParsePath($self, $dest);
    $self->{function} = \&SMBPut;

    TraverseLocal($self, $src, $dest);
}

#
# Put a file or directory from a network share if it has been changed
# since the last time it was copied.
#
sub PutNewFiles($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $dest = ParsePath($self, $dest);
    $self->{function} = \&SMBPutNew;

    TraverseLocal($self, $src, $dest);
}

#
# Rename an SMB file.  The destination name must be
# on the same share as the source.
#
sub Rename($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $src = ParsePath($self, $src);
    $dest = ParsePath($self, $dest);
    Run($self, "rename", "-l $src -r '$dest'");
}

# Delete an SMB file
sub Delete($$)
{
    my ($self, $path) = @_;

    SetFlags($self);
    $path = ParsePath($self, $path);
    Run($self, "delete", "-r '$path'");
}

# Create an SMB directory
sub MkDir($$)
{
    my ($self, $path) = @_;

    SetFlags($self);
    $path = ParsePath($self, $path);
    Run($self, "mkdir", "-r '$path'");
}

# Worker function for MkPath (call this one from other methods).
sub MkSMBPath($$)
{
    my ($self, $path) = @_;

    my ($attr) = Stat($self, $path);
    if (! ($attr & 0x10))
    {
        (my $parent = $path) =~ s#/[^/]*$##;

        if ($parent ne "")
        {
            MkSMBPath($self, $parent);
        }

        Run($self, "mkdir", "-r '$path'");
    }
}

# Create an SMB directory, including any parent directories that
# do not exist.
sub MkPath($$)
{
    my ($self, $path) = @_;

    SetFlags($self);
    $path = ParsePath($self, $path);
    MkSMBPath($self, $path);
}

# Delete an SMB directory
sub RmDir($$)
{
    my ($self, $path) = @_;

    SetFlags($self);
    $path = ParsePath($self, $path);
    Run($self, "rmdir", "-r '$path'");
}

#
# Delete a copy of a file or directory.  If it's a file,
# just call the delete function.  For a directory, call
# RemoveDeleted with an empty list of found files, which
# will cause it to delete all the files in the local
# list file.
#
sub DeleteCopy($$$$)
{
    my ($self, $src, $dest, $function) = @_;
    my %emptyhash;
    my %findOptions;

    if (-f $src)
    {
        &{$function}($self, $src, $dest);
        return;
    }

    if (! $self->{recurse})
    {
        # No recursion, just clean the directory.
        RemoveDeleted($self, $src, $dest, $function, \%emptyhash);
        &{$function}($self, $src, $dest);
        return;
    }

    # Recursion is enabled; traverse the tree, cleaning each directory.
    $findOptions{wanted} = sub
    {
        return;
    };

    $findOptions{postprocess} = sub
    {
        (my $dir = $File::Find::dir) =~ s/^$src//;
        RemoveDeleted($self, $src . $dir, $dest . $dir, $function,
            \%emptyhash);
        &{$function}($self, $src . $dir, $dest . $dir);
    };

    finddepth(\%findOptions, $src);
}

#
# Delete the local copy of a remote file or directory.
# If the source is a directory, it is scanned, and the destination
# copy of every source file found is deleted.
#
sub DeleteLocalFile($$$)
{
    my ($self, $src, $dest) = @_;

    if (-d $dest)
    {
        rmdir($dest);
    }
    else
    {
        unlink($dest);
    }
}

sub DeleteLocalCopy($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);

    DeleteCopy($self, $dest, $dest, \&DeleteLocalFile);
}

#
# Delete the remote copy of a local file or directory.
# If the source is a directory, it is scanned, and the destination
# copy of every source file found is deleted.
#
sub DeleteSMBFile($$$)
{
    my ($self, $src, $dest) = @_;

    my ($attr) = Stat($self, $dest);

    if ($attr & 0x10)
    {
        Run($self, "rmdir", "-r '$dest'");
    }
    else
    {
        Run($self, "delete", "-r '$dest'");
    }
}

sub DeleteSMBCopy($$$)
{
    my ($self, $src, $dest) = @_;

    SetFlags($self);
    $dest = ParsePath($self, $dest);

    DeleteCopy($self, $src, $dest, \&DeleteSMBFile);
}

1;
