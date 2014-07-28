##############################################################################
#
# Copyright (C) 2010-2014 Centrify Corporation. All rights reserved.
#
# Centrify 802.1X module for Mac OS X.
#
# This module is for setting 802.1X settings. It updates 802.1X settings
# in current location.
#
#
# The standard procedure to use this module is:
#
#   1. create a new instance;
#   2. add profile(s) or do cleanup;
#   3. save.
#
#
# To create a new Mac8021X:
#
#   my $mac8021x = CentrifyDC::GP::Mac8021X->new();
#
# To create a new Mac8021X for user:
#
#   my $mac8021x = CentrifyDC::GP::Mac8021X->new(user);
#
# To add a system profile:
#
#   my $profile = {
#                   'Wireless Network'  => 'OFFICE01',
#                   'Wireless Security' => 'WPA Enterprise',
#                   'AcceptEAPTypes'    => [PEAP, TTLS,],
#                   'UserName'          => 'johndoe',   (optional)
#                   'Password'          => 'idontknow', (optional)
#                 };
#   $mac8021x->addProfile('System', $profile);
#
# To add a system profile and force update setting:
#
#   $mac8021x->addProfile('System', $profile, 1);
#
# To add a system profile and make sure AirPort is turned on:
#
#   $mac8021x->addProfile('System', $profile, undef, 1);
#
# To add a user profile:
#
#   my $profile = {
#                   'UserDefinedName'   => 'myWireless',
#                   'Wireless Network'  => 'OFFICE01',
#                   'Wireless Security' => 'WPA Enterprise',
#                   'AcceptEAPTypes'    => [PEAP],
#                 };
#   $mac8021x->addProfile('User', $profile);
#
# To add a login window profile:
#
#   my $profile = {
#                   'UserDefinedName'   => 'Office 802.1X',
#                   'Wireless Network'  => 'OFFICE01',
#                   'Wireless Security' => 'WPA Enterprise',
#                   'AcceptEAPTypes'    => [PEAP],
#                 };
#   $mac8021x->addProfile('LoginWindow', $profile);
#
# To clean all 802.1X profiles:
#
#   $mac8021x->clean();
#
# To clean 802.1X system profile:
#
#   $mac8021x->clean('System');
#
# To clean 802.1X login window profiles:
#
#   $mac8021x->clean('LoginWindow');
#
# To clean 802.1X user profiles:
#
#   $mac8021x->clean('User');
#
# To save 802.1X settings:
#
#   $mac8021x->save();
#
# To save 802.1X settings at login time:
#
#   $mac8021x->save(1);
#
##############################################################################

use strict;

package CentrifyDC::GP::Mac8021X;
my $VERSION = '1.0';
require 5.000;

use Data::Dumper qw(Dumper);
use File::Copy qw(copy move);

use CentrifyDC::GP::General qw(:debug IsEmpty IsEqual RunCommand);
use CentrifyDC::GP::Mac qw(:objc GetMacOSVersion);
use CentrifyDC::GP::Plist;

# plist files
my $PLIST_NETWORK = '/Library/Preferences/SystemConfiguration/preferences.plist';
my $PLIST_AIRPORT_PREFERENCES = '/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist';
my $PLIST_USER_PROFILES = 'com.apple.eap.profiles';

# commands
my $SECURITY = '/usr/bin/security';
my $UUIDGEN = '/usr/bin/uuidgen';
my $IFCONFIG = '/sbin/ifconfig';
my $NETWORKSETUP = '/usr/sbin/networksetup';

# strings for keychain
my $KEYCHAIN_ITEM_KIND = '802.1X Password';
my $KEYCHAIN_ITEM_NAME = 'Network Connection (AirPort)';
my $KEYCHAIN_ITEM_COMMENT = '802.1X Password: Network Connection (AirPort)';

use constant {
    TYPE_SYSTEM         => 1,
    TYPE_LOGINWINDOW    => 2,
    TYPE_USER           => 3,
};

my %AUTHENTICATION_METHODS = (
    'TTLS'      => '21',
    'PEAP'      => '25',
    'TLS'       => '13',
    'EAP-FAST'  => '43',
    'LEAP'      => '17',
    'MD5'       => '4',
);

# class public functions
sub new($;$);
sub clean($;$);
sub addProfile($$$;$$);
sub save($;$);

# class private functions
sub _load($);
sub _trace($);
sub _addNetwork($$$);
sub _updatePreferredNetworks($);
sub _updateSystemProfile($);
sub _updateLoginWindowProfiles($);
sub _updateUserProfiles($);
sub _createProfileObject($$$);
sub _createPreferredNetworkObject($$$);
sub _getAirPortSettings($);
sub _getPreferredNetworks($$$);
sub _getSystemProfile($$$);
sub _getLoginWindowProfiles($$$);
sub _getUserProfiles($);
sub _getMacVer($);

# private functions
sub _SimplifyProfile($);
sub _IsEqualProfile($$);
sub _SimplifyNetwork($);
sub _IsEqualNetwork($$);
sub _ConvertEAPType($);
sub _AddKeychainPassword($$$$);

# general purpose functions
sub _GenerateUUID();
sub _GetMacAddress($);
sub _RestartAirPortsIfOn($;$);
sub _StartAirPorts($;$);
sub _StartAirPort($;$);
sub _StopAirPort($;$);



# >>> CLASS PUBLIC >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# create instance
#
#   $_[0]:  self
#   $_[1]:  username (optional, for user GP)
#
#   return: self    - successful
#           0       - no airport device
#           undef   - failed
#
sub new($;$)
{
    my ($invocant, $user) = @_;
    my $class = ref($invocant) || $invocant;

    my $self = {
        macver              => undef,   # Mac version
        user                => $user,   # optional username (for user GP)
        plist               => undef,   # plist instance of /Library/Preferences/SystemConfiguration/preferences.plist
        plist_user          => undef,   # plist instance of user's ~/Library/Preferences/com.apple.eap.profiles.plist

        changed_plist       => undef,   # is /Library/Preferences/SystemConfiguration/preferences.plist changed?
        changed_plist_user  => undef,   # is user's ~/Library/Preferences/com.apple.eap.profiles.plist changed?

        # need to turn on AirPort if certain kind of profile exists?
        TurnOnAirPort       => {
                                User        => undef,
                                System      => undef,
                                LoginWindow => undef,
                               },

        # clean up specified profile?
        CleanUp             => {
                                User        => undef,
                                System      => undef,
                                LoginWindow => undef,
                               },

        CurrentLocation     => undef,   # current location ID
        Locations           => undef,   # array reference of location settings, including system/loginwindow profiles and preferred networks
        AirPort             => undef,   # hash reference of AirPort hardware setting (MAC address)
        UserProfiles        => undef,   # array reference of current user profiles
        KeychainItems       => undef,   # array reference of user/password that need to be added into keychain
        PreferredNetworks   => undef,   # array reference of preferred networks that are used by 802.1X settings
        NewProfiles         => undef,   # hash reference of new profiles specified in GP
    };

    bless($self, $class);

    if (! _load($self))
    {
        ERROR_OUT("Cannot load 802.1X settings");
        return undef;
    }

    if (IsEmpty($self->{AirPort}))
    {
        TRACE_OUT("No AirPort device. Skip 802.1X setting");
        return 0;
    }

    return $self;
}

