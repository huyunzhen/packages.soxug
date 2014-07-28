##############################################################################
#
# Copyright (C) 2004-2014 Centrify Corporation. All rights reserved.
#
# Centrify service module for Mac OS X.
#
##############################################################################

use strict;

package CentrifyDC::GP::MacService;
my $VERSION = '1.0';
require 5.000;

use vars qw(@ISA @EXPORT_OK $MACVER);

use CentrifyDC::GP::Lock;
use CentrifyDC::GP::Plist;
use CentrifyDC::GP::General qw(:debug IsEqual RunCommand ReadFile WriteFile AddElementsIntoArray RemoveElementsFromArray);
use CentrifyDC::GP::Mac qw(:objc GetMacOSVersion);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw($MACVER GetSettingFromLaunchd GetSettingFromHostconfig GetSettingFromSMBConfPlist UpdateLaunchdSetting UpdateHostconfigSetting UpdateSMBConfFile UpdateSMBConfPlist SwitchServiceFirewallSetting);

my $FWHELPER = '/System/Library/PrivateFrameworks/NetworkConfig.framework/Resources/firewalltool';
my $PLIST_FILE_FIREWALL = '/Library/Preferences/com.apple.sharing.firewall.plist';
my $HOSTCONFIG_FILE = '/etc/hostconfig';
my $SMB_CONF_FILE = '/var/db/smb.conf';
my $SMB_CONF_PLIST = '/Library/Preferences/SystemConfiguration/com.apple.smb.server.plist';

# mac 10.6 uses a new file to store launchd setting. old files (/Library/Launch...)
# are only used at first time and will be ignored later.
my $PLIST_FILE_LAUNCHD_OVERRIDE = '/private/var/db/launchd.db/com.apple.launchd/overrides.plist';
my %LAUNCHD_OVERRIDE_ENTRY = (
    afp     => 'com.apple.AppleFileServer',
    eppc    => 'com.apple.AEServer',
    ftp     => 'com.apple.ftpd',
    smb     => 'org.samba.smbd',
    nmb     => 'org.samba.nmbd',
    ssh     => 'com.openssh.sshd',
    www     => 'org.apache.httpd',
    xgrid   => 'com.apple.xgridagentd',
    ntp     => 'org.ntp.ntpd',
);

# hash to map service name to firewall setting key in firewall plist file
my %SERVICE_FIREWALL_ENTRY = (
    afp     => 'Personal File Sharing',
    ard     => 'Apple Remote Desktop',
    eppc    => 'Remote Apple Events',
    ftp     => 'FTP Access',
    ichat   => 'iChat Rendezvous',
    iphoto  => 'iPhoto Rendezvous Sharing',
    itunes  => 'iTunes Music Sharing',
    ntp     => 'Network Time',
    printer => 'Printer Sharing',
    smb     => 'Samba Sharing',
    ssh     => 'Remote Login - SSH',
    www     => 'Personal Web Sharing',
);

# hash to map service name to property in /etc/hostconfig
my %SERVICE_HOSTCONFIG_ENTRY = (
    www     => 'WEBSERVER',
    afp     => 'AFPSERVER',
    ard     => 'ARDAGENT',
    ntp     => 'TIMESYNC',
);

# hash to map service name to property in
# /Library/Preferences/SystemConfiguration/com.apple.smb.server.plist
# and /var/db/smb.conf
my %SERVICE_SMB_ENTRY = (
    smb     => 'disk',
    printer => 'print',
);

