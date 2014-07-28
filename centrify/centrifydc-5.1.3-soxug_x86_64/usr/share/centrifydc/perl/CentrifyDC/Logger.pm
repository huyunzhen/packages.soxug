#
# Copyright (C) 2005-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl logging module.  Reads centrifydc.conf
# to determine the configured log level for the specified module.
#
# To create a new logger:
#
# my $logger = CentrifyDC::Logger->new('com.centrify.mappers.my_mapper');
#
# To log a message:
#
# $logger->log('DEBUG', "My pid is %d", $$);
#
# To get and set the level of message that will be logged (setting will
# override the level specified in centrifydc.conf):
#
# my $logLevel = $logger->level();
# $logger->level('DEBUG');
#
use strict;
use vars qw($VERSION %LEVELS %SYSLOG_LEVELS $PROGRAM_NAME);

package CentrifyDC::Logger;
my $VERSION = "1.0";
require 5.000;

use CentrifyDC::Config;

my %LEVELS = (
    TRACE	=> 0,
    DEBUG	=> 1,
    INFO	=> 2,
    WARN	=> 3,
    ERROR	=> 4,
    FATAL	=> 5,
);

my %SYSLOG_LEVELS = (
    TRACE	=> 'debug',
    DEBUG	=> 'debug',
    INFO	=> 'info',
    WARN	=> 'warning',
    ERROR	=> 'err',
    FATAL	=> 'emerg',
);

my %SYSLOG_FACILITIES = (
    KERN           => 'kern',
    USER           => 'user',
    MAIL           => 'mail',
    DAEMON         => 'daemon',
    AUTH           => 'auth',
    SYSLOG         => 'syslog',
    LPR	           => 'lpr',
    NEWS           => 'news',
    UUCP           => 'uucp',
    CRON           => 'cron',
    AUTHPRIV       => 'authpriv',
    FTP	           => 'ftp',
    LOCAL0         => 'local0',
    LOCAL1         => 'local1',
    LOCAL2         => 'local2',
    LOCAL3         => 'local3',
    LOCAL4         => 'local4',
    LOCAL5         => 'local5',
    LOCAL6         => 'local6',
    LOCAL7         => 'local7',
    AUDIT          => 'audit',
    MARK           => 'mark',
);

my $PROGRAM_NAME;

BEGIN
{
    ($PROGRAM_NAME = $0) =~ s/.*(?=\/)\/?([^\/]*)$/$1/;
}

#
# Implement our own version of syslog by calling the
# logger program.
#
# We won't use the perl Sys::Syslog package because on
# certain system (for example HP-UX B.11.31) it has problem
# and is extremely slow.
#
use vars qw($ident $facility);
my $ident;
my $facility;

sub openlog
{   
    my $logopt;
    ($ident, $logopt, $facility) = @_;

    foreach (split(/\s+/, $logopt))
    {
        /pid/ && do {           
            $ident .= "[$$]";
        };
    }    
}

sub syslog
{
    my $priority = shift;
    my $format = shift;
    my $loginfo;
    
    #For outputing the quotes in loginfo,we must use "\" to escape the quotes.
    $loginfo = sprintf($format, @_);
    $loginfo =~ s/\\/\\\\/g;
    $loginfo =~ s/"/\\"/g;
    $loginfo =~ s/\`/\\\`/g;
    
    my $command = "logger -p $facility.$priority -t $ident \"";
    $command .= $loginfo;
    $command .= "\"";

    system($command);
}

#
# Create a new logger.
#
sub new($$)
{
    my ($proto, $logname) = @_;
    my $class = ref($proto) || $proto;
    my $level;
    my $property;
    my $facility;

    #
    # Find the configured log level.
    #
    $property = "log." . $logname;

    while ($property ne "")
    {
	$level = $CentrifyDC::Config::properties{$property};
	last if ($level ne "" || $property eq "log");
	$property =~ s/\.[^\.]*$//;
    }

    if ($level eq "")
    {
	$level = "ERROR";
    }

    #
    # Find the configured facility.
    #
    $property = "logger.facility.*." . $logname;

    while ($property ne "")
    {
	$facility = $CentrifyDC::Config::properties{$property};
	last if ($facility ne "" || $property eq "logger.facility.*");
	$property =~ s/\.[^\.]*$//;
    }

    $facility = uc($facility);
    if ($facility eq "")
    {
	$facility = "AUTH";
    }

    #
    # Save log level and facility.
    #
    my $self = {
	level		=> uc($level),
	facility	=> $facility,
    };

    bless($self, $class);

    openlog($PROGRAM_NAME, 'pid', $SYSLOG_FACILITIES{$facility});

    return $self;
}

#
# Log a message.
#
sub log($$@)
{
    my $self = shift;
    my $level = uc(shift);

    if ($LEVELS{$level} >= $LEVELS{$self->{level}})
    {
	#
	# Catch errors from syslog; if an error or fatal message
	# couldn't be logged, write it to stderr.
	#
	eval {
	    syslog($SYSLOG_LEVELS{$level}, @_);
	};
	if ($@ && ($level eq 'ERROR' || $level eq 'FATAL'))
	{
	    my $format = shift;
	    printf(STDERR $format . "\n", @_);
	}
    }
}

#
# Get or set the log level.
#
sub level($;$)
{
    my ($self, $value) = @_;

    if (defined($value))
    {
	$self->{level} = uc($value);
    }

    return $self->{level};
}

1;
