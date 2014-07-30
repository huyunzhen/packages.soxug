#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl configuration module.
#
# This module provides access to the Centrify DirectControl
# configuration file. It reads each line of the configuration file,
# then parses the line and puts the property and value into the %properties
#
use strict;

package CentrifyDC::Config;
my $VERSION = "1.0";
require 5.000;

use vars qw($VERSION $FILE %properties);

use Exporter;
my @ISA = qw(Exporter);
my @EXPORT_OK = qw(properties GetCertStore);

use Text::ParseWords;


sub BEGIN 
{
$FILE = "/etc/centrifydc/centrifydc.conf";
    open (CONF, "< $FILE") or die $!;
    my $skip = 0;
    my $tmp_line;

    while (<CONF>)
    {
    next if (/^#|^$/);
    #
    # Join continuous line which ends with '\' to one line, then parse the joined line.
    #
    if (/\\$/)
    {
        $skip = 1;
        $tmp_line = $tmp_line.$_;
        $tmp_line =~ s/\\$//;
        chomp($tmp_line);
        next;
    }
    if ($skip)
    {
        $_ = $tmp_line.$_;
        $tmp_line = "";
        $skip = 0;
    }
    /([^\s:=]+)[:=]?\s*(.*)[\r\n]*$/;
    my ($property, $value) = ($1, $2);
    my @words = split ('\s+', $value);
    $value = join(' ', @words);
    $properties{$property} = $value;
    }

    close (CONF);
}

#
# Get certificate store folder path.
#
# Machine cert store is /var/centrify/net/certs by default.
# User cert store is ~/.centrify by default.
#
#   ret:    cert store folder path
#
sub GetCertStore($)
{
    my $certstore;

    # machine cert store
    if (!defined($_[0]))
    {
        $certstore = $CentrifyDC::Config::properties{"adsec.cert.dir"};
        if (!defined($certstore))
        {
            $certstore = "/var/centrify/net/certs";
        }
    }
    # user cert store
    else
    {
        my $user = $_[0];
        my $userhome = (getpwnam($user))[7];
        $certstore = $userhome . "/.centrify";
    }
    
    return $certstore;
}

1;
