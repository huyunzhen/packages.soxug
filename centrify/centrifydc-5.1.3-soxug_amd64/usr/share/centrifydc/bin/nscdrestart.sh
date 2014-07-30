#!/bin/bash 

# Copyright (c) 2006-2008   Centrify Corp.
#
# restart the Name Service Caching Daemon to pickup changes to 
# nsswitch.conf and it's own config. 
#
# Linux & Solaris: nscd
# HPUX: pwgrd
# IRIX: nsd

NSCD="/usr/sbin/nscd"
NSCD_CONF="/etc/nscd.conf"
PWGR_SCRIPT="/sbin/init.d/pwgr"
NSCD_SCRIPT="/etc/init.d/nscd"
NSCD_SRV="system/name-service/cache"
NSCD_SYSTEMD_CMD="/usr/bin/systemctl"
NSCD_SYSTEMD_SRV="nscd.service"
LOGGER="logger -i -t nscdrestart -p"
NSD="/usr/etc/nsd"
SVCADM="/usr/sbin/svcadm"
SVCS="/usr/bin/svcs"

# Typically this value is only set during testing
unset CDC_OVERRIDE_MODE

# Set NSCD_SRV="system/name-service-cache" only for Solaris 10
if [ "`uname -s`" = "SunOS" -a "`uname -r`" = "5.10" ]; then
    NSCD_SRV="system/name-service-cache"
fi

usage()
{
    echo Restart or flush the nscd or pwgr daemon
    echo $0 '[ restart|flush|status ]'
}

isrunning()
{
    if [ "`uname -s`" = "SunOS" -a -x ${SVCADM} ]; then
        ${SVCS} ${NSCD_SRV} | grep online
    elif [ -x ${NSCD} ]; then
        test -n "`ps -ef | grep 'nscd' | grep -v grep | grep -v nscdrestart`"
    elif [ -x ${PWGR_SCRIPT} ]; then
        test -n "`ps -ef | grep 'pwgrd' | grep -v grep`"
    else
        test -n "`ps -ef | grep 'nsd' | grep -v grep`"
    fi
}

flushnscd()
{
    if isrunning; then
        # invalidate the cache
        ${LOGGER} auth.debug "invalidate nscd cache"
        ${NSCD} -i passwd
        ${NSCD} -i group
    fi
}

restartnscd()
{
    if [ "`uname -s`" = "SunOS" -a -x ${SVCADM} ]; then
# Solaris 10 uses smf instead of /etc/init.d
        if isrunning; then
            ${LOGGER} auth.debug "stopping name-service-cache"
            ${SVCADM} -v disable ${NSCD_SRV}
            if [ $? -eq 0 ]; then
                ${LOGGER} auth.debug "starting name-service-cache"
                ${SVCADM} -v enable ${NSCD_SRV}
# Nscd needs some time to become fully started on some systems, "online*" is the interim state.
                cnt=0
                while [ $cnt -lt 10 ]; do
                    if ${SVCS} ${NSCD_SRV} | grep "online\*" 2>&1 > /dev/null; then
                        sleep 1
                        cnt=`expr $cnt + 1`
                    else
                        break;
                    fi
                done
            else
                ${LOGGER} auth.debug "unable to stop name-service-cache"
            fi
        else
            ${LOGGER} auth.debug "name-service-cache not running. No need to restart"
        fi
    elif [ -x ${NSCD} ]; then
            if isrunning; then
                ${LOGGER} auth.debug "stopping nscd"
                if [ -x ${NSCD_SCRIPT} ]; then
                    ${NSCD_SCRIPT} stop
                elif [ -x ${NSCD_SYSTEMD_CMD} ]; then
                    ${NSCD_SYSTEMD_CMD} stop ${NSCD_SYSTEMD_SRV}
                fi
                
                if [ $? -eq 0 ]; then
                    sleep 1
                    ${LOGGER} auth.debug "starting nscd"
                    if [ -x ${NSCD_SCRIPT} ]; then
                        ${NSCD_SCRIPT} start 
                    elif [ -x ${NSCD_SYSTEMD_CMD} ]; then
                        ${NSCD_SYSTEMD_CMD} start ${NSCD_SYSTEMD_SRV}
                    fi
                else
                    ${LOGGER} auth.warn "problem stopping nscd.."
                fi
            else
                ${LOGGER} auth.debug "nscd not running. No need to restart"
            fi
    fi
}

if [ "$1" = "status" ]; then
    if isrunning; then
        echo name service cache is running
        exit 0;
    else
        echo name service cache is not running
        exit 1;
    fi
fi

if [ -x ${NSCD} ]; then
    case $1 in
      flush)
        flushnscd
        ;;
      restart)
        restartnscd
        flushnscd
        ;;
      *)
        usage
        ;;
    esac
elif [ -x $PWGR_SCRIPT ]; then
    case $1 in
      flush|restart)
        # No flush so just restart regardless
        if isrunning; then
            ${PWGR_SCRIPT} stop
            ${PWGR_SCRIPT} start
        fi
        # /sbin/init.d/set_pgroup may be run before adclient is active
        if [ -f /etc/privgroup ]; then
            /usr/sbin/setprivgrp -f /etc/privgroup
        fi
        ;;
      *)
        usage
        ;;
    esac
elif [ -x $NSD ]; then
    case $1 in
      flush)
        if isrunning; then
            # invalidate the cache
            ${LOGGER} auth.debug "invalidate nsd cache"
            /usr/sbin/nsadmin flush group.bygid  > /dev/null 2>&1
            /usr/sbin/nsadmin flush group.bymember  > /dev/null 2>&1
            /usr/sbin/nsadmin flush group.byname  > /dev/null 2>&1
            /usr/sbin/nsadmin flush passwd.byname  > /dev/null 2>&1
            /usr/sbin/nsadmin flush passwd.byuid  > /dev/null 2>&1
            /usr/sbin/nsadmin flush shadow.byname  > /dev/null 2>&1
            #
            # or flush everything
            # /usr/sbin/nsadmin flush
            #
        fi
        ;;
      restart)
        if isrunning; then
            /usr/sbin/nsadmin restart  > /dev/null 2>&1
        else
            ${LOGGER} auth.debug "nsd not running. No need to restart"
        fi
        ;;
      *)
        usage
        ;;
    esac
fi
