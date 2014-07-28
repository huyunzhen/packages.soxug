package provide ade_lib 1.0

proc create_aduser {dn upn sam pw {dname {}} {gname {}} {spn {}} {gecos {}}} {
    new_object $dn;
    sof userPrincipalName $upn;
    sof sAMAccountName $sam;
    sof objectClass user;
    sof userAccountControl 514;
    save_object;
    append samAtDomain "$sam@" [domain_from_dn $dn]
    sup $samAtDomain $pw;
    sof userAccountControl 512;
    save_object;
    slo $dn
    if {[string length $dname]} {
        sof displayName $dname
    }
    if {[string length $gname]} {
        sof givenName $gname
    }
    if {[string length $spn]} {
        sof servicePrincipalName $spn
    }
    if {[string length $gecos]} {
        sof gecos $gecos
    }
    svo
}

proc get_user_groups {args} {
    push
    set usage {wrong # args: should be [-dn] [-z] <user dn|user upn>} 
    set getdn [getopt args "-dn"]
    set zone_enable [getopt args "-z"]
    if { [llength $args] != 1 } {
        error $usage
    }
    lassign $args aduser
    set group_dn {}
    set groups {}
    
    if { $zone_enable } {
        foreach g [get_zone_groups] {
            dict set group_dn [string tolower [principal_to_dn $g]] 1
        }
    }

    slo [GetDN $aduser]
    foreach g [gof memberOf] {
        if { $zone_enable && ![dict exists $group_dn [string tolower $g]] } {
            continue
        }
        lappend groups [expr { $getdn ? $g : [dn_to_principal $g] }]
    }
    pop
    return $groups
}

proc get_all_zone_users {args} {
    push
    set getupn [getopt args "-upn"]
    set usage {wrong # args: should be [-upn] <zone dn>}
    if { [llength $args] != 1 } {
        error $usage
    }
    lassign $args zone
    set options ""
    if { $getupn } {
        set options "-upn"
    }

    set users {}
    while { $zone != "" } {
        slz $zone
        foreach u [gzu {*}$options] {
            dict set users [string tolower $u] $u
        }
        set zone [gzf parent]
    }
    pop
    return [dict values $users]
}

proc create_adgroup {dn sam gtype} {
    new_object $dn;
    sof sAMAccountName $sam;
    sof objectClass group;
    switch $gtype {
        "global" {
                sof groupType [expr 0x80000002]
        }
        universal {
                sof groupType [expr 0x80000008]
        }
        local {
                sof groupType [expr 0x80000004]
        }
        default {
            error "invalid group type"
        }
    }

    save_object;
}

proc create_user {ad uname uid gid gecos home shell role} {

    set ztype [gzf type]
    if {$uname ne "-"
            || $uid ne "-"
            || $gid ne "-"
            || $gecos ne "-"
            || $home ne "-"
            || $shell ne "-"} {
        new_zone_user $ad;
        szuf uname $uname;
        szuf uid $uid;
        szuf gid $gid;
        # you cannot set the gecos field on classsic zones, so warn user and continue
        catch { szuf gecos $gecos;}
        szuf home $home;
        szuf shell $shell;
        if {[string match classic* $ztype]} {
            szuf enabled $role
        }
        save_zone_user;
    }
    if {[string match classic* $ztype] eq 0} {
        if {$role ne "-"} {
            if {[string first "+" $ad] == -1} {
                new_role_assignment $ad;
                set_role_assignment_field role $role;
                save_role_assignment;
            }
        }
    }
}

proc lremove {listVariable value} {
    upvar 1 $listVariable var
    set var [lsearch -not -inline -all -nocase $var $value]
}

# merge the lists into one and lsort -unique it.
proc lmerge {args} {
    if {[llength $args] < 1} {
	error "args: lists to be merged and sorted"
    }
    return [lsort -unique [concat {*}$args]]
}

# args: upn/dn
proc GetDN { object } {
    if {[regexp -nocase {(cn|ou|dc)=.+} $object]} {
        return $object
    }
    return [principal_to_dn $object]
}

# args: upn/udn, gpn/gdn.
proc remove_user_from_group {user group} {
    push
    set gdn [GetDN $group]
    set udn [GetDN $user]
    set udom [domain_from_dn $udn]
    set uforest [get_bind_info $udom forest]
    set gdom [domain_from_dn $gdn]
    set gforest [get_bind_info $gdom forest]
    if {$uforest != $gforest} {
         slo $udn
         set sid [gof sid]
         set udn "<SID="
         append udn $sid ">"
    }

    if {[catch {remove_object_value $gdn member $udn} err]} {
        pop
        error "$err"
    }

    pop
}

# args: upn/udn, gpn/gdn.
proc add_user_to_group {user group} {
    push
    set gdn [GetDN $group]
    set udn [GetDN $user]
    if { [string tolower $gdn] == [string tolower $udn] } {
        error "Cannot add $gdn to itself."
    }
    set udom [domain_from_dn $udn]
    set uforest [get_bind_info $udom forest]
    set gdom [domain_from_dn $gdn]
    set gforest [get_bind_info $gdom forest]
    if {$uforest != $gforest} {
        slo $udn
        set sid [gof sid]
        set udn "<SID="
        append udn $sid ">"
    }

    if {[catch {add_object_value $gdn member $udn} err]} {
        pop
        error "$err"
    }
    pop
}

# from/to, in the format of "yr-mon-day hr:min"
proc create_assignment {adg role {from {}} {to {}}} {
    new_role_assignment $adg;
    set_role_assignment_field role $role;
    if {[string length $from]} {
        sraf from [clock scan $from]
    }
    if {[string length $to]} {
        sraf to [clock scan $to]
    }
    save_role_assignment;
}

proc create_group {adg name gid {req {}}} {
    new_zone_group $adg;
    szgf name $name;
    szgf gid $gid;
    if {[string length $req]} {
        szgf required $req
    }
    save_zone_group;
}

#args: nismapname, entries(the list of nismap entries, in the format as 
# the result of get_nis_map)
proc create_nismap {nm entries} {
    new_nis_map $nm 
    save_nis_map 
    select_nis_map $nm 
    foreach entr $entries {
        set nm_key [lindex $entr 0]
        set nm_idx [string last ":" $nm_key ]
        add_map_entry [string range $nm_key 0 [ expr $nm_idx-1 ] ] [ lindex $entr 1 ]
    }
    save_nis_map
}


# Precreate a computer, create an zone computer or machine zone
# It will also create the AD computer object if necessary
# Similar to adjoin --precreate
#
# precreate_computer samaccount@domain ... 
# precreate_computer samaccount@domain ?-ad? ?-scp? ?-czone? ?-all? ?-container rdn? ?-dnsname dnsname? ?-trustee upn1? ?-trustee upn2? ...
#
# samaccount@domain contains both the computer name and the domain to join
# samaccount should be form of <computer>$, for example, the first argument can be paul-pc$pual.test
# Scp or computer zone will be created in current select zone, so need select_zone first
#
# computer:     computer account name
# Optional Arguments:
# -ad           (optional) Create AD computer object
#                          It will not create AD computer object if the computer object exists
# -scp          (optional) Precreate create zone computer(extension object)
#                          It will create AD computer object if not present
# -czone        (optional) Create computer zone
# -all          (optional) Create all above
#                          In addition, If no action specified, create ad and scp by default
# -container <rdn>
#               (optional) Subtree to create AD object
#                          This option takes effect only when a new AD computer object need to be created
#                          If empty, default to CN=Computers,DC=<domain>
# -dnsname <dnsname>
#               (optional) specified dns name
#                          If empty, derive the dnsname from samaccount name and domain
# -trustee <upn>
#               (optional) Arbitrary trustees who can use the precreated computers
#                          Note this option can be set multiple times
# Example:  Precreate computer "redhat" at default zone in centrify.com 
#           select_zone {CN=default,CN=Zones,DC=centrify,DC=com}
#           precreate_computer redhat$@centrify.com -trustee foo@centrify.com -trustee bar@child.centrify.com
proc precreate_computer {upn args} {
    set usage "precreate_computer samaccount@domain"
    set usage "$usage ?-ad? ?-scp? ?-czone? ?-all? ?-container rdn? ?-dnsname dnsname? ?-trustee upn1? ?-trustee upn2? ...";

    # Resolve samaccount@domain
    set dotIndex [string last "$@" $upn]
    set len [string length $upn]
    if {$dotIndex <= 0 || $dotIndex >= [expr $len-2]} {
        error "Computer name should be: samaccount@domain, and the samaccount should end with $"
    }
    set computer [string range $upn 0 [expr $dotIndex-1]]
    set domain [string range $upn [expr $dotIndex+2] $len]

    set base [dn_from_domain $domain]
    set sam "$computer\$"
    set pw [string tolower [string range $computer 0 13]]

    set createAD ""
    set createScp ""
    set createZone ""
    set explicitlyCreateAD ""
    set explicitlyCreateZone ""
    set trustees ""
    set container ""
    set dnsname ""
    set argCount [llength $args]
    for {set idx 0} {$idx < $argCount} {incr idx} {
        set flag [lindex $args $idx]
        switch -glob -- $flag {
            -ad {
               set createAD "true" 
               set explicitlyCreateAD "true"
            }
            -scp {
               set createScp "true" 
            }
            -czone {
               set createZone "true" 
               set explicitlyCreateZone "true"
            }
            -all {
               set createAD "true" 
               set createScp "true" 
               set createZone "true" 
            }
            -container {
                incr idx
                if {$idx >= $argCount} {
                    error "Missing -container argument: should be\n$usage"
                }
                set container [lindex $args $idx] 
            }
            -dnsname {
                incr idx
                if {$idx >= $argCount} {
                    error "Missing -dnsname argument: should be\n$usage"
                }
                set dnsname [lindex $args $idx] 
            }
            -trustee {
                incr idx
                if {$idx >= $argCount} {
                    error "Missing -trustee argument: should be\n$usage"
                }
                lappend trustees [lindex $args $idx] 
            }
            -* {
                error "Unknown flag $flag: should be\n$usage"
            }
            default {
                error "Unknown option $flag: should be\n$usage"
            }
        }
    }

    if {$createAD != "true" && $createScp != "true" && $createZone != "true"} {
        # Default to create ad and scp
        set createAD "true" 
        set createScp "true" 
    }

    set ztype ""
    set zone ""
    set zbase ""
    if {$createScp == "true" || $createZone == "true"} {
        set ztype [gzf type]
        if {$ztype != "tree" && $ztype != "classic3" &&  $ztype != "classic4"} {
            error "Wrong zone type $ztype, should be tree zone or classic zone"
        }
        set zone [gzf dn]
        set zbase [dn_from_domain [domain_from_dn $zone]]
    }
    if {$dnsname == ""} {
        # If not specified, dnsname should be computer.<joined domain>(same as console)
        set dnsname $computer.$domain
    }

    set addn ""
    if {$createAD == "true" || $createScp == "true"} {
        set objlist [get_objects -depth sub $base "(&(objectclass=computer)(cn=$computer))"]
        if {[llength $objlist] <= 0 && $createAD == "true"} {
            # If ad computer object does not exist and createAD
            # Create ad computer
            if {[string length $container] == 0} {
                set container computers
            }
            if {![catch {select_object $container}]} {
                set addn cn=$computer,$container
            } elseif {![catch {select_object $container,$base}]} {
                set addn cn=$computer,$container,$base
            } elseif {![catch {select_object cn=$container,$base}]} {
                set addn cn=$computer,cn=$container,$base
            } else {
                error "Invalid container"
            }

            new_object $addn
            sof objectclass computer 
            sof samaccountname $sam
            sof useraccountcontrol [expr 0x1000]
            svo
        } elseif {[llength $objlist] <= 0 && $createAD != "true"} { 
            # If ad computer object does not exist and not createAD
            # Error
            error "AD computer object doesn't exist, please specify -ad to create"
        } elseif {$explicitlyCreateAD == "true"} { 
            # If ad computer object exists
            # only error when explicitly creating AD computer object
            error "AD computer object already exists"
        } else {
            set addn [lindex $objlist 0]
        }

        # change computer password
        sup "$sam@$domain" $pw

        #enable computer account
        select_object $addn
        set control [gof userAccountControl]
        set control [expr $control & ~0x2]
        sof useraccountcontrol $control
        sof dNSHostName $dnsname
        set stypes "host http ftp cifs nfs"
        set spns ""
        foreach stype $stypes {
            lappend spns $stype/$computer
            lappend spns $stype/$dnsname
        }
        eval "sof servicePrincipalName $spns"
        svo
    }

    if {$createScp == "true"} {
        # deleting existing scp
        select_object $addn; 
        set sid [get_object_field sid]
        set filter "(|(keywords=parentLink:$sid)(managedBy=$addn))";
        foreach scp [get_objects -depth sub $zbase $filter] {
            select_object $scp; 
            delete_object;
        }

        new_zone_computer $sam@$domain
        set_zone_computer_field enabled 1
        save_zone_computer

        select_object $addn; 
        set scpdn [get_objects -depth sub $zbase "(|(keywords=parentLink:[gof sid])(managedBy=$addn))"]
        if {[llength $scpdn] != 1} {
            error "Can not find the scp we just created, maybe replication problem."
        } else {
            set scpdn [lindex $scpdn 0]
        }

        set uacGuid [get_schema_guid User-Account-Control] 
        # Well-known User-Force-Change-Password
        set pwdGuid {00299570-246d-11d0-a768-00aa006e0529}
        # Well-known Validated-DNS-Host-Name
        set dhnGuid {72e39547-7b18-11d1-adef-00c04fd8d5cd}
        # Well-known Validated-SPN
        set spnGuid {f3a64788-5306-11d1-a9c5-0000f80367c1}
        foreach trustee $trustees {
            slo [principal_to_dn $trustee]
            set usid [gof sid]
            
            slo $scpdn
            set sd [gof sd]
            # Arbitrary Trustee, Zone/Computers/scp, This object, Generic Read
            set sd [add_sd_ace $sd "A;;GR;;;$usid"]
            sof sd $sd
            svo

            slo $addn
            set sd [gof sd]
            # Arbitrary Trustee, AD computer object, This object, This object, Reset Password
            set sd [add_sd_ace $sd "OA;;CR;$pwdGuid;;$usid"]
            # Arbitrary Trustee, AD computer object, This object, This object, Write userAccountControl
            set sd [add_sd_ace $sd "OA;;RPWP;$uacGuid;;$usid"]
            # Arbitrary Trustee, AD computer object, This object, This object, Validated write to DNS host name 
            set sd [add_sd_ace $sd "OA;;SWRP;$dhnGuid;;$usid"]
            # Arbitrary Trustee, AD computer object, This object, This object, read/write to service principal name
            set sd [add_sd_ace $sd "OA;;RPWP;$spnGuid;;$usid"]
            sof sd $sd
            svo
        }

        set osGuid [get_schema_guid Operating-System] 
        set osvGuid [get_schema_guid Operating-System-Version]
        set oshGuid [get_schema_guid Operating-System-Hotfix]
        set osspGuid [get_schema_guid Operating-System-Service-Pack]
        slo $addn
        set csid [gof sid]
        set sd [gof sd]
        # SELF, AD computer object, This object, Write operatingSystem
        set sd [add_sd_ace $sd "OA;;WP;$osGuid;;PS"]
        # SELF, AD computer object, This object, Write operatingSystemVersion
        set sd [add_sd_ace $sd "OA;;WP;$osvGuid;;PS"]
        # SELF, AD computer object, This object, Write operatingSystemHotfix
        set sd [add_sd_ace $sd "OA;;WP;$oshGuid;;PS"]
        # SELF, AD computer object, This object, Write operatingSystemServicePack
        set sd [add_sd_ace $sd "OA;;WP;$osspGuid;;PS"]
        # SELF, AD computer object, This object, Reset Password
        set sd [add_sd_ace $sd "OA;;CR;$pwdGuid;;PS"]
        # SELF, AD computer object, This object, read userAccountControl
        set sd [add_sd_ace $sd "OA;;RP;$uacGuid;;PS"]
        # SELF, AD computer object, This object, Validated write to DNS host name 
        set sd [add_sd_ace $sd "OA;;SWRP;$dhnGuid;;PS"]
        # SELF, AD computer object, This object, read/write to service principal name
        set sd [add_sd_ace $sd "OA;;RPWP;$spnGuid;;PS"]        
        sof sd $sd
        svo

        set kwdGuid [get_schema_guid Keywords] 
        set disGuid [get_schema_guid Display-Name]
        slo $scpdn
        set sd [gof sd]
        # Precreated computer account, Zone/Computer/scp, This object, Generic Read
        set sd [add_sd_ace $sd "A;;GR;;;$csid"]
        # Precreated computer account, Zone/Computer/scp, This object, Write keywords property
        set sd [add_sd_ace $sd "OA;;WP;$kwdGuid;;$csid"]
        # Precreated computer account, Zone/Computer/scp, This object, Write displayName property
        set sd [add_sd_ace $sd "OA;;WP;$disGuid;;$csid"]
        sof sd $sd
        svo
    }

    if {$createZone == "true"} {
        set MZ $dnsname@$zone
        catch {select_zone $MZ;dlz}
        set czone_type [expr { $ztype == "tree" ? "computer" : "classic-computer" }]
        create_zone $czone_type $MZ std

        # restore current zone
        select_zone $zone
    }
}

proc getopt {_argv name {_var ""} } {
    upvar 1 $_argv argv $_var var
    set pos [lsearch -regexp $argv ^$name]
    if {$pos>=0} {
        set to $pos
        if {$_var ne ""} {
            set var [lindex $argv [incr to]]
        }
        set argv [lreplace $argv $pos $to]
        return 1
    } else {
        return 0
    }
}

proc convert_msdate {msdate} {
    if {$msdate==9223372036854775807} {
        return -1
    }
    return [clock format [expr ($msdate/10000000)-11644473600]]
}

set dict_gt [dict create]
dict set dict_gt 0x0001 "SYSTEM" 
dict set dict_gt 0x0002 "GLOBAL" 
dict set dict_gt 0x0004 "DOMAIN_LOCAL" 
dict set dict_gt 0x0008 "UNIVERSAL" 
dict set dict_gt 0x0010 "APP_BASIC" 
dict set dict_gt 0x0020 "APP_QUEEY" 
dict set dict_gt 0x80000000 "SECURITY" 

proc explain_groupType {gt} {
    global dict_gt
    set r [format "%x" $gt]
    dict for {k v} $dict_gt {
        if [expr $gt&$k] {
            lappend r $v
	    }
    }
    return $r
}

set dict_ta [dict create]
dict set dict_ta 0x0001 "NON_TRANSITIVE" 
dict set dict_ta 0x0002 "UPLEVEL_ONLY" 
dict set dict_ta 0x0004 "QUARANTINED_DOMAIN" 
dict set dict_ta 0x0008 "FOREST_TRANSITIVE" 
dict set dict_ta 0x0010 "CROSS_ORGANIZATION" 
dict set dict_ta 0x0020 "WITHIN_FOREST" 
dict set dict_ta 0x0040 "TREAT_AS_EXTERNAL" 
dict set dict_ta 0x0080 "USE_RC4_ENCRYPTION" 

proc explain_trustAttributes {ta} {
    global dict_ta
    set r [format "%x" $ta]
    dict for {k v} $dict_ta {
        if [expr $ta&$k] {
            lappend r $v
        }
    }
    return $r
}

proc explain_trustDirection {td} {
    switch $td {
	0 {return "disabled"}
	1 {return "inbound"}
	2 {return "outbound"}
	3 {return "two-way"}
        default {return "unknown"}
    }
}

set dict_pt [dict create]
dict set dict_pt # "Local Unix User"
dict set dict_pt % "Local Unix Group"
dict set dict_pt $ "Local Windows User"
dict set dict_pt : "Local Windows Group"
dict set dict_pt a "All AD users"
dict set dict_pt x "All Unix users"
dict set dict_pt w "All Windows users"
dict set dict_pt u "AD user"
dict set dict_pt g "AD group"

proc explain_ptype {pt} {
    global dict_pt
     if {![dict exists $dict_pt $pt]} {
        error "invalid ptype"
    } else {
        return [dict get $dict_pt $pt]
    }
}

set dict_uac [dict create]
dict set dict_uac 0x0001 "ADS_UF_SCRIPT" 
dict set dict_uac 0x0002 "ADS_UF_ACCOUNTDISABLE" 
dict set dict_uac 0x0008 "ADS_UF_HOMEDIR_REAUIRED" 
dict set dict_uac 0x0010 "ADS_UF_LOCKOUT" 
dict set dict_uac 0x0020 "ADS_UF_PASSWD_BITREQD" 
dict set dict_uac 0x0040 "ADS_UF_PASSWD_CANT_CHANGE" 
dict set dict_uac 0x0080 "ADS_UF_ENCRYPTED_TEXT_PASSWORD_ALLOWED" 
dict set dict_uac 0x0100 "ADS_UF_TEMP_DUPLICATE_ACCOUNT" 
dict set dict_uac 0x0200 "ADS_UF_NORMAL_ACCOUNT" 
dict set dict_uac 0x0800 "ADS_UF_INTERDOMAIN_TRUST_ACCOUNT" 
dict set dict_uac 0x1000 "ADS_UF_WORKSTATION_TRUST_ACCOUNT" 
dict set dict_uac 0x2000 "ADS_UF_SERVER_TRUST_ACCOUNT" 
dict set dict_uac 0x010000 "ADS_UF_DONT_EXPIRE_PASSWD" 
dict set dict_uac 0x020000 "ADS_UF_MNS_LOGON_ACCOUNT" 
dict set dict_uac 0x040000 "ADS_UF_SMARTCARD_REQUIRED" 
dict set dict_uac 0x080000 "ADS_UF_TRUSTED_FOR_DELEGATION" 
dict set dict_uac 0x100000 "ADS_UF_NOT_DELEGATED" 
dict set dict_uac 0x200000 "ADS_UF_USE_DES_KEY_ONLY" 
dict set dict_uac 0x400000 "ADS_UF_DONT_REQUIRE_PREAUTH" 
dict set dict_uac 0x800000 "ADS_UF_PASSWORD_EXPIRED" 

proc explain_userAccountControl {uac} {
    global dict_uac
    set r [format "%x" $uac]
    dict for {k v} $dict_uac {
        if [expr $uac&$k] {
            lappend r $v
	    }
    }
    return $r
}

proc list_zones {domain} {
    push
    foreach  zone [get_zones $domain] {
	if {[catch {select_zone -nc $zone}]} {
            puts "Cannot open zone: $zone"
        } else {
            puts "$zone : [gzf type] : [gzf schema] " }
    }
    pop
}

# Modify a timebox string (42 hex characters)
# strTimeBox:   original timebox string(42 hex characters)
# day:          the day of week to modify(Sunday=0)
# hour:         the hour to modify(0-23)
#               0 means 0:00~1:00, 23 means 23:00~24:00
# avail:        0 - make this hour unavailable
#               not 0 - make this hour available
# Example:  Let Saturday 23:00~24:00(Sa: 23:00-00:00) available
#           set tb 000000000000000000000000000000000000000000
#           puts [modify_timebox $tb 6 23 1]
#           800000000000000000000000000000000000000000
proc modify_timebox {strTimeBox day hour avail} {
    # Trim the head 0 in hour
    set hour [string trimleft $hour 0]
    if {$hour == ""} {
        set hour 0
    }
    if {$hour < 0 || $hour > 23} {
        error "Invalid hour: $hour. Should be 0~23"
    }
    if {$day < 0 || $day > 6} {
        error "Invalid day of week: $day. Should be 0~6"
    }
    set dayIndex [expr 6*int($day)+2]
    # 4 bit a hex characters, each bit represents one hour
    set hourIndex [expr int($hour/4)]
    # Because the timebox string is little-ending, and the higher bit is bigger hour
    # So change 0 1 2 3 4 5 -> 1 0 3 2 5 4
    set hourIndex [expr int($hourIndex/2)*4+1-$hourIndex] 
    set hourMask [expr int(pow(2, int($hour)%4))]
    # calculate index char 
    set i [expr ($dayIndex+$hourIndex)%42]
    # get original value
    set v 0x[string index $strTimeBox $i]
    # modify value
    if {$avail == "0"} {
        set v [format "%X" [expr $v & ~$hourMask]]
    } else {
        set v [format "%X" [expr $v | $hourMask]]
    }
    return [string replace $strTimeBox $i $i $v]
}

####################################################################
# timebox: a string(42 hex characters)    
#          Each day takes up 6 hex characters
#   internal format: the return value of [get_role_field timebox] 
#                    start from Sat 16:00 and the order is unusual 
#   output formal: an usual expression begin at Sun 0:00,and in usual order 
# internal format:             [2*i+1]         [2*i]           --- string index
#     [ 0~ 1] Sat  16:00~24:00 [ 1]16:00~20:00 [ 0]20:00~24:00
#     [ 2~ 3] Sun  00:00~08:00 [ 3]00:00~04:00 [ 2]04:00~08:00
#     [ 4~ 5]      08:00~16:00 [ 5]08:00~12:00 [ 4]12:00~16:00
#     [ 6~ 7]      16:00~24:00 [ 7]16:00~20:00 [ 6]16:00~24:00
#     [ 8~13] Mon  00:00~24:00        ......
#     ......     ......               ......
#     [32~37] Fri  00:00~24:00        ......
#     [38~39] Sat  00:00~08:00 [39]00:00~04:00 [38]04:00~08:00
#     [40~41] Sat  08:00~16:00 [41]08:00~12:00 [40]12:00~16:00
# output format:               [2*i]           [2*i+1]         --- string index
#     [ 0~ 1] Sun  00:00~08:00 [ 0]00:00~04:00 [ 1]04:00~08:00
#     [ 2~ 3]      08:00~16:00 [ 2]08:00~12:00 [ 3]12:00~16:00
#     [ 4~ 5]      16:00~24:00 [ 4]16:00~20:00 [ 5]16:00~24:00
#     [ 6~11] Mon  00:00~24:00        ......
#     ......     ......               ......
#     [30~35] Fri  00:00~24:00        ......
#     [36~37] Sat  00:00~08:00 [36]00:00~04:00 [37]04:00~08:00
#     [38~39] Sat  08:00~16:00 [38]08:00~12:00 [39]12:00~16:00
#     [40~41] Sat  16:00~24:00 [40]16:00~20:00 [41]20:00~24:00
#####################################################################
# return output format
proc decode_timebox {internal} {
    set output $internal
    # move the last 8 hours of Sat--the first 2 characters--to last,
    # the order is remaining
    set Sat_20_24_hours [string index $output 0]
    set Sat_16_20_hours [string index $output 1]
    set output [string replace $output 0 1]
    append output $Sat_20_24_hours 
    append output $Sat_16_20_hours 
    # now output start from 0:00 of Sun.
    # exchange value at position of 2i and 2i+1 hex characters .
    # make the expression of 8 hours is 
    #  (0:00-4:00 4:00-8:00) (8:00-12:00 12:00-16:00) (16:00-20:00 20:00-24:00)
    for {set i 0} {$i <21} {incr i} {
        # exchange the hex characters of the 2 position 
        set high_pos  [expr $i+$i] 
        set high [string index $output $high_pos] 
        set low_pos   [expr $high_pos+1] 
        set low  [string index $output $low_pos ] 
        set output [string replace $output $high_pos $high_pos $low  ]
        set output [string replace $output $low_pos  $low_pos  $high ]
    }
    return $output 
}
# return internal format
proc encode_timebox {output} {
    set internal $output 
    # move the last 8 hours of Sat--the first 2 characters-- to first,
    # the order is remaining
    set Sat_20_24_hours [string index $internal 41]
    set Sat_16_20_hours [string index $internal 40]
    set internal [string replace $internal 40 41]
    set Sat_16_24_hours ""
    append Sat_16_beginning $Sat_16_20_hours 
    append Sat_16_beginning $Sat_20_24_hours 
    append Sat_16_beginning $internal 
    set internal $Sat_16_beginning 
    # now internal start from 16:00 of Sat
    # exchange value at position of 2i and 2i+1 hex characters.
    # make the expression of 8 hours is 
    #  (4:00-8:0 00:00-4:00) (12:00-16:00 8:00-12:00) (20:00-24:00 16:00-20:00)
    for {set i 0} {$i <21} {incr i} {
        # exchange the hex characters of the 2 position 
        set high_pos  [expr $i+$i] 
        set high [string index $internal $high_pos] 
        set low_pos   [expr $high_pos+1] 
        set low  [string index $internal $low_pos ] 
        set internal [string replace $internal $high_pos $high_pos $low  ]
        set internal [string replace $internal $low_pos  $low_pos  $high ]
    }
    return $internal 
}

# args: rolename, description, sysrights,pamapplist,dzcmdlist,allowlocaluser,rse
proc create_role {role {desc {}} {sr {}} {apps {}} {cmds {}} {allowlocal {}} {rse {}} } {
    new_role $role
    
    set_role_field description $desc
	
    if {[string length $allowlocal]} {
        srf allowlocaluser $allowlocal
    }
	
    if {[string length $sr]} {
        srf sysrights $sr
    }

    foreach app $apps {
        add_pamapp_to_role $app
    }
    foreach cmd $cmds {
        add_command_to_role $cmd
    }
    if {[string length $rse]} {
        set_rs_env_for_role $rse
    }
    save_role
}

# args: pamappname, application, description
proc create_pam_app {pam app {desc {}}} {
    new_pam_app $pam;
    set_pam_field application $app;
    spf description $desc;
    save_pam_app;
}
# args: dzcmdname, cmd, description,form,
# dzdo_runas,dzsh_runas,flags,priority,umask,path.
proc create_dz_command {dzc cmd 
                        {desc {}} 
                        {form {}} 
                        {dzdo_runas {}} 
                        {dzsh_runas {}} 
                        {flags {}} 
                        {pri {}} 
                        {umask {}}
                        {path {}}} {
    new_dz_command $dzc 
    set_dzc_field cmd $cmd
    sdzcf description $desc
    sdzcf dzdo_runas $dzdo_runas
    if {[string length $dzsh_runas]} {
        sdzcf dzsh_runas $dzsh_runas
    }
    if {[string length $form]} {
        sdzcf form $form
    }
    if {[string length $flags]} {
        sdzcf flags  $flags
    }
    if {[string length $pri]} {
        sdzcf pri $pri
    }
    if {[string length $umask]} {
        sdzcf umask $umask
    }
    if {[string length $path]} {
        sdzcf path  $path
    }
    save_dz_command
}

# args: rscmdname, cmd, description,form,
# dzsh_runas,flags,priority,umask,path.
proc create_rs_command {rsc cmd 
                        {desc {}} 
                        {form {}} 
                        {dzsh_runas {}} 
                        {flags {}} 
                        {pri {}} 
                        {umask {}}
                        {path {}}} {
    new_rs_command $rsc 
    set_rsc_field cmd $cmd
    srscf description $desc
    srscf dzsh_runas $dzsh_runas
    if {[string length $form]} {
        srscf form $form
    }
    if {[string length $flags]} {
        srscf flags  $flags
    }
    if {[string length $pri]} {
        srscf pri $pri
    }
    if {[string length $umask]} {
        srscf umask $umask
    }
    if {[string length $path]} {
        srscf path  $path
    }
    save_rs_command
}

# args: rsename, description
proc create_rs_env {rse {desc {}}} {
    new_rs_env $rse
    set_rse_field description $desc
    save_rs_env
}