#
# cleanup 802.1X profile(s)
#
#   $_[0]:  self
#   $_[1]:  type (User|LoginWindow|System) (if omitted, cleanup all 802.1X profiles
#
#   return: 1       - successful
#           undef   - failed
#
sub clean($;$)
{
    my ($self, $type) = @_;

    defined($self) or return undef;

    if (defined($type))
    {
        if ($type ne 'User' and $type ne 'LoginWindow' and $type ne 'System')
        {
            ERROR_OUT("Cannot cleanup profile: unknown profile type $type");
            return undef;
        }
        else
        {
            DEBUG_OUT("Cleanup $type profiles");
            $self->{CleanUp}{$type} = 1;
        }
    }
    else
    {
        DEBUG_OUT("Clean up all wireless 802.1X settings");

        $self->{CleanUp}{User}          = 1;
        $self->{CleanUp}{LoginWindow}   = 1;
        $self->{CleanUp}{System}        = 1;
    }

    return 1;
}

#
# add a 802.1X profile
#
#   $_[0]:  self
#   $_[1]:  profile type (System|LoginWindow|User)
#   $_[2]:  hash reference of profile setting
#               => {
#                       UserDefinedName     => profile name (ignored by system profile)
#                       Wireless Network    => network SSID
#                       Wireless Security   => security type (WPA Enterprise|WPA2 Enterprise|802.1X WEP)
#                       AcceptEAPTypes      => [
#                                                   PEAP,
#                                                   TTLS,
#                                                   ...
#                                               ]
#                       UserName            => username (optional)
#                       Password            => password (optional)
#                   }
#   $_[3]:  force update (1 means the profile will be updated no matter it exists or not)
#   $_[4]:  turn on AirPort (1 means turn on AirPort, others mean leave current status unchanged)
#
#   return: 1       - successful
#           undef   - failed
#
sub addProfile($$$;$$)
{
    my ($self, $type, $hash_input, $force, $airporton) = @_;

    defined($self) or return undef;

    if (! defined($type))
    {
        ERROR_OUT("Cannot add profile: profile type not defined");
        return undef;
    }
    if ($type ne 'User' and $type ne 'LoginWindow' and $type ne 'System')
    {
        ERROR_OUT("Cannot add profile: unknown profile type $type");
        return undef;
    }
    if (! defined($hash_input))
    {
        ERROR_OUT("Cannot add profile: profile setting not defined");
        return undef;
    }
    if (ref($hash_input) ne 'HASH')
    {
        ERROR_OUT("Cannot add profile: profile setting incorrect");
        return undef;
    }

    my $hash = {};
    $hash->{UserDefinedName} = $hash_input->{UserDefinedName};
    $hash->{'Wireless Network'} = $hash_input->{'Wireless Network'};
    $hash->{'Wireless Security'} = $hash_input->{'Wireless Security'};
    $hash->{UserName} = $hash_input->{UserName};
    $hash->{Password} = $hash_input->{Password};
    $hash->{AcceptEAPTypes} = _ConvertEAPType($hash_input->{AcceptEAPTypes});
    $hash->{ForceUpdate} = $force;

    if ($type ne 'System' and ! defined($hash->{UserDefinedName}))
    {
        ERROR_OUT("Cannot add profile: profile name not defined");
        return undef;
    }
    if (! defined($hash->{'Wireless Network'}))
    {
        ERROR_OUT("Cannot add profile: network SSID not defined");
        return undef;
    }
    if (! defined($hash->{'Wireless Security'}))
    {
        ERROR_OUT("Cannot add profile: security type  not defined");
        return undef;
    }

    if (! defined($hash->{AcceptEAPTypes}))
    {
        ERROR_OUT("Cannot add profile: fail to convert EAP type");
        return undef;
    }

    DEBUG_OUT("Add profile:  type: [$type]  name: [$hash->{UserDefinedName}]  SSID: [$hash->{'Wireless Network'}]  Security Type: [$hash->{'Wireless Security'}]");

    # there's only 1 system profile, so use hash directly instead of pushing
    # into an array
    if ($type eq 'System')
    {
        $self->{NewProfiles}{$type} = $hash;
    }
    else
    {
        push(@{$self->{NewProfiles}{$type}}, $hash);
    }

    if ($airporton)
    {
        $self->{TurnOnAirPort}{$type} = 1;
    }

    if (! _addNetwork($self, $hash->{'Wireless Network'}, $hash->{'Wireless Security'}))
    {
        ERROR_OUT("Cannot add profile: cannot add network");
        return undef;
    }

    return 1;
}

#
# save settings
#
# update plist files. if setting changed, restart AirPort. if setting exists,
# start AirPort.
#
#   $_[0]:  self
#   $_[1]:  is it login time?
#
#   return: 1       - successful
#           undef   - failed
#
sub save($;$)
{
    my ($self, $is_login) = @_;

    defined($self) or return undef;

    # we already have all the required data, now update the plist objects.
    TRACE_OUT("Save 802.1X settings");

    if (defined($self->{user}))
    {
        if (! _updateUserProfiles($self))
        {
            ERROR_OUT("Cannot update user profiles");
            return undef;
        }
    }
    else
    {
        if (! _updateSystemProfile($self))
        {
            ERROR_OUT("Cannot update system profile");
            return undef;
        }
        if (! _updateLoginWindowProfiles($self))
        {
            ERROR_OUT("Cannot update login window profiles");
            return undef;
        }
    }

    if (! _updatePreferredNetworks($self))
    {
        ERROR_OUT("Cannot update preferred networks");
        return undef;
    }

    IsEmpty($self->{NewProfiles}) and delete($self->{NewProfiles});
    IsEmpty($self->{PreferredNetworks}) and delete($self->{PreferredNetworks});

    $self->_trace();

    # add keychain password
    foreach my $item(@{$self->{KeychainItems}})
    {
        _AddKeychainPassword($item->{type}, $item->{user}, $item->{password}, $item->{uuid}) or return undef;
    }

    # update /Library/Preferences/SystemConfiguration/preferences.plist
    if ($self->{changed_plist})
    {
        my $file_original = $self->{plist}->filename();
        my $file_backup = $file_original . '.pre_8021x';
        DEBUG_OUT("Backup $file_original to $file_backup");
        if (! copy($file_original, $file_backup))
        {
            ERROR_OUT("Cannot backup $file_original to $file_backup");
            return undef;
        }
        if (! $self->{plist}->save())
        {
            ERROR_OUT("Cannot save $file_original. restore from $file_backup");
            move($file_backup, $file_original);
            return undef;
        }
        else
        {
            unlink($file_backup);
        }
    }

    # update user's ~/Library/Preferences/com.apple.eap.profiles.plist
    if ($self->{changed_plist_user})
    {
        my $file_original = $self->{plist_user}->filename();
        if (IsEmpty($self->{NewProfiles}{User}))
        {
            unlink($file_original);
        }
        else
        {
            my $do_backup = 0;
            (-f $file_original) and $do_backup = 1;
            my $file_backup = $file_original . '.pre_8021x';

            if ($do_backup)
            {
                DEBUG_OUT("Backup $file_original to $file_backup");
                if (! copy($file_original, $file_backup))
                {
                    ERROR_OUT("Cannot backup $file_original to $file_backup");
                    return undef;
                }
            }
            if (! $self->{plist_user}->save())
            {
                ERROR_OUT("Cannot save $file_original");
                if ($do_backup)
                {
                    DEBUG_OUT("Restore $file_original from $file_backup");
                    move($file_backup, $file_original);
                }
                return undef;
            }
            else
            {
                unlink($file_backup);
            }
        }
    }

    my @array_nics = keys %{$self->{AirPort}};

    my $do_restart = 0;
    if ($is_login)
    {
        if ($self->_getMacVer() eq '10.5')
        {
            if (IsEmpty($self->{NewProfiles}{System}))
            {
                if(! IsEmpty($self->{NewProfiles}{LoginWindow}) or ! IsEmpty($self->{NewProfiles}{User}))
                {
                    $do_restart = 1;
                }
            }
        }
    }
    else
    {
        #
        # if setting changed, then:
        #  1. if AirPort is off, leave it as is;
        #  2. if AirPort is on, then restart it to make setting take effect.
        #
        if ($self->{changed_plist} or $self->{changed_plist_user})
        {
            unlink($PLIST_AIRPORT_PREFERENCES);
            $do_restart = 1;
        }
    }

    if ($do_restart)
    {
        DEBUG_OUT("Restart AirPort to apply 802.1X settings");
        if (! _RestartAirPortsIfOn($self->_getMacVer(), \@array_nics))
        {
            ERROR_OUT("Cannot restart AirPort devices");
            return undef;
        }
    }

    #
    # if 802.1X setting exists, then:
    #  1. if $self->{TurnOnAirPort}{$type}, start AirPort;
    #  2. if not $self->{TurnOnAirPort}{$type}, leave AirPort status as is.
    #
    if(! IsEmpty($self->{NewProfiles}))
    {
        my $turnon = 0;
        foreach my $type (qw(System LoginWindow User))
        {
            if (! IsEmpty($self->{NewProfiles}{$type}) and $self->{TurnOnAirPort}{$type})
            {
                $turnon = 1;
                last;
            }
        }

        if ($turnon)
        {
            DEBUG_OUT("Turn on AirPort");
            if (! _StartAirPorts($self->_getMacVer(), \@array_nics))
            {
                ERROR_OUT("Cannot start AirPort devices");
                return undef;
            }
        }
    }

    return 1;
}