# hash to map service name to launchd plist file
my %SERVICE_LAUNCHD_FILE = (
    '10.4'    => {
        eppc    => '/System/Library/LaunchDaemons/eppc.plist',
        ftp     => '/System/Library/LaunchDaemons/ftp.plist',
        smb     => '/System/Library/LaunchDaemons/smbd.plist',
        nmb     => '/System/Library/LaunchDaemons/nmbd.plist',
        ssh     => '/System/Library/LaunchDaemons/ssh.plist',
        xgrid   => '/System/Library/LaunchDaemons/com.apple.xgridagentd.plist',
        printer => '/System/Library/LaunchDaemons/printer.plist',
    },
    '10.5'    => {
        afp     => '/System/Library/LaunchDaemons/com.apple.AppleFileServer.plist',
        eppc    => '/System/Library/LaunchDaemons/eppc.plist',
        ftp     => '/System/Library/LaunchDaemons/ftp.plist',
        smb     => '/System/Library/LaunchDaemons/smbd.plist',
        nmb     => '/System/Library/LaunchDaemons/nmbd.plist',
        ssh     => '/System/Library/LaunchDaemons/ssh.plist',
        www     => '/System/Library/LaunchDaemons/org.apache.httpd.plist',
        xgrid   => '/System/Library/LaunchDaemons/com.apple.xgridagentd.plist',
        printer => '/System/Library/LaunchDaemons/org.cups.cups-lpd.plist',
        ntp     => '/System/Library/LaunchDaemons/org.ntp.ntpd.plist',
    },
    '10.6'    => {
        afp     => '/System/Library/LaunchDaemons/com.apple.AppleFileServer.plist',
        eppc    => '/System/Library/LaunchDaemons/com.apple.eppc.plist',
        ftp     => '/System/Library/LaunchDaemons/ftp.plist',
        smb     => '/System/Library/LaunchDaemons/smbd.plist',
        nmb     => '/System/Library/LaunchDaemons/nmbd.plist',
        ssh     => '/System/Library/LaunchDaemons/ssh.plist',
        www     => '/System/Library/LaunchDaemons/org.apache.httpd.plist',
        xgrid   => '/System/Library/LaunchDaemons/com.apple.xgridagentd.plist',
        printer => '/System/Library/LaunchDaemons/org.cups.cups-lpd.plist',
        ntp     => '/System/Library/LaunchDaemons/org.ntp.ntpd.plist',
    },
    '10.7'    => {
        afp     => '/System/Library/LaunchDaemons/com.apple.AppleFileServer.plist',
        eppc    => '/System/Library/LaunchDaemons/com.apple.eppc.plist',
        ftp     => '/System/Library/LaunchDaemons/ftp.plist',
        smb     => '/System/Library/LaunchDaemons/com.apple.smbd.plist',
        # No this plist on 10.7
        # nmb     => '/System/Library/LaunchDaemons/nmbd.plist',
        ssh     => '/System/Library/LaunchDaemons/ssh.plist',
        www     => '/System/Library/LaunchDaemons/org.apache.httpd.plist',
        xgrid   => '/System/Library/LaunchDaemons/com.apple.xgridagentd.plist',
        printer => '/System/Library/LaunchDaemons/org.cups.cups-lpd.plist',
        ntp     => '/System/Library/LaunchDaemons/org.ntp.ntpd.plist',
    },
    '10.8'    => {
        afp     => '/System/Library/LaunchDaemons/com.apple.AppleFileServer.plist',
        eppc    => '/System/Library/LaunchDaemons/com.apple.eppc.plist',
        ftp     => '/System/Library/LaunchDaemons/ftp.plist',
        smb     => '/System/Library/LaunchDaemons/com.apple.smbd.plist',
        ssh     => '/System/Library/LaunchDaemons/ssh.plist',
        www     => '/System/Library/LaunchDaemons/org.apache.httpd.plist',
        xgrid   => '/System/Library/LaunchDaemons/com.apple.xgridagentd.plist',
        printer => '/System/Library/LaunchDaemons/org.cups.cups-lpd.plist',
        ntp     => '/System/Library/LaunchDaemons/org.ntp.ntpd.plist',
    },
    '10.9'    => {
        afp     => '/System/Library/LaunchDaemons/com.apple.AppleFileServer.plist',
        eppc    => '/System/Library/LaunchDaemons/com.apple.eppc.plist',
        ftp     => '/System/Library/LaunchDaemons/ftp.plist',
        smb     => '/System/Library/LaunchDaemons/com.apple.smbd.plist',
        ssh     => '/System/Library/LaunchDaemons/ssh.plist',
        www     => '/System/Library/LaunchDaemons/org.apache.httpd.plist',
        # no xgrid plist on 10.9
        #xgrid   => '/System/Library/LaunchDaemons/com.apple.xgridagentd.plist',
        printer => '/System/Library/LaunchDaemons/org.cups.cups-lpd.plist',
        ntp     => '/System/Library/LaunchDaemons/org.ntp.ntpd.plist',
    },
);

sub __Init();

sub GetSettingFromLaunchd($);
sub GetSettingFromHostconfig($);
sub GetSettingFromSMBConfPlist($);
sub UpdateLaunchdSetting($$);
sub UpdateHostconfigSetting($$);
sub UpdateSMBConfFile($$);
sub UpdateSMBConfPlist($$);
sub SwitchServiceFirewallSetting($$);

# private
sub _RunLauchctl($$);
sub _CreateDefaultFirewallConfigPlistFile($);



