##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl mapper script certificate utility module.
#
##############################################################################

use strict;

package CentrifyDC::GP::CertUtil;
my $VERSION = "1.0";
require 5.000;

use vars qw(@ISA @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(GetFingerprint);

use CentrifyDC::GP::General qw(:debug RunCommand);

my $openssl = "/usr/share/centrifydc/bin/openssl";

sub GetFingerprint($;$);


#
# Get fingerprint from a certificate file which is in specific format. Supported
# format are PEM, DER and NET.
#
#   $_[0]:  cert file
#   $_[1]:  cert file format
#
#   return: certificate fingerprint
#           undef   - failed
#
sub GetFingerprint($;$)                                                                                                                                                                                                                                                                                                   
{
    my ($file, $certForm) = @_; 

    if ($certForm ne 'PEM' && $certForm ne 'DER' && $certForm ne 'NET')
    {
        $certForm = 'DER';
    }

    TRACE_OUT("Get fingerprint from [$file]");
    #   
    # get fingerprint from certificate file.
    # output format:
    # SHA1 Fingerprint=XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX
    # to extract fingerprint, remove heading and :
    #   
    # Do not change the way the cache file name is determined (with
    # openssl x509 -fingerprint -sha1) without a corresponding change
    # to lib/darwin/pkinit.cpp.
    #   
    my $cmd = "${openssl} x509 -fingerprint -sha1 -noout -inform $certForm -in '$file'";
    my ($rc, $output) = RunCommand($cmd);
    if (! defined($rc) or $rc ne '0')
    {   
        ERROR_OUT("Cannot get fingerprint from $file");
        return undef;
    }   
    my $fingerprint = $output;
    $fingerprint =~ s/.*Fingerprint=//;
    $fingerprint =~ s/://g;
    chomp($fingerprint);
    
    if (defined($fingerprint))
    {   
        return $fingerprint;
    }   

    return undef;
}

1;