# <<< CLASS PUBLIC <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> CLASS PRIVATE >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# load 802.1X settings.
#
# Load /Library/Preferences/SystemConfiguration/preferences.plist to get
# network settings and system/loginwindow profiles.
#
# For user GP, also load user's ~/Library/Preferences/com.apple.eap.profiles.plist
# to get user profiles.
#
#   $_[0]:  self
#
#   return: 1       - successful
#           undef   - failed
#
sub _load($)
{
    my $self = $_[0];

    TRACE_OUT("load 802.1X settings");

    my $plist = CentrifyDC::GP::Plist->new($PLIST_NETWORK);
    if (! $plist)
    {
        ERROR_OUT("Cannot create plist instance for $PLIST_NETWORK");
        return undef;
    }
    if (! $plist->load())
    {
        ERROR_OUT("Cannot load $PLIST_NETWORK");
        return undef;
    }

    $self->{plist} = $plist;

    # convert plist to a Perl hash for easy access
    my $all_settings = CreateHashFromNSDictionary($plist->get([]));
    $self->{dumped_plist} = $all_settings;

    # get current location
    $self->{CurrentLocation} = $all_settings->{CurrentSet};
    $self->{CurrentLocation} =~ s|.*/||;

    # get AirPort device name and MAC address
    $self->{AirPort} = _getAirPortSettings($self);
    IsEmpty($self->{AirPort}) and delete($self->{AirPort});

    # get location settings
    foreach my $key (keys %{$all_settings->{Sets}})
    {
        my $dict_location = $all_settings->{Sets}{$key};
        my $name = $dict_location->{UserDefinedName};

        #
        # for each AirPort device, get its preferred network and 802.1X
        # System/LoginWindow profiles.
        #
        foreach my $nic (keys %{$self->{AirPort}})
        {
            $self->{Locations}{$key}{$nic}{PreferredNetworks} = _getPreferredNetworks($self, $key, $nic);
            $self->{Locations}{$key}{$nic}{SystemProfile} = _getSystemProfile($self, $key, $nic);
            $self->{Locations}{$key}{$nic}{LoginWindowProfiles} = _getLoginWindowProfiles($self, $key, $nic);

            if (! defined($self->{Locations}{$key}{$nic}{PreferredNetworks}))
            {
                ERROR_OUT("Cannot get preferred networks for $nic");
                return undef;
            }
            if (! defined($self->{Locations}{$key}{$nic}{SystemProfile}))
            {
                ERROR_OUT("Cannot get System Profile for $nic");
                return undef;
            }
            if (! defined($self->{Locations}{$key}{$nic}{LoginWindowProfiles}))
            {
                ERROR_OUT("Cannot get Login Window Profiles for $nic");
                return undef;
            }

            # delete empty settings
            IsEmpty($self->{Locations}{$key}{$nic}{PreferredNetworks}) and delete($self->{Locations}{$key}{$nic}{PreferredNetworks});
            IsEmpty($self->{Locations}{$key}{$nic}{SystemProfile}) and delete($self->{Locations}{$key}{$nic}{SystemProfile});
            IsEmpty($self->{Locations}{$key}{$nic}{LoginWindowProfiles}) and delete($self->{Locations}{$key}{$nic}{LoginWindowProfiles});
        }
    }

    # for user GP, get 802.1X User profiles.
    if (defined($self->{user}))
    {
        $self->{UserProfiles} = _getUserProfiles($self);
        if (! defined($self->{UserProfiles}))
        {
            ERROR_OUT("Cannot get User Profiles");
            return undef;
        }
        IsEmpty($self->{UserProfiles}) and delete($self->{UserProfiles});
    }

    return 1;
}

#
# create log entry for 802.1X settings
#
#   $_[0]:  self
#
sub _trace($)
{
    my $self = $_[0];

    my $str = ">>> 802.1X settings >>>\n";
    $str .= "Current Location: $self->{CurrentLocation}\n";
    $str .= "Locations: " . Dumper($self->{Locations});
    $str .= "Airport: " . Dumper($self->{AirPort});
    $str .= "UserProfiles: " . Dumper($self->{UserProfiles});
    $str .= "NewProfiles: " . Dumper($self->{NewProfiles});
    $str .= "CleanUp: " . Dumper($self->{CleanUp});
    $str .= "PreferredNetworks: " . Dumper($self->{PreferredNetworks});
    $str .= "TurnOnAirPort: " . Dumper($self->{TurnOnAirPort});
    $str .= "<<< 802.1X settings <<<";

    TRACE_OUT($str);
}

#
# add a preferred network into $self->{PreferredNetworks}
#
#   $_[0]:  self
#   $_[1]:  network SSID
#   $_[2]:  network security type
#
#   return: 1       - successful
#           undef   - failed
#
sub _addNetwork($$$)
{
    my ($self, $network, $security) = @_;

    defined($self) or return undef;

    if (! defined($network))
    {
        ERROR_OUT("Cannot add preferred network: SSID not defined");
        return undef;
    }
    if (! defined($security))
    {
        ERROR_OUT("Cannot add preferred network: security type not defined");
        return undef;
    }

    my $hash_network = {
        SSID_STR        => $network,
        SecurityType    => $security,
    };

    # only add a network if it's not already added
    my $add = 1;
    foreach my $net (@{$self->{PreferredNetworks}})
    {
        if (IsEqual($net, $hash_network))
        {
            $add = 0;
            last;
        }
    }

    if ($add)
    {
        TRACE_OUT("Add preferred network:  SSID: [$network]  Security Type: [$security]");
        push(@{$self->{PreferredNetworks}}, $hash_network);
    }

    return 1;
}