#
# get Mac OS X version, create default firewall plist file if not exist, create
# empty /etc/hostconfig if not exist.
#
#   return: 1       - successful
#           undef   - failed
#
sub __Init()
{
    $MACVER = GetMacOSVersion()->{major};

    if ($MACVER eq '10.3')
    {
        DEBUG_OUT("Mac OS X 10.3 is no longer supported");
        exit(0);
    }

    if ($MACVER eq '10.5')
    {
        $PLIST_FILE_FIREWALL = '/Library/Preferences/com.apple.alf.plist';
    }

    _CreateDefaultFirewallConfigPlistFile($PLIST_FILE_FIREWALL) or return undef;

    if (! -f '/etc/hostconfig')
    {
        DEBUG_OUT("/etc/hostconfig not exist. Create an empty file");
        RunCommand('/usr/bin/touch /etc/hostconfig');
        chmod 0644, '/etc/hostconfig';
    }

    return 1;
}

#
# get status of specified service controlled by launchd. status is ON/OFF
#
#   $_[0]:  service name (for example, ftp)
#
#   return: string  - successful (ON/OFF)
#           undef   - failed
#
sub GetSettingFromLaunchd($)
{
    my $service = $_[0];

    defined($service) or return undef;

    TRACE_OUT("get service [$service] setting from launchd");

    my $setting;
    my $check_individual_plist = 1;

    # for Mac 10.6 and later, need to check the service override file first.
    if ($MACVER ne '10.4' and $MACVER ne '10.5')
    {
        my $service_key = $LAUNCHD_OVERRIDE_ENTRY{$service};
        if (! defined($service_key))
        {
            ERROR_OUT("Cannot find corresponding launchd entry for service [$service]");
            return undef;
        }

        my $plist = CentrifyDC::GP::Plist->new($PLIST_FILE_LAUNCHD_OVERRIDE);
        $plist or return undef;
        $plist->load() or return undef;

        $setting = ToString($plist->get([$service_key, 'Disabled']));
        defined($setting) and $check_individual_plist = 0;
    }

    if ($check_individual_plist)
    {
        my $plist_file = $SERVICE_LAUNCHD_FILE{$MACVER}->{$service};
        if (! defined($plist_file))
        {
            ERROR_OUT("Cannot find corresponding plist file for service [$service]");
            return undef;
        }

        my $plist = CentrifyDC::GP::Plist->new($plist_file);
        $plist or return undef;
        $plist->load() or return undef;

        $setting = ToString($plist->get(['Disabled']));
    }

    if (defined($setting) and $setting eq '1')
    {
        $setting = 'OFF';
    }
    else
    {
        $setting = 'ON';
    }

    TRACE_OUT("service [$service] setting: [$setting]");

    return $setting;
}

#
# get status of specified service controlled by /etc/hostconfig
# (for example, www on 10.4). status is ON/OFF/undef
# if cannot find service setting in /etc/hostconfig, return undef
#
#   $_[0]:  service name (for example, www)
#
#   return: string  - successful (ON/OFF)
#           undef   - failed or no such setting
#
sub GetSettingFromHostconfig($)
{
    my $service = $_[0];

    defined($service) or return undef;

    TRACE_OUT("get service [$service] setting from /etc/hostconfig");

    my $hostconfig_setting = ReadFile($HOSTCONFIG_FILE);
    my $entry = $SERVICE_HOSTCONFIG_ENTRY{$service};

    if (! defined($entry))
    {
        ERROR_OUT("No corresponding hostconfig entry for service [$service]");
        return undef;
    }

    TRACE_OUT("get service [$service] setting from hostconfig: entry: [$entry]");

    $hostconfig_setting =~ m/^$entry=-(YES|NO|AUTOMATIC)-$/m;
    my $setting = $1;

    if (defined($setting))
    {
        $setting = ($setting eq 'YES') ? 'ON' : 'OFF';
        TRACE_OUT("service [$service] setting: [$setting]");
    }
    else
    {
        TRACE_OUT("service [$service] has no setting");
    }

    return $setting;
}

#
# get status of specified service from /Library/Preferences/SystemConfiguration/com.apple.smb.server.plist
# currently it's for smb and printer, but there may be more in the future.
#
#   $_[0]:  service name (smb/printer/...)
#
#   return: string  - successful (ON/OFF)
#           undef   - failed or no such setting
#
sub GetSettingFromSMBConfPlist($)
{
    my $service = $_[0];

    defined($service) or return undef;

    TRACE_OUT("get service [$service] setting from /Library/Preferences/SystemConfiguration/com.apple.smb.server.plist");

    my $setting = 'OFF';
    my $entry = $SERVICE_SMB_ENTRY{$service};

    if (! defined($entry))
    {
        ERROR_OUT("No corresponding SMB entry for service [$service]");
        return undef;
    }

    my $plist = CentrifyDC::GP::Plist->new($SMB_CONF_PLIST);
    $plist or return undef;
    $plist->load() or return undef;

    my $service_list = CreateArrayFromNSArray($plist->get(['EnabledServices']));

    if (defined($service_list))
    {
        foreach my $candidate (@$service_list)
        {
            if ($entry eq $candidate)
            {
                $setting = 'ON';
                last;
            }
        }
    }

    return $setting;
}

