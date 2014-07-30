#!/bin/bash /usr/share/centrifydc/perl/run
#
# Get stack trace information from CentrifyDC core dumps.

use strict;
use File::Temp;


# Global settings
my $core_dump_dir = "/var/centrifydc";
my $log_to_file = 0;


sub Info
{
    my $msg = shift;
    
    if ($log_to_file)
    {
        print LOG "$msg\n";
    }
    else
    {
        print "$msg\n";
    }
}

sub ToolPath
{
    my $tool = shift;
    
    my @dirs = ("/bin", "/usr/bin", "/usr/sbin", "/usr/local/bin", "/opt/langtools/bin/");
    foreach my $dir (@dirs)
    {
        if (-x "$dir/$tool")
        {
            return "$dir/$tool";
        }        
    }
    
    return "";
}

sub MDB_StackTrace
{
    my ($tool, $executable, $corefile) = @_;
    
    Info("Debugger: mdb");
    
    my $fh = File::Temp->new();
    my $filename = $fh->filename;
    
    print $fh "\$G\n";
    print $fh "::status\n";
    print $fh "::walk thread | ::findstack\n";
    print $fh "::quit\n";
    
    my $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    Info($msg);
    
    close($fh);
}

sub GDB_StackTrace
{
    my ($tool, $executable, $corefile) = @_;
    
    Info("Debugger: gdb");
    
    my $fh = File::Temp->new();
    my $filename = $fh->filename;
    
    print $fh "set pagination 0\n";
    print $fh "info threads\n";
    print $fh "thread apply all bt full\n";
    print $fh "quit\n";
    
    my $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    Info($msg);
    
    close($fh);
}

sub DBX_StackTrace
{
    my ($tool, $executable, $corefile) = @_;
    
    Info("Debugger: dbx");
    
    my $fh = File::Temp->new();
    my $filename = $fh->filename;
    
    print $fh "where\n";
    print $fh "quit\n";

    my $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    Info($msg);
    
    close($fh);
}

sub DBX_StackTrace_AIX
{
    my ($tool, $executable, $corefile) = @_;
    
    Info("Debugger: dbx");
    
    my $fh = File::Temp->new();
    my $filename = $fh->filename;
    
    # Get thread count.
    print $fh "thread\n";
    print $fh "quit\n";
    
    # DBX thread command sample output on AIX.
    # thread  state-k     wchan    state-u    k-tid   mode held scope function
    # $t1     wait                 running    20583     k   no   pro  select
    # $t2     run                  blocked    26515     k   no   pro  _event_sleep
    my $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    Info($msg);
    my @threads = ($msg =~ /[\s>]+\$t(\d+)\s+/gm);
    
    # Get thread stack trace info one by one.
    truncate($fh, 0);
    
    for my $index (@threads)
    {
        print $fh "thread current $index\n";
        print $fh "thread $index\n";
        print $fh "where\n";
    }
    print $fh "quit\n";
    
    $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    Info($msg);
    
    close($fh);
}

sub DBX_StackTrace_Solaris
{
    my ($tool, $executable, $corefile) = @_;
    
    Info("Debugger: dbx");
    
    my $fh = File::Temp->new();
    my $filename = $fh->filename;
    
    # Get thread count.
    print $fh "threads\n";
    print $fh "quit\n";
    
    # DBX threads command sample output on Solaris.
    # t@1  a  l@1   ?()   signal SIGSEGV in  __pollsys()
    # t@2  a  l@2   ThreadStart()   sleep on 0x21a0b0  in  __lwp_park()
    my $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    my @threads = split(/t\@\d\s+/, $msg);
    my $threads_count = scalar(@threads) - 1;
    
    # Get thread stack trace info one by one.
    truncate($fh, 0);
    
    my $index = 1;
    while ($index <= $threads_count)
    {
        print $fh "thread t\@$index\n";
        print $fh "where\n";
        $index++;
    }
    print $fh "quit\n";
    
    $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    Info($msg);
    
    close($fh);
}

sub ADB_StackTrace
{
    my ($tool, $executable, $corefile) = @_;
    
    Info("Debugger: adb");
    
    my $fh = File::Temp->new();
    my $filename = $fh->filename;
    
    print $fh "\$c\n";
    print $fh "\$q\n";
    
    my $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    Info($msg);
    
    close($fh);
}