#
# update preferred networks setting in current location for all AirPort devices
#
# setting is got from $self->{PreferredNetworks} and will be written into
# $self->{plist}
#
# only add network that's not already in the plist
#
#   $_[0]:  self
#
#   return: 1       - successful
#           undef   - failed
#
sub _updatePreferredNetworks($)
{
    my $self = $_[0];

    defined($self) or return undef;

    TRACE_OUT("Update preferred networks");

    foreach my $net (@{$self->{PreferredNetworks}})
    {
        foreach my $nic (keys %{$self->{AirPort}})
        {
            my $add = 1;
            my $current_networks = $self->{Locations}{$self->{CurrentLocation}}{$nic}{PreferredNetworks};
            foreach my $current_net (@$current_networks)
            {
                if (_IsEqualNetwork($current_net, $net))
                {
                    $add = 0;
                    last;
                }
            }
            if ($add)
            {
                my $dict = _createPreferredNetworkObject($self, $net->{SSID_STR}, $net->{SecurityType});
                if (! defined($dict))
                {
                    ERROR_OUT("Cannot create preferred network object");
                    return undef;
                }
                my $r_keys = [
                        'Sets',
                        $self->{CurrentLocation},
                        'Network',
                        'Interface',
                        $nic,
                        'AirPort',
                        'PreferredNetworks',
                ];

                # make sure the network added by GP is on top of network list.
                my $array_current_networks = CreateArrayFromNSArray($self->{plist}->get($r_keys));
                my $array_new_networks = [];
                push(@$array_new_networks, $dict);
                if (! IsEmpty($array_current_networks))
                {
                    push(@$array_new_networks, @$array_current_networks);
                }

                my $r_keys_set = [
                        'Sets',
                        $self->{CurrentLocation},
                        'Network',
                        'Interface',
                        $nic,
                        'AirPort',
                ];
                my $rc = $self->{plist}->set($r_keys_set, 'PreferredNetworks', ToCF($array_new_networks));
                if (! $rc)
                {
                    ERROR_OUT("Cannot set preferred networks");
                    return undef;
                }
                $self->{changed_plist} = 1;
            }
        }
    }

    return 1;
}

#
# update system profile in current location for all AirPort devices
#
# if do cleanup, remove all profile whose 'GroupPolicy' key is true.
# else setting is got from $self->{NewProfiles}{System} and is written
# into $self->{plist}
#
# only update profile if different from current setting
#
#   $_[0]:  self
#
#   return: 1       - successful
#           undef   - failed
#
sub _updateSystemProfile($)
{
    my $self = $_[0];

    defined($self) or return undef;

    my $location = $self->{Locations}{$self->{CurrentLocation}};

    my $array_changed_nic = [];

    # if cleanup, remove GP system profile from all nics.
    if ($self->{CleanUp}{System})
    {
        TRACE_OUT("Cleanup system profile");
        foreach my $nic (keys %$location)
        {
            if (! IsEmpty($location->{$nic}{SystemProfile}) and $location->{$nic}{SystemProfile}{GroupPolicy})
            {
                DEBUG_OUT("Cleanup system profile for device $nic");
                my $r_keys = [
                        'Sets',
                        $self->{CurrentLocation},
                        'Network',
                        'Interface',
                        $nic,
                ];
                my $rc = $self->{plist}->set($r_keys, 'EAPOL', undef);
                if (! $rc)
                {
                    ERROR_OUT("Cannot cleanup system profile for $nic");
                    return undef;
                }

                $self->{changed_plist} = 1;
            }
        }
    }
    else
    {
        if (! defined($self->{NewProfiles}{System}))
        {
            TRACE_OUT("No need to update system profile");
            return 1;
        }

        TRACE_OUT("Update system profile");

        foreach my $nic (keys %$location)
        {
            if (! _IsEqualProfile($location->{$nic}{SystemProfile}, $self->{NewProfiles}{System}))
            {
                (IsEmpty($location->{$nic}{SystemProfile}) and IsEmpty($self->{NewProfiles}{System})) or push(@$array_changed_nic, $nic);
            }
        }

        if (! IsEmpty($array_changed_nic))
        {
            DEBUG_OUT("System profile changed");

            my $dict = _createProfileObject($self, TYPE_SYSTEM, $self->{NewProfiles}{System});
            if (! defined($dict))
            {
                ERROR_OUT("Cannot create system profile object");
                return undef;
            }
            IsEmpty($dict) and $dict = undef;

            foreach my $nic (@$array_changed_nic)
            {
                DEBUG_OUT("Update system profile for device $nic");
                my $r_keys = [
                        'Sets',
                        $self->{CurrentLocation},
                        'Network',
                        'Interface',
                        $nic,
                ];

                my $rc = $self->{plist}->set($r_keys, 'EAPOL', $dict);
                if (! $rc)
                {
                    ERROR_OUT("Cannot update system profile for $nic");
                    return undef;
                }
            }

            $self->{changed_plist} = 1;
        }
    }

    return 1;
}

#
# update login window profiles in current location for all AirPort devices
#
# if do cleanup, remove all profile whose 'GroupPolicy' key is true.
# else setting is got from $self->{NewProfiles}{LoginWinodw} and is written
# into $self->{plist}
#
# only update profiles if different from current setting
#
#   $_[0]:  self
#
#   return: 1       - successful
#           undef   - failed
#
sub _updateLoginWindowProfiles($)
{
    my $self = $_[0];

    defined($self) or return undef;

    my $location = $self->{Locations}{$self->{CurrentLocation}};

    my $array_changed_nic = [];

    # if cleanup, remove GP login window profiles from all nics.
    if ($self->{CleanUp}{LoginWindow})
    {
        foreach my $nic (keys %$location)
        {
            IsEmpty($location->{$nic}{LoginWindowProfiles}) and next;
            foreach my $profile (@{$location->{$nic}{LoginWindowProfiles}})
            {
                if ($profile->{GroupPolicy})
                {
                    my $uuid = $profile->{UniqueIdentifier};
                    my $name = $profile->{UserDefinedName};
                    DEBUG_OUT("Cleanup login window profile $name for device $nic");
                    my $r_keys = [
                            'Sets',
                            $self->{CurrentLocation},
                            'Network',
                            'Interface',
                            $nic,
                            'EAPOL.LoginWindow',
                    ];

                    my $rc = $self->{plist}->set($r_keys, $uuid, undef);
                    if (! $rc)
                    {
                        ERROR_OUT("Cannot cleanup login window profile $name for $nic");
                        return undef;
                    }

                    $self->{changed_plist} = 1;
                }
            }
        }
    }
    else
    {
        if (! defined($self->{NewProfiles}{LoginWindow}))
        {
            TRACE_OUT("No need to update login window profiles");
            return 1;
        }

        TRACE_OUT("Update login window profiles");

        foreach my $nic (keys %$location)
        {
            if (! _IsEqualProfile($location->{$nic}{LoginWindowProfiles}, $self->{NewProfiles}{LoginWindow}))
            {
                (IsEmpty($location->{$nic}{LoginWindowProfiles}) and IsEmpty($self->{NewProfiles}{LoginWindow})) or push(@$array_changed_nic, $nic);
            }
        }

        if (! IsEmpty($array_changed_nic))
        {
            DEBUG_OUT("Login Window profiles changed");

            my $dict_profiles = {};

            foreach my $profile (@{$self->{NewProfiles}{LoginWindow}})
            {
                my $dict = _createProfileObject($self, TYPE_LOGINWINDOW, $profile);
                if (! defined($dict))
                {
                    ERROR_OUT("Cannot create login window profile object");
                    return undef;
                }
                IsEmpty($dict) and $dict = undef;
                defined($dict) and $dict_profiles->{$dict->{UniqueIdentifier}} = $dict;
            }

            foreach my $nic (@$array_changed_nic)
            {
                DEBUG_OUT("Update login window profiles for device $nic");
                my $r_keys = [
                        'Sets',
                        $self->{CurrentLocation},
                        'Network',
                        'Interface',
                        $nic,
                ];

                my $rc = $self->{plist}->set($r_keys, 'EAPOL.LoginWindow', $dict_profiles);
                if (! $rc)
                {
                    ERROR_OUT("Cannot update login window profile for $nic");
                    return undef;
                }
            }

            $self->{changed_plist} = 1;
        }
    }

    return 1;
}