#
# update service settings controlled by hostconfig (for example, ftp)
#
# first update firewall setting, then enable/disable service.
# undefined setting will be treated as ON
#
#   $_[0]:  service name (for example, ftp)
#   $_[1]:  setting (ON/OFF/undef)
#
#   return: 1       - successful
#           2       - no need to update
#           undef   - failed
#
sub UpdateLaunchdSetting($$)
{
    my ($service, $setting) = @_;

    if (! defined($service))
    {
        ERROR_OUT("Cannot update launchd controlled service setting: service not specified");
        return undef;
    }

    defined($setting) or return 2;

    DEBUG_OUT("update launchd controlled service setting:  service: [$service]  setting: [$setting]");

    # Mac OS X 10.5 does not require updating firewall setting
    if ($MACVER eq '10.4')
    {
        SwitchServiceFirewallSetting($service, $setting) or return undef;
    }

    my $plist_file = $SERVICE_LAUNCHD_FILE{$MACVER}->{$service};
    if (! defined($plist_file))
    {
        ERROR_OUT("Cannot find corresponding plist file for service [$service]");
        return undef;
    }

    my $action;
    if ($setting eq 'OFF')
    {
        DEBUG_OUT("Disable service [$service]");
        $action = 'unload';
    }
    else
    {
        DEBUG_OUT("Enable service [$service]");
        $action = 'load';
    }

    _RunLauchctl($action, $plist_file) or return undef;

    return 1;
}

#
# update service settings controlled by /etc/hostconfig
# (for example, www on 10.4)
#
# first update firewall setting, then enable/disable service.
#
#   $_[0]:  service name (for example, www)
#   $_[1]:  setting (ON/OFF/undef)
#
#   return: 1       - successful
#           2       - no need to update
#           undef   - failed
#
sub UpdateHostconfigSetting($$)
{
    my ($service, $setting) = @_;

    if (! defined($service))
    {
        ERROR_OUT("Cannot update hostconfig controlled service setting: service not specified");
        return undef;
    }

    my $entry = $SERVICE_HOSTCONFIG_ENTRY{$service};
    if (! defined($entry))
    {
        ERROR_OUT("No corresponding hostconfig entry for service [$service]");
        return undef;
    }

    my $hostconfig_setting = ReadFile($HOSTCONFIG_FILE);
    # convert setting from ON/OFF to YES/NO
    if (defined($setting))
    {
        # Mac OS X 10.5 does not require updating firewall setting
        if ($MACVER eq '10.4')
        {
            SwitchServiceFirewallSetting($service, $setting) or return undef;
        }

        if ($setting eq 'ON')
        {
            DEBUG_OUT("Enable service [$service] in $HOSTCONFIG_FILE");
            $setting = 'YES';
        }
        else
        {
            DEBUG_OUT("Disable service [$service] in $HOSTCONFIG_FILE");
            $setting = 'NO';
        }
        if ($hostconfig_setting =~ m/^$entry=-(YES|NO|AUTOMATIC)-$/m)
        {
            $hostconfig_setting =~ s/^$entry=-(YES|NO|AUTOMATIC)-$/$entry=-$setting-/mg;
        }
        else
        {
            chomp $hostconfig_setting;
            $hostconfig_setting .= "\n$entry=-$setting-\n";
        }
    }
    else
    {
        DEBUG_OUT("Remove service [$service] entry [$entry] in $HOSTCONFIG_FILE");
        $hostconfig_setting =~ s/^$entry=-(YES|NO|AUTOMATIC)-$//mg;
    }

    TRACE_OUT("new $HOSTCONFIG_FILE:\n[$hostconfig_setting]");
    return WriteFile($HOSTCONFIG_FILE, $hostconfig_setting);
}

#
# need to update /var/db/smb.conf for service smb and printer
#
#   $_[0]:  service (smb/printer)
#   $_[1]:  setting (ON/OFF/undef)
#
#   return: 1       - successful
#           2       - no need to update
#           undef   - failed
#
sub UpdateSMBConfFile($$)
{
    my ($service, $setting) = @_;

    defined($service) or return undef;

    defined($setting) or return 2;

    TRACE_OUT("update $SMB_CONF_FILE");

    my $str = ReadFile($SMB_CONF_FILE);
    my $entry = $SERVICE_SMB_ENTRY{$service};
    if (! defined($entry))
    {
        ERROR_OUT("Cannot update $SMB_CONF_FILE: Service [$service] not supported");
        return undef;
    }

    if ($setting eq 'ON')
    {
        $str =~ s/^\s*enable $entry services = no\s*$/enable $entry services = yes/mg;
    }
    else
    {
        $str =~ s/^\s*enable $entry services = yes\s*$/enable $entry services = no/mg;
    }

    return WriteFile($SMB_CONF_FILE, $str);
}

