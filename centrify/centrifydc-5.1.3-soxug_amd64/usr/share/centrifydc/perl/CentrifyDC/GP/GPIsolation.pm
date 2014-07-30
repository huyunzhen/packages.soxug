##############################################################################
#
# Copyright (C) 2011-2014 Centrify Corporation. All rights reserved.
#
# Centrify DirectControl GP Isolation Registry module.
#
# This module is used when GP Isolation mode is disabled.
#
##############################################################################

use strict;

package CentrifyDC::GP::GPIsolation;
my $VERSION = '1.0';
require 5.000;

use vars qw(@ISA @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(GetRegKey GetRegValType GP_REG_FILE_CURRENT GP_REG_FILE_PREVIOUS GP_REG_FILE_LOCAL);

my %GP_ISOLATION_REGKEY = (
    'secedit.system.access.maximumpasswordage'  => 'secedit/system access',
    'secedit.system.access.minimumpasswordage'  => 'secedit/system access',
    'secedit.system.access.lockoutduration'     => 'secedit/system access',
    'secedit.system.access.lockoutbadcount'     => 'secedit/system access',
    'LegalNoticeText'                           => 'Software/Microsoft/Windows/CurrentVersion/Policies/System',
    'pam.password.expiry.warn'                  => 'Software/Microsoft/Windows NT/CurrentVersion/Winlogon',
    'gp.refresh.disable'                        => 'Software/Microsoft/Windows/CurrentVersion/Policies/System',
    'adclient.sntp.enabled'                     => 'Software/Policies/Microsoft/W32time/TimeProviders/NtpClient',
    'adclient.sntp.poll'                        => 'Software/Policies/Microsoft/W32Time/Config',
    'AutoEnroll'                                => 'Software/Policies/Microsoft/Cryptography/Autoenrollment',
    'TrustedRootCA'                             => 'Software/Policies/Microsoft/SystemCertificates/Root/Certificates',
);

my %GP_ISOLATION_REGVAL_TYPE = (
    'secedit.system.access.maximumpasswordage'  => 'REG_SZ',
    'secedit.system.access.minimumpasswordage'  => 'REG_SZ',
    'secedit.system.access.lockoutduration'     => 'REG_SZ',
    'secedit.system.access.lockoutbadcount'     => 'REG_SZ',
);

use constant GP_REG_FILE_CURRENT   => 'Registry.pol';
use constant GP_REG_FILE_PREVIOUS  => 'Previous.pol';
use constant GP_REG_FILE_LOCAL     => 'Local.pol';

sub GetRegKey($);
sub GetRegValType($);



sub GetRegKey($)
{
    my ($regval) = $_[0];

    defined($regval) or return undef;

    return $GP_ISOLATION_REGKEY{$regval};
}

sub GetRegValType($)
{
    my ($regval) = $_[0];

    defined($regval) or return undef;

    return $GP_ISOLATION_REGVAL_TYPE{$regval};
}

1;