#
# update user profiles
#
# if do cleanup, remove all profiles.
# else setting is got from $self->{NewProfiles}{User} and is written
# into $self->{plist_user}
#
# only update profiles if different from current setting
#
#   $_[0]:  self
#
#   return: 1       - successful
#           undef   - failed
#
sub _updateUserProfiles($)
{
    my $self = $_[0];

    defined($self) or return undef;

    # if cleanup, remove user profiles.
    if ($self->{CleanUp}{User})
    {
        if (! IsEmpty($self->{UserProfiles}))
        {
            DEBUG_OUT("Cleanup user profiles");
            my $dict_profiles = {
                Profiles => undef,
            };

            $self->{plist_user}->loadHash($dict_profiles);

            $self->{changed_plist_user} = 1;
        }
    }
    else
    {
        if (! defined($self->{NewProfiles}{User}) or
            (IsEmpty($self->{UserProfiles}) and IsEmpty($self->{NewProfiles}{User})))
        {
            TRACE_OUT("No need to update user profiles");
            return 1;
        }

        if (! _IsEqualProfile($self->{UserProfiles}, $self->{NewProfiles}{User}))
        {
            DEBUG_OUT("Update user profiles");

            my $array_profiles = [];

            foreach my $profile (@{$self->{NewProfiles}{User}})
            {
                my $dict = _createProfileObject($self, TYPE_USER, $profile);
                if (! defined($dict))
                {
                    ERROR_OUT("Cannot create user profile object");
                    return undef;
                }
                IsEmpty($dict) and $dict = undef;
                defined($dict) and push(@$array_profiles, $dict);
            }

            my $dict_profiles = {
                Profiles => $array_profiles,
            };

            $self->{plist_user}->loadHash($dict_profiles);

            $self->{changed_plist_user} = 1;
        }
    }

    return 1;
}

#
# create a profile object
#
# the profile object has a special binary value 'GroupPolicy' to indicate it's
# created by GP.
#
#   $_[0]:  self
#   $_[1]:  profile type (TYPE_SYSTEM|TYPE_LOGINWINDOW|TYPE_USER)
#   $_[2]:  hash reference of profile settings (can be undefined)
#
#   return: hash reference  - profile object
#           undef           - failed
#
sub _createProfileObject($$$)
{
    my ($self, $type, $hash) = @_;

    defined($self) or return undef;

    if (! defined($type))
    {
        ERROR_OUT("Cannot create profile object: profile type not defined");
        return undef;
    }

    TRACE_OUT("Create profile object: type: $type");

    my $dict = {};

    IsEmpty($hash) and return $dict;

    # generate eap setting
    my $array_eap = [];
    foreach my $eap (@{$hash->{AcceptEAPTypes}})
    {
        push(@$array_eap, ToCF($eap, CF_INTEGER));
    }

    # generate uuid
    my $user = $hash->{UserName};
    my $password = $hash->{Password};

    if ($type == TYPE_SYSTEM)
    {
        $dict = {
            'AcceptEAPTypes' => $array_eap,
            'Wireless Network' => $hash->{'Wireless Network'},
            'Wireless Security' => $hash->{'Wireless Security'},
        };
        if (defined($user))
        {
            $dict->{UserName} = $user;
            if (defined($password))
            {
                my $uuid = _GenerateUUID();
                if (! defined($uuid))
                {
                    ERROR_OUT("Cannot create profile object: cannot generate UUID");
                    return undef;
                }
                $dict->{UserPasswordKeychainItemID} = $uuid;
                my $keychain_item = {
                    type        => TYPE_SYSTEM,
                    user        => $user,
                    password    => $password,
                    uuid        => $uuid,
                };

                push(@{$self->{KeychainItems}}, $keychain_item);
            }
        }
    }
    elsif ($type == TYPE_LOGINWINDOW)
    {
        my $uuid = _GenerateUUID();
        if (! defined($uuid))
        {
            ERROR_OUT("Cannot create profile object: cannot generate UUID");
            return undef;
        }
        $dict = {
            'EAPClientConfiguration' => {
                'AcceptEAPTypes' => $array_eap,
            },
            'Wireless Network' => $hash->{'Wireless Network'},
            'Wireless Security' => $hash->{'Wireless Security'},
            'UserDefinedName' => $hash->{'UserDefinedName'},
            'UniqueIdentifier' => $uuid,
        };
    }
    elsif ($type == TYPE_USER)
    {
        my $uuid = _GenerateUUID();
        if (! defined($uuid))
        {
            ERROR_OUT("Cannot create profile object: cannot generate UUID");
            return undef;
        }
        $dict = {
            'EAPClientConfiguration' => {
                'AcceptEAPTypes' => $array_eap,
            },
            'Wireless Network' => $hash->{'Wireless Network'},
            'Wireless Security' => $hash->{'Wireless Security'},
            'UserDefinedName' => $hash->{'UserDefinedName'},
            'UniqueIdentifier' => $uuid,
        };
        if (defined($user))
        {
            $dict->{EAPClientConfiguration}{UserName} = $user;
            if (defined($password))
            {
                $dict->{EAPClientConfiguration}{UserPasswordKeychainItemID} = $uuid;
                my $keychain_item = {
                    type        => TYPE_USER,
                    user        => $user,
                    password    => $password,
                    uuid        => $uuid,
                };

                push(@{$self->{KeychainItems}}, $keychain_item);
            }
        }
    }
    else
    {
        ERROR_OUT("Cannot create profile object: unknown type $type");
        return undef;
    }

    $dict->{GroupPolicy} = ToCF(1, CF_BOOL);

    return $dict;
}

#
# create a preferred network object
#
#   $_[0]:  self
#   $_[1]:  network SSID
#   $_[2]:  network security type
#
#   return: hash reference  - profile object
#           undef           - failed
#
sub _createPreferredNetworkObject($$$)
{
    my ($self, $network, $security) = @_;

    defined($self) or return undef;

    if (! defined($network))
    {
        ERROR_OUT("Cannot create preferred network object: SSID not defined");
        return undef;
    }
    if (! defined($security))
    {
        ERROR_OUT("Cannot create preferred network object: security type not defined");
        return undef;
    }

    TRACE_OUT("Create preferred network object:  SSID: [$network]  Security Type: [$security]");

    my $uuid = _GenerateUUID();
    if (! defined($uuid))
    {
        ERROR_OUT("Cannot create preferred network object: cannot generate UUID");
        return undef;
    }

    my $dict = {
        SSID_STR        => $network,
        SecurityType    => $security,
        'Unique Network ID' => $uuid,
    };

    return $dict;
}

#
# get AirPort settings (MAC address, etc.)
#
#   $_[0]:  self
#
#   return: hash reference  - AirPort settings (empty means no setting)
#           undef           - failed
#
sub _getAirPortSettings($)
{
    my $self = $_[0];

    defined($self) or return undef;

    TRACE_OUT("Get AirPort settings");

    my $airports = {};

    foreach my $key (keys %{$self->{dumped_plist}{NetworkServices}})
    {
        my $service = $self->{dumped_plist}{NetworkServices}{$key};

        my $name = $service->{Interface}{UserDefinedName};
        my $nic = $service->{Interface}{DeviceName};
        my $hardware = $service->{Interface}{Hardware};

        if ($hardware eq 'AirPort')
        {
            $airports->{$nic} = _GetMacAddress($nic);
            if (! defined($airports->{$nic}))
            {
                ERROR_OUT("Cannot get MAC address for $nic");
                return undef;
            }
        }
    }

    return $airports;
}