#
# need to update /Library/Preferences/SystemConfiguration/com.apple.smb.server.plist
# for service smb and printer
#
#   $_[0]:  service (smb/printer)
#   $_[1]:  setting (ON/OFF/undef)
#
#   return: 1       - successful
#           2       - no need to update
#           undef   - failed
#
sub UpdateSMBConfPlist($$)
{
    my ($service, $setting) = @_;

    defined($service) or return undef;

    defined($setting) or return 2;

    TRACE_OUT("update $SMB_CONF_PLIST");

    my $entry = $SERVICE_SMB_ENTRY{$service};

    if (! defined($entry))
    {
        ERROR_OUT("Cannot update $SMB_CONF_PLIST: Service [$service] not supported");
        return undef;
    }

    my $plist = CentrifyDC::GP::Plist->new($SMB_CONF_PLIST);
    $plist or return undef;
    $plist->load() or return undef;

    my $service_list = CreateArrayFromNSArray($plist->get(['EnabledServices']));

    if ($setting eq 'ON')
    {
        defined($service_list) or $service_list = [];
        $service_list = AddElementsIntoArray($service_list, $entry);
        defined($service_list) or return undef;
    }
    else
    {
        if (! defined($service_list))
        {
            # no need to remove service
            return 1;
        }
        else
        {
            $service_list = RemoveElementsFromArray($service_list, $entry);
            defined($service_list) or return undef;
        }
    }

    $plist->set(undef, 'EnabledServices', $service_list) or return undef;
    $plist->save() or return undef;

    return 1;
}

#
# switch firewall setting based on service setting
#
# Mac OS X 10.5 does not require updating firewall setting
#
# if service is enabled, enable it in firewall plist and add port to allowed
# port list; if service is disabled, disable it in firewall plist and remove
# port from allowed port list
#
#   $_[0]:  service name (for example, ftp)
#   $_[1]:  setting (ON/OFF/undef)
#
#   return: 1       - successful
#           2       - no need to update
#           undef   - failed
#
sub SwitchServiceFirewallSetting($$)
{
    my ($service, $setting) = @_;

    # we don't know what to do if no setting, so better do nothing
    defined($setting) or return 2;

    if (! defined($service))
    {
        ERROR_OUT("Cannot update firewall setting: service not specified");
        return undef;
    }

    $setting = ($setting eq 'ON') ? 1 : 0;

    TRACE_OUT("update firewall setting:  service: [$service]  setting: [$setting]");

    # get key name in firewall plist file
    my $entry = $SERVICE_FIREWALL_ENTRY{$service};

    # some service don't have firewall entry (for example, nmbd)
    if (! defined($entry))
    {
        TRACE_OUT("No corresponding firewall entry for service [$service]. Skip");
        return 2;
    }

    # load firewall plist file
    my $plist = CentrifyDC::GP::Plist->new($PLIST_FILE_FIREWALL);
    $plist or return undef;
    $plist->load() or return undef;

    my $sys_setting = ToString($plist->get(['firewall', $entry, 'enable']));
    # return if nothing changed
    IsEqual($sys_setting, $setting) and return 2;

    $plist->set(['firewall', $entry], 'enable', $setting, CF_INTEGER) or return undef;

    # add/remove port of the service in port list
    my $port = CreateArrayFromNSArray($plist->get(['firewall', $entry, 'port']));
    my $udpport = CreateArrayFromNSArray($plist->get(['firewall', $entry, 'udpport']));
    my $allports = CreateArrayFromNSArray($plist->get(['allports']));
    my $alludpports = CreateArrayFromNSArray($plist->get(['alludpports']));

    if ($setting)
    {
        DEBUG_OUT("Add ports for service [$service]");
        $allports = AddElementsIntoArray($allports, $port);
        $alludpports = AddElementsIntoArray($alludpports, $udpport);
    }
    else
    {
        DEBUG_OUT("Remove ports for service [$service]");
        $allports = RemoveElementsFromArray($allports, $port);
        $alludpports = RemoveElementsFromArray($alludpports, $udpport);
    }

    $plist->set(undef, 'allports', $allports);
    $plist->set(undef, 'alludpports', $alludpports);

    $plist->save() or return undef;

    TRACE_OUT("reload firewall setting");
    defined(RunCommand($FWHELPER)) or return undef;

    return 1;
}



# >>> PRIVATE >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