sub ADB_StackTrace_HPUX
{
    my ($tool, $executable, $corefile) = @_;
    
    Info("Debugger: adb");
    
    my $fh = File::Temp->new();
    my $filename = $fh->filename;
    
    print $fh "\$pc\n";
    print $fh "\$q\n";
    
    my $msg = `$tool $executable $corefile < $filename 2> /dev/null`;
    Info($msg);
    
    close($fh);
}

sub GetStackTrace
{
    my $corefile = shift;
    my ($executable, $tool, $msg);
    
    # Get CDC binary path.    
    my $ret = `file $corefile`;
    
    if ($ret =~ /adclient/i)
    {
        $executable = "/usr/sbin/adclient";
    }
    else
    {
        Info("Unknown core dump owner: $ret");
        return;
    }
    
    # Get stack trace.
    $ret = `uname -s`;
    
    if ($ret =~ /SunOS/i)
    {
        $tool = ToolPath("mdb");
        if ($tool ne "")
        {
            MDB_StackTrace($tool, $executable, $corefile);
            return;
        }

        $tool = ToolPath("gdb");
        if ($tool ne "")
        {
            GDB_StackTrace($tool, $executable, $corefile);
            return;
        }
        
        $tool = ToolPath("dbx");
        if ($tool ne "")
        {
            DBX_StackTrace_Solaris($tool, $executable, $corefile);
            return;
        }
        
        $tool = ToolPath("adb");
        if ($tool ne "")
        {
            ADB_StackTrace($tool, $executable, $corefile);
            return;
        }
    }
    
    if ($ret =~ /HP-UX/i)
    {
        $tool = ToolPath("gdb");
        if ($tool ne "")
        {
            GDB_StackTrace($tool, $executable, $corefile);
            return;
        }
        
        $tool = ToolPath("adb");
        if ($tool ne "")
        {
            ADB_StackTrace_HPUX($tool, $executable, $corefile);
            return;
        }
        
        $tool = ToolPath("dbx");
        if ($tool ne "")
        {
            DBX_StackTrace($tool, $executable, $corefile);
            return;
        }
    }
    
    if ($ret =~ /AIX/i)
    {
        $tool = ToolPath("dbx");
        if ($tool ne "")
        {
            DBX_StackTrace_AIX($tool, $executable, $corefile);
            return;
        }

        $tool = ToolPath("gdb");
        if ($tool ne "")
        {
            GDB_StackTrace($tool, $executable, $corefile);
            return;
        }
        
        $tool = ToolPath("adb");
        if ($tool ne "")
        {
            ADB_StackTrace($tool, $executable, $corefile);
            return;
        }
    }
    
    if ($ret =~ /Linux|Darwin/i)
    {
        $tool = ToolPath("gdb");
        if ($tool ne "")
        {
            GDB_StackTrace($tool, $executable, $corefile);
            return;
        }

        $tool = ToolPath("dbx");
        if ($tool ne "")
        {
            DBX_StackTrace($tool, $executable, $corefile);
            return;
        }
        
        $tool = ToolPath("adb");
        if ($tool ne "")
        {
            ADB_StackTrace($tool, $executable, $corefile);
            return;
        }
    }
    
    Info("No debug tool was found.");
}

sub main
{
    my $outFile = $ARGV[0];    
    if (defined($outFile))
    {
        if (-e $outFile)
        {
            print "Removing previous $outFile\n";
            unlink($outFile);
        }
        $log_to_file = 1;
        open(LOG, "> $outFile") or die "Can't open $outFile for writing: $!\n";
    }
    
    # Handle core dump files.
    my $file;
    my $counter = 0;
    
    opendir(DIR, $core_dump_dir) or die "Can't open dir $core_dump_dir: $!";
    while (defined($file = readdir(DIR)))
    {
        if ($file =~ /^core/)
        {
            Info("Core dump file:");
            Info(`ls -l $core_dump_dir/$file`);
                        
            GetStackTrace("$core_dump_dir/$file");
            $counter++;
        }        
    }
    
    if ($counter == 0)
    {
        Info("No core dump was found.");
    }
    
    if ($log_to_file)
    {
        close(LOG);
    }
}

main();