#
# get preferred networks of specified location/device
#
#   $_[0]:  self
#   $_[1]:  location ID
#   $_[2]:  device name
#
#   return: array reference - preferred networks (empty means no setting)
#           undef           - failed
#
sub _getPreferredNetworks($$$)
{
    my ($self, $location_id, $nic) = @_;

    defined($self) or return undef;

    if (! defined($location_id))
    {
        ERROR_OUT("Cannot get preferred networks: location ID not defined");
        return undef;
    }
    if (! defined($nic))
    {
        ERROR_OUT("Cannot get preferred networks: device not defined");
        return undef;
    }

    TRACE_OUT("Get preferred network:  location ID: [$location_id]  device: [$nic]");

    my $original_array = $self->{dumped_plist}{Sets}{$location_id}{Network}{Interface}{$nic}{AirPort}{PreferredNetworks};

    my $array = [];

    # if no preferred network, return empty array reference.
    if (defined($original_array))
    {
        # only get useful info
        foreach my $network (@$original_array)
        {
            my $hash = {};
            $hash->{SecurityType} = $network->{SecurityType};
            $hash->{SSID_STR} = $network->{SSID_STR};
            $hash->{'Unique Network ID'} = $network->{'Unique Network ID'};
            push(@$array, $hash);
        }
    }

    return $array;
}

#
# get 802.1X system profile of specified location/device
#
#   $_[0]:  self
#   $_[1]:  location ID
#   $_[2]:  device name
#
#   return: hash reference  - system profile (empty means no setting)
#           undef           - failed
#
sub _getSystemProfile($$$)
{
    my ($self, $location_id, $nic) = @_;

    defined($self) or return undef;

    if (! defined($location_id))
    {
        ERROR_OUT("Cannot get system profile: location ID not defined");
        return undef;
    }
    if (! defined($nic))
    {
        ERROR_OUT("Cannot get system profile: device not defined");
        return undef;
    }

    TRACE_OUT("Get system profile:  location ID: [$location_id]  device: [$nic]");

    my $original_hash = $self->{dumped_plist}{Sets}{$location_id}{Network}{Interface}{$nic}{EAPOL};

    my $hash = {};

    # if no setting for specified location/device, return empty array reference.
    if (defined($original_hash))
    {
        # only get useful info
        $hash->{AcceptEAPTypes} = $original_hash->{AcceptEAPTypes};
        $hash->{UserName} = $original_hash->{UserName};
        $hash->{'Wireless Network'} = $original_hash->{'Wireless Network'};
        $hash->{'Wireless Security'} = $original_hash->{'Wireless Security'};
        $hash->{UserPasswordKeychainItemID} = $original_hash->{UserPasswordKeychainItemID};
        $hash->{GroupPolicy} = $original_hash->{GroupPolicy};

        foreach my $key (keys %$hash)
        {
            defined($hash->{$key}) or delete($hash->{$key});
        }
    }

    return $hash;
}

#
# get 802.1X login window profiles of specified location/device
#
#   $_[0]:  self
#   $_[1]:  location ID
#   $_[2]:  device name
#
#   return: array reference - login window profiles (empty means no setting)
#           undef           - failed
#
sub _getLoginWindowProfiles($$$)
{
    my ($self, $location_id, $nic) = @_;

    defined($self) or return undef;

    if (! defined($location_id))
    {
        ERROR_OUT("Cannot get login window profiles: location ID not defined");
        return undef;
    }
    if (! defined($nic))
    {
        ERROR_OUT("Cannot get login window profiles: device not defined");
        return undef;
    }

    TRACE_OUT("Get login window profiles:  location ID: [$location_id]  device: [$nic]");

    my $original_hash = $self->{dumped_plist}{Sets}{$location_id}{Network}{Interface}{$nic}{'EAPOL.LoginWindow'};

    my $array = [];

    # if no setting for specified location/device, return empty array reference.
    if (defined($original_hash))
    {
        # only get useful info
        foreach my $id (keys %$original_hash)
        {
            my $hash = {};
            $hash->{AcceptEAPTypes} = $original_hash->{$id}{EAPClientConfiguration}{AcceptEAPTypes};
            $hash->{UserDefinedName} = $original_hash->{$id}{UserDefinedName};
            $hash->{'Wireless Network'} = $original_hash->{$id}{'Wireless Network'};
            $hash->{'Wireless Security'} = $original_hash->{$id}{'Wireless Security'};
            $hash->{UniqueIdentifier} = $original_hash->{$id}{UniqueIdentifier};
            $hash->{GroupPolicy} = $original_hash->{$id}{GroupPolicy};

            foreach my $key (keys %$hash)
            {
                defined($hash->{$key}) or delete($hash->{$key});
            }

            push(@$array, $hash);
        }
    }

    return $array;
}

#
# get 802.1X user profiles
#
#   $_[0]:  self
#
#   return: array reference - user profiles (empty means no setting)
#           undef           - failed
#
sub _getUserProfiles($)
{
    my $self = $_[0];

    defined($self) or return undef;

    TRACE_OUT("Get user profiles for $self->{user}");

    my $plist = CentrifyDC::GP::Plist->new($PLIST_USER_PROFILES, $self->{user});
    if (! $plist)
    {
        ERROR_OUT("Cannot create plist instance:  user: $self->{user}  plist: $PLIST_USER_PROFILES");
        return undef;
    }
    if (! $plist->load())
    {
        ERROR_OUT("Cannot load plist file:  user: $self->{user}  plist: $PLIST_USER_PROFILES");
        return undef;
    }

    $self->{plist_user} = $plist;

    my $all_settings = CreateHashFromNSDictionary($plist->get([]));

    my $array = [];

    foreach my $profile (@{$all_settings->{Profiles}})
    {
        my $hash = {};
        $hash->{AcceptEAPTypes} = $profile->{EAPClientConfiguration}{AcceptEAPTypes};
        $hash->{UserName} = $profile->{EAPClientConfiguration}{UserName};
        $hash->{UserDefinedName} = $profile->{UserDefinedName};
        $hash->{'Wireless Network'} = $profile->{'Wireless Network'};
        $hash->{'Wireless Security'} = $profile->{'Wireless Security'};
        $hash->{UniqueIdentifier} = $profile->{UniqueIdentifier};

        foreach my $key (keys %$hash)
        {
            defined($hash->{$key}) or delete($hash->{$key});
        }

        push(@$array, $hash);
    }

    return $array;
}

#
# get Mac OS X version and save into $self->{macver}
#
#   $_[0]:  self
#
#   return: string  - Mac OS X version
#           undef   - failed
#
sub _getMacVer($)
{
    my $self = $_[0];

    defined($self) or return undef;

    defined($self->{macver}) or $self->{macver} = GetMacOSVersion()->{major};
    if (! defined($self->{macver}))
    {
        ERROR_OUT("Cannot get Mac OS X version");
        return undef;
    }

    return $self->{macver};
}

# <<< CLASS PRIVATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> PRIVATE >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# simplify a profile (for comparison). return the simplified profile
# (i.e. only contain necessary info. password is not included)
#
#   $_[0]:  hash reference of the original profile
#
#   return: hash reference  - simplified profile
#           undef           - failed
#
sub _SimplifyProfile($)
{
    my $hash = $_[0];

    if (! defined($hash))
    {
        ERROR_OUT("Cannot simplify profile: profile not defined");
        return undef;
    }
    if (ref($hash) ne 'HASH')
    {
        ERROR_OUT("Cannot simplify profile: incorrect profile");
        return undef;
    }

    IsEmpty($hash) and return $hash;

    my $simplified = {};

    $simplified->{AcceptEAPTypes} = $hash->{AcceptEAPTypes};
    $simplified->{UserName} = $hash->{UserName};
    $simplified->{UserDefinedName} = $hash->{UserDefinedName};
    $simplified->{'Wireless Network'} = $hash->{'Wireless Network'};
    $simplified->{'Wireless Security'} = $hash->{'Wireless Security'};
    $simplified->{ForceUpdate} = $hash->{ForceUpdate};

    foreach my $key (keys %$simplified)
    {
        defined($simplified->{$key}) or delete($simplified->{$key});
    }

    return $simplified;
}