#
# run launchctl to load/unlad service
#
#   $_[0]:  action (load/unload)
#   $_[1]:  plist file
#
#   return: 1       - successful
#           undef   - failed
#
sub _RunLauchctl($$)
{
    my ($action, $plist_file) = @_;

    if (! defined($action))
    {
        ERROR_OUT("Cannot run launchctl: action not specified");
        return undef;
    }

    if ($action ne 'load' and $action ne 'unload')
    {
        ERROR_OUT("Cannot run launchctl: unknown action: [$action]");
        return undef;
    }

    my $ret;
    my $cmd = "/bin/launchctl $action -w $plist_file";
    DEBUG_OUT("Run command: [$cmd]");

    my $lock = CentrifyDC::GP::Lock->new($plist_file);
    if (! defined($lock))
    {
        ERROR_OUT("Cannot obtain lock");
        return undef;
    }
    TRACE_OUT(" lockfile: [" . $lock->file() . "]");

    eval
    {
        system "$cmd";
        $ret = $? >> 8;
    };
    if ($@)
    {
        ERROR_OUT("Cannot run command [$cmd]: ($@)");
        $ret = undef;
    }
    else
    {
        TRACE_OUT(" return: [$ret]");
    }

    defined($ret) and $ret = 1;

    return $ret;
}