#
# compare two profiles (or profile array). only compare the essential setting.
#
#   $_[0]:  hash reference of a profile or array reference of profiles
#   $_[1]:  hash reference of a profile or array reference of profiles
#
#   return: 1       - profiles are equal
#           0       - profiles are different
#           undef   - failed
#
sub _IsEqualProfile($$)
{
    my ($p1, $p2) = @_;

    my $sp1;
    my $sp2;

    my $type_1 = ref($p1);
    my $type_2 = ref($p2);

    IsEqual($type_1, $type_2) or return 0;

    if ($type_1)
    {
        if ($type_1 eq 'HASH')
        {
            $sp1 = _SimplifyProfile($p1);
        }
        elsif ($type_1 eq 'ARRAY')
        {
            foreach my $p (@$p1)
            {
                push(@$sp1, _SimplifyProfile($p));
            }
        }
        else
        {
            ERROR_OUT("Cannot compare profiles: incorrect type $type_1");
            return undef;
        }
    }
    else
    {
        $sp1 = $p1;
    }

    if ($type_2)
    {
        if ($type_2 eq 'HASH')
        {
            $sp2 = _SimplifyProfile($p2);
        }
        elsif ($type_2 eq 'ARRAY')
        {
            foreach my $p (@$p2)
            {
                push(@$sp2, _SimplifyProfile($p));
            }
        }
        else
        {
            ERROR_OUT("Cannot compare profiles: incorrect type $type_2");
            return undef;
        }
    }
    else
    {
        $sp2 = $p2;
    }

    return IsEqual($sp1, $sp2);
}

#
# simplify a preferred network (for comparison). return the simplified network
#
#   $_[0]:  hash reference of the original network
#
#   return: hash reference  - simplified network
#           undef           - failed
#
sub _SimplifyNetwork($)
{
    my $hash = $_[0];

    if (! defined($hash))
    {
        ERROR_OUT("Cannot simplify preferred network: network not defined");
        return undef;
    }
    if (ref($hash) ne 'HASH')
    {
        ERROR_OUT("Cannot simplify preferred network: incorrect network");
        return undef;
    }

    IsEmpty($hash) and return $hash;

    my $simplified = {};

    $simplified->{SecurityType} = $hash->{SecurityType};
    $simplified->{SSID_STR} = $hash->{SSID_STR};

    foreach my $key (keys %$simplified)
    {
        defined($simplified->{$key}) or delete($simplified->{$key});
    }

    return $simplified;
}

#
# compare two preferred networks. only compare the essential setting.
#
#   $_[0]:  hash reference of a preferred network
#   $_[1]:  hash reference of a preferred network
#
#   return: 1       - networks are equal
#           0       - networks are different
#           undef   - failed
#
sub _IsEqualNetwork($$)
{
    my ($n1, $n2) = @_;

    my $sn1;
    my $sn2;

    my $type_1 = ref($n1);
    my $type_2 = ref($n2);

    IsEqual($type_1, $type_2) or return 0;

    $sn1 = _SimplifyNetwork($n1);
    $sn2 = _SimplifyNetwork($n2);

    return IsEqual($sn1, $sn2);
}

#
# convert EAP type from string to integer (for example PEAP is 25) in an
# array reference
#
#   $_[0]:  array reference of string EAP types
#
#   return: array reference - array reference of integer EAP types
#           undef           - failed
#
sub _ConvertEAPType($)
{
    my $array_old = $_[0];

    if (! defined($array_old))
    {
        ERROR_OUT("Cannot convert EAP type: EAP array not defined.");
        return undef;
    }
    if (ref($array_old) ne 'ARRAY')
    {
        ERROR_OUT("Cannot convert EAP type: not an array");
        return undef;
    }

    my $array = [];
    foreach my $eaptype (@$array_old)
    {
        my $type = $AUTHENTICATION_METHODS{$eaptype};
        if (! defined($type))
        {
            ERROR_OUT("Cannot convert EAP type: incorrect type $eaptype");
            return undef;
        }
        push(@$array, $type);
    }

    return $array;
}

#
# add a keychain password
#
# for system/loginwindow profile, add keychain password into system keychain
#
# TODO:
# for user profile, should add keychain password into user's login keychain,
# but we don't know how to add it, so just add into system keychain. however,
# user profile won't work with password in system keychain.
#
#   $_[0]:  profile type (TYPE_SYSTEM|TYPE_LOGINWINDOW|TYPE_USER)
#   $_[1]:  user
#   $_[2]:  password
#   $_[3]:  UUID
#
#   return: 1       - successful
#           undef   - failed
#
sub _AddKeychainPassword($$$$)
{
    my ($type, $user, $password, $uuid) = @_;

    if (! defined($type))
    {
        ERROR_OUT("Cannot add keychain password: type not defined");
    }
    if (! defined($user))
    {
        ERROR_OUT("Cannot add keychain password: user not defined");
    }
    if (! defined($password))
    {
        ERROR_OUT("Cannot add keychain password: password not defined");
    }
    if (! defined($uuid))
    {
        ERROR_OUT("Cannot add keychain password: service UUID not defined");
    }

    if ($type == TYPE_USER)
    {
        DEBUG_OUT("Add user keychain password");

        my $cmd = "$SECURITY add-generic-password -a '$user' -s '$uuid' -p '$password' -D '$KEYCHAIN_ITEM_KIND' -l '$user' -j '$KEYCHAIN_ITEM_COMMENT' -U -A";

        my $ret = RunCommand($cmd);
        if (! defined($ret) or $ret ne '0')
        {
            ERROR_OUT("Cannot add system keychain password");
            return undef;
        }
    }
    else
    {
        DEBUG_OUT("Add system keychain password");

        my $cmd = "$SECURITY add-generic-password -a '$user' -s '$uuid' -p '$password' -D '$KEYCHAIN_ITEM_KIND' -l '$KEYCHAIN_ITEM_NAME' -j '$KEYCHAIN_ITEM_COMMENT' -U -A";

        my $ret = RunCommand($cmd);
        if (! defined($ret) or $ret ne '0')
        {
            ERROR_OUT("Cannot add system keychain password");
            return undef;
        }
    }

    return 1;
}

# <<< PRIVATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> GENERIC >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# These functions are independent of 802.1X settings.

#
# generate a UUID
#
#   return: string  - UUID
#           undef   - failed
#
sub _GenerateUUID()
{
    TRACE_OUT("Generate an UUID");

    my ($ret, $uuid) = RunCommand($UUIDGEN);
    if (! defined($ret) or $ret ne '0')
    {
        ERROR_OUT("Cannot generate UUID");
        return undef;
    }

    chomp($uuid);

    return $uuid;
}

#
# get MAC address of specified network device using ifconfig command
#
#   $_[0]:  device name (for example en0)
#
#   return: string  - MAC address, in XX:XX:XX:XX:XX:XX format
#           undef   - failed
#
sub _GetMacAddress($)
{
    my $nic = $_[0];

    if (! defined($nic) or $nic eq '')
    {
        ERROR_OUT("Cannot get MAC address: device name not specified");
        return undef;
    }

    TRACE_OUT("Get Mac address of $nic");

    my $cmd = "$IFCONFIG '$nic' ether";
    my ($ret, $data) = RunCommand($cmd);
    if (! defined($ret) or ! defined($data))
    {
        ERROR_OUT("Cannot get MAC address of [$nic]");
        return undef;
    }

    $data =~ m/ether\s*(\S+)/gs;
    my $MAC = $1;

    # verify MAC format
    if ($MAC =~ m/^([0-9a-f][0-9a-f]:){5}[0-9a-f][0-9a-f]$/)
    {
        TRACE_OUT("MAC address of $nic: [$MAC]");
    }
    else
    {
        ERROR_OUT("Incorrect MAC address: $MAC");
        $MAC = undef;
    }

    return $MAC;
}

#
# restart AirPort devices if already powered on
#
# Mac 10.6 can specify the device name, 10.5 can't.
#  10.5: networksetup -setairportpower on
#  10.6: networksetup -setairportpower en1 on
#
#   $_[0]:  Mac version
#   $_[1]:  array reference of device name (optional, only used on Mac 10.6)
#
#   return: 1       - successful
#           undef   - failed
#
sub _RestartAirPortsIfOn($;$)
{
    my ($macver, $nics) = @_;

    if (! defined($macver))
    {
        ERROR_OUT("Cannot restart AirPort devices: Mac OS X version undefined");
        return undef;
    }

    DEBUG_OUT("Restart AirPort devices if already on");

    if ($macver eq '10.5')
    {
        my $is_on = _IsAirPortOn($macver);
        if (! defined($is_on))
        {
            ERROR_OUT("Cannot get AirPort power status");
            return undef;
        }
        if ($is_on)
        {
            if (! _StopAirPort($macver))
            {
                ERROR_OUT("Cannot stop AirPort.");
                return undef;
            }
            if (! _StartAirPort($macver))
            {
                ERROR_OUT("Cannot start AirPort.");
                return undef;
            }
        }
    }
    else
    {
        if (defined($nics) and ! IsEmpty($nics))
        {
            foreach my $nic (@$nics)
            {
                my $is_on = _IsAirPortOn($macver, $nic);
                if (! defined($is_on))
                {
                    ERROR_OUT("Cannot get AirPort device $nic power status");
                    return undef;
                }
                if ($is_on)
                {
                    if (! _StopAirPort($macver, $nic))
                    {
                        ERROR_OUT("Cannot stop AirPort device $nic.");
                        return undef;
                    }
                    if (! _StartAirPort($macver, $nic))
                    {
                        ERROR_OUT("Cannot start AirPort device $nic.");
                        return undef;
                    }
                }
            }
        }
        else
        {
            ERROR_OUT("Cannot restart AirPort devices: device not specified");
            return undef;
        }
    }

    return 1;
}

#
# start AirPort devices if off
#
# Mac 10.6 can specify the device name, 10.5 can't.
#  10.5: networksetup -setairportpower off
#  10.6: networksetup -setairportpower en1 off
#
#   $_[0]:  Mac version
#   $_[1]:  array reference of device name (optional, only used on Mac 10.6)
#
#   return: 1       - successful
#           undef   - failed
#
sub _StartAirPorts($;$)
{
    my ($macver, $nics) = @_;

    if (! defined($macver))
    {
        ERROR_OUT("Cannot restart AirPort devices: Mac OS X version undefined");
        return undef;
    }

    DEBUG_OUT("Start AirPort devices if off");

    if ($macver eq '10.5')
    {
        my $is_on = _IsAirPortOn($macver);
        if (! defined($is_on))
        {
            ERROR_OUT("Cannot get AirPort power status");
            return undef;
        }
        if (! $is_on)
        {
            if (! _StartAirPort($macver))
            {
                ERROR_OUT("Cannot start AirPort.");
                return undef;
            }
        }
    }
    else
    {
        if (defined($nics) and ! IsEmpty($nics))
        {
            foreach my $nic (@$nics)
            {
                my $is_on = _IsAirPortOn($macver, $nic);
                if (! defined($is_on))
                {
                    ERROR_OUT("Cannot get AirPort device $nic power status");
                    return undef;
                }
                if (! $is_on)
                {
                    if (! _StartAirPort($macver, $nic))
                    {
                        ERROR_OUT("Cannot start AirPort device $nic.");
                        return undef;
                    }
                }
            }
        }
        else
        {
            ERROR_OUT("Cannot restart AirPort devices: device not specified");
            return undef;
        }
    }

    return 1;
}

#
# start specified AirPort device
#
# Mac 10.6 can specify the device name, 10.5 can't.
#  10.5: networksetup -setairportpower on
#  10.6: networksetup -setairportpower en1 on
#
#   $_[0]:  Mac version
#   $_[1]:  device name (optional, only used on Mac 10.6)
#
#   return: 1       - successful
#           undef   - failed
#
sub _StartAirPort($;$)
{
    my ($macver, $nic) = @_;

    if ($macver eq '10.5')
    {
        DEBUG_OUT("Turn on AirPort");

        my $cmd = "$NETWORKSETUP -setairportpower on";
        my $ret = RunCommand($cmd);
        if (! defined($ret) or $ret ne '0')
        {
            ERROR_OUT("Cannot turn on AirPort");
            return undef;
        }
            DEBUG_OUT("AirPort turned on");
    }
    else
    {
        if (defined($nic) and $nic ne '')
        {
            DEBUG_OUT("Turn on AirPort device $nic");
            my $cmd = "$NETWORKSETUP -setairportpower '$nic' on";
            my $ret = RunCommand($cmd);
            if (! defined($ret) or $ret ne '0')
            {
                ERROR_OUT("Cannot turn on AirPort device $nic");
                return undef;
            }
            DEBUG_OUT("AirPort device $nic turned on");
        }
        else
        {
            ERROR_OUT("Cannot turn on AirPort: device not specified");
            return undef;
        }
    }

    return 1;
}

#
# stop specified AirPort device
#
# Mac 10.6 can specify the device name, 10.5 can't.
#  10.5: networksetup -setairportpower off
#  10.6: networksetup -setairportpower en1 off
#
#   $_[0]:  Mac version
#   $_[1]:  device name (optional, only used on Mac 10.6)
#
#   return: 1       - successful
#           undef   - failed
#
sub _StopAirPort($;$)
{
    my ($macver, $nic) = @_;

    if ($macver eq '10.5')
    {
        DEBUG_OUT("Turn off AirPort");

        my $cmd = "$NETWORKSETUP -setairportpower off";
        my $ret = RunCommand($cmd);
        if (! defined($ret) or $ret ne '0')
        {
            ERROR_OUT("Cannot turn off AirPort");
            return undef;
        }
        DEBUG_OUT("AirPort turned off");
    }
    else
    {
        if (defined($nic) and $nic ne '')
        {
            DEBUG_OUT("Turn off AirPort device $nic");
            my $cmd = "$NETWORKSETUP -setairportpower '$nic' off";
            my $ret = RunCommand($cmd);
            if (! defined($ret) or $ret ne '0')
            {
                ERROR_OUT("Cannot turn off AirPort device $nic");
                return undef;
            }
            DEBUG_OUT("AirPort device $nic turned off");
        }
        else
        {
            ERROR_OUT("Cannot turn off AirPort: device not specified");
            return undef;
        }
    }

    return 1;
}

#
# check if AirPort is turned on
#
# Mac 10.6 can specify the device name, 10.5 can't.
#  10.5: networksetup -getairportpower
#  10.6: networksetup -getairportpower en1
#
#   $_[0]:  Mac version
#   $_[1]:  device name (optional, only used on Mac 10.6)
#
#   return: 1       - on
#           0       - off
#           undef   - failed
#
sub _IsAirPortOn($;$)
{
    my ($macver, $nic) = @_;

    my $status = 0;

    my $cmd;
    if ($macver eq '10.5')
    {
        $cmd = "$NETWORKSETUP -getairportpower";
    }
    else
    {
        if (defined($nic))
        {
            $cmd = "$NETWORKSETUP -getairportpower '$nic'";
        }
        else
        {
            ERROR_OUT("Cannot get AirPort power status: device not specified");
            return undef;
        }
    }

    my ($ret, $data) = RunCommand($cmd);
    if (! defined($ret) or $ret ne '0')
    {
        ERROR_OUT("Cannot get AirPort power status");
        return undef;
    }
    else
    {
        $status = ($data =~ m/:\s*On/) ? 1 : 0;
    }

    return $status;
}


# <<< GENERIC <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

1;