#
# create the default firewall config plist file if it does not exist
#  10.5:      /Library/Preferences/com.apple.alf.plist
#  10.3/10.4: /Library/Preferences/com.apple.sharing.firewall.plist
#
# default content:
#  10.3: <dict><key>allports</key><array/><key>firewall</key><dict><key>Apple Remote Desktop</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>3283</string><string>5900</string></array><key>row</key><integer>7</integer></dict><key>FTP Access</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>20-21</string><string>*</string></array><key>row</key><integer>4</integer></dict><key>Personal File Sharing</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>548</string><string>427</string></array><key>row</key><integer>0</integer></dict><key>Personal Web Sharing</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>80</string><string>427</string></array><key>row</key><integer>2</integer></dict><key>Printer Sharing</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>631</string><string>515</string></array><key>row</key><integer>6</integer></dict><key>Remote Apple Events</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>3031</string></array><key>row</key><integer>5</integer></dict><key>Remote Login - SSH</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>22</string></array><key>row</key><integer>3</integer></dict><key>Samba Sharing</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>139</string></array><key>row</key><integer>1</integer></dict><key>iChat Rendezvous</key><dict><key>editable</key><integer>1</integer><key>enable</key><integer>0</integer><key>port</key><array><string>5297</string><string>5298</string></array><key>row</key><integer>8</integer></dict><key>iTunes Music Sharing</key><dict><key>editable</key><integer>1</integer><key>enable</key><integer>0</integer><key>port</key><array><string>3689</string></array><key>row</key><integer>9</integer></dict></dict><key>state</key><false/></dict>
#  10.4: <dict><key>allports</key><array/><key>alludpports</key><array><string>123</string></array><key>firewall</key><dict><key>Apple Remote Desktop</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>3283</string><string>5900</string></array><key>row</key><integer>5</integer><key>udpport</key><array><string>3283</string><string>5900</string></array></dict><key>FTP Access</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>21</string></array><key>row</key><integer>4</integer></dict><key>Network Time</key><dict><key>editable</key><integer>1</integer><key>enable</key><integer>1</integer><key>row</key><integer>11</integer><key>udpport</key><array><string>123</string></array></dict><key>Personal File Sharing</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>548</string><string>427</string></array><key>row</key><integer>0</integer></dict><key>Personal Web Sharing</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>80</string><string>427</string><string>443</string></array><key>row</key><integer>2</integer></dict><key>Printer Sharing</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>631</string><string>515</string></array><key>row</key><integer>7</integer></dict><key>Remote Apple Events</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>3031</string></array><key>row</key><integer>6</integer></dict><key>Remote Login - SSH</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>22</string></array><key>row</key><integer>3</integer></dict><key>Samba Sharing</key><dict><key>editable</key><integer>0</integer><key>enable</key><integer>0</integer><key>port</key><array><string>139</string></array><key>row</key><integer>1</integer><key>udpport</key><array><string>137</string><string>138</string></array></dict><key>iChat Rendezvous</key><dict><key>editable</key><integer>1</integer><key>enable</key><integer>0</integer><key>port</key><array><string>5297</string><string>5298</string></array><key>row</key><integer>8</integer></dict><key>iPhoto Rendezvous Sharing</key><dict><key>editable</key><integer>1</integer><key>enable</key><integer>0</integer><key>port</key><array><string>8770</string></array><key>row</key><integer>10</integer></dict><key>iTunes Music Sharing</key><dict><key>editable</key><integer>1</integer><key>enable</key><integer>0</integer><key>port</key><array><string>3689</string></array><key>row</key><integer>9</integer></dict></dict><key>state</key><false/></dict>
#  10.5: <dict><key>applications</key><array/><key>exceptions</key><array><dict><key>path</key><string>/usr/bin/nmblookup</string><key>state</key><integer>0</integer></dict><dict><key>path</key><string>/sbin/mount_ftp</string><key>state</key><integer>0</integer></dict><dict><key>path</key><string>/usr/bin/gdb</string><key>state</key><integer>0</integer></dict><dict><key>path</key><string>/System/Library/Filesystems/ftp.fs/mount_ftp</string><key>state</key><integer>0</integer></dict><dict><key>bundleid</key><string>com.apple.NetAuthAgent</string><key>state</key><integer>0</integer></dict><dict><key>path</key><string>/usr/bin/smbclient</string><key>state</key><integer>0</integer></dict></array><key>explicitauths</key><array><dict><key>path</key><string>/usr/bin/python</string></dict><dict><key>path</key><string>/usr/bin/ruby</string></dict><dict><key>path</key><string>/usr/bin/perl</string></dict><dict><key>path</key><string>/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Commands/java</string></dict><dict><key>path</key><string>/usr/bin/php</string></dict></array><key>firewall</key><dict><key>Apple Remote Desktop</key><dict><key>proc</key><string>AppleVNCServer</string><key>state</key><integer>0</integer></dict><key>FTP Access</key><dict><key>proc</key><string>ftpd</string><key>state</key><integer>0</integer></dict><key>Personal File Sharing</key><dict><key>proc</key><string>AppleFileServer</string><key>state</key><integer>0</integer></dict><key>Personal Web Sharing</key><dict><key>proc</key><string>httpd</string><key>state</key><integer>0</integer></dict><key>Printer Sharing</key><dict><key>proc</key><string>cupsd</string><key>state</key><integer>0</integer></dict><key>Remote Apple Events</key><dict><key>proc</key><string>AEServer</string><key>state</key><integer>0</integer></dict><key>Remote Login - SSH</key><dict><key>proc</key><string>sshd-keygen-wrapper</string><key>state</key><integer>0</integer></dict><key>Samba Sharing</key><dict><key>proc</key><string>smbd</string><key>state</key><integer>0</integer></dict></dict><key>firewallunload</key><integer>0</integer><key>globalstate</key><integer>0</integer><key>loggingenabled</key><integer>0</integer><key>stealthenabled</key><integer>0</integer><key>version</key><string>1.0a11</string></dict>
#
#   $_[0]:  plist filename
#
#   return: 1       - successful
#           2       - file exists
#           undef   - failed
#
sub _CreateDefaultFirewallConfigPlistFile($)
{
    my $file = $_[0];

    if (! defined($file))
    {
        ERROR_OUT("Cannot create default firewall config plist file: file name not specified");
        return undef;
    }

    my $ret = 1;

    (-e $file) and return 2;

    DEBUG_OUT("Create default firewall plist file: [$file]");

    my $default_plist_source;
    if ($MACVER eq '10.3')
    {
        $default_plist_source  = {
            allports => [],
            firewall => {
                'Apple Remote Desktop' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [3283, 5900],
                    row => ToCF(7, CF_INTEGER),
                },
                'FTP Access' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => ['20-21', '*'],
                    row => ToCF(4, CF_INTEGER),
                },
                'Personal File Sharing' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [548, 427],
                    row => ToCF(0, CF_INTEGER),
                },
                'Personal Web Sharing' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [80, 427],
                    row => ToCF(2, CF_INTEGER),
                },
                'Printer Sharing' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [631, 515],
                    row => ToCF(6, CF_INTEGER),
                },
                'Remote Apple Events' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [3031],
                    row => ToCF(5, CF_INTEGER),
                },
                'Remote Login - SSH' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [22],
                    row => ToCF(3, CF_INTEGER),
                },
                'Samba Sharing' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [139],
                    row => ToCF(1, CF_INTEGER),
                },
                'iChat Rendezvous' => {
                    editable => ToCF(1, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [5297, 5298],
                    row => ToCF(8, CF_INTEGER),
                },
                'iTunes Music Sharing' => {
                    editable => ToCF(1, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [3689],
                    row => ToCF(9, CF_INTEGER),
                },
            },
            state => ToCF(0, CF_BOOL), 
        };
    }
    elsif ($MACVER eq '10.4')
    {
        $default_plist_source  = {
            allports => [],
            alludpports => [123],
            firewall => {
                'Apple Remote Desktop' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [3283, 5900],
                    row => ToCF(5, CF_INTEGER),
                    udpport => [3283, 5900],
                },
                'FTP Access' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [21],
                    row => ToCF(4, CF_INTEGER),
                },
                'Network Time' => {
                    editable => ToCF(1, CF_INTEGER), 
                    enable => ToCF(1, CF_INTEGER),
                    row => ToCF(11, CF_INTEGER),
                    udpport => [123],
                },
                'Personal File Sharing' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [548, 427],
                    row => ToCF(0, CF_INTEGER),
                },
                'Personal Web Sharing' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [80, 427, 443],
                    row => ToCF(2, CF_INTEGER),
                },
                'Printer Sharing' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [631, 515],
                    row => ToCF(7, CF_INTEGER),
                },
                'Remote Apple Events' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [3031],
                    row => ToCF(6, CF_INTEGER),
                },
                'Remote Login - SSH' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [22],
                    row => ToCF(3, CF_INTEGER),
                },
                'Samba Sharing' => {
                    editable => ToCF(0, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [139],
                    row => ToCF(1, CF_INTEGER),
                    udpport => [137, 138],
                },
                'iChat Rendezvous' => {
                    editable => ToCF(1, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [5297, 5298],
                    row => ToCF(8, CF_INTEGER),
                },
                'iPhoto Rendezvous Sharing' => {
                    editable => ToCF(1, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [8770],
                    row => ToCF(10, CF_INTEGER),
                },
                'iTunes Music Sharing' => {
                    editable => ToCF(1, CF_INTEGER), 
                    enable => ToCF(0, CF_INTEGER),
                    port => [3689],
                    row => ToCF(9, CF_INTEGER),
                },
            },
            state => ToCF(0, CF_BOOL), 
        };
    }
    else
    {
        $default_plist_source  = {
            applications => [], 
            exceptions => [
                {path => '/usr/bin/nmblookup', state => ToCF(0, CF_INTEGER)}, 
                {path => '/sbin/mount_ftp', state => ToCF(0, CF_INTEGER)}, 
                {path => '/usr/bin/gdb', state => ToCF(0, CF_INTEGER)}, 
                {path => '/System/Library/Filesystems/ftp.fs/mount_ftp', state => ToCF(0, CF_INTEGER)}, 
                {bundleid => 'com.apple.NetAuthAgent', state => ToCF(0, CF_INTEGER)}, 
                {path => '/usr/bin/smbclient', state => ToCF(0, CF_INTEGER)}
            ], 
            explicitauths => [
                {path => '/usr/bin/python'}, 
                {path => '/usr/bin/ruby'}, 
                {path => '/usr/bin/perl'}, 
                {path => '/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Commands/java'}, 
                {path => '/usr/bin/php'}
            ], 
            firewall => {
                'Apple Remote Desktop' => {
                    proc => 'AppleVNCServer',
                    state => ToCF(0, CF_INTEGER)
                }, 
                'FTP Access' => {
                    proc => 'ftpd',
                    state => ToCF(0, CF_INTEGER)
                }, 
                'Personal File Sharing' => {
                    proc => 'AppleFileServer',
                    state => ToCF(0, CF_INTEGER)
                }, 
                'Personal Web Sharing' => {
                    proc => 'httpd',
                    state => ToCF(0, CF_INTEGER)
                }, 
                'Printer Sharing' => {
                    proc => 'cupsd',
                    state => ToCF(0, CF_INTEGER)
                }, 
                'Remote Apple Events' => {
                    proc => 'AEServer',
                    state => ToCF(0, CF_INTEGER)
                }, 
                'Remote Login - SSH' => {
                    proc => 'sshd-keygen-wrapper',
                    state => ToCF(0, CF_INTEGER)
                }, 
                'Samba Sharing' => {
                    proc => 'smbd',
                    state => ToCF(0, CF_INTEGER)
                }, 
            }, 
            firewallunload => ToCF(0, CF_INTEGER), 
            globalstate => ToCF(0, CF_INTEGER), 
            loggingenabled => ToCF(0, CF_INTEGER), 
            stealthenabled => ToCF(0, CF_INTEGER), 
            version => '1.0a11', 
        };
    }

    my $default_plist = CentrifyDC::GP::Plist->new($file);
    $default_plist or return undef;

    if (! $default_plist->loadHash($default_plist_source))
    {
        ERROR_OUT("Cannot load hash into plist");
        return undef;
    }

    if (! $default_plist->save())
    {
        ERROR_OUT("Can not save default plist [$file]");
        return undef;
    }

    return $ret;
}

# <<< PRIVATE <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<



# >>> INIT >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

__Init() or exit(1);

1;
