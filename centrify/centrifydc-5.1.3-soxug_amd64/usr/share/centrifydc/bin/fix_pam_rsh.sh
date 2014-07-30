#!/bin/bash

SED=`which sed 2>/dev/null`
PAM_CONF="/etc/pam.conf"
PAM_TMP="/etc/pam.conf.cdc_fix"

need_fix() {
    if [ -f $PAM_CONF ]; then
	NEEDFIX=`grep rsh $PAM_CONF | grep centrifydc`
	if [ -n "$NEEDFIX" ]; then
	    return 1
	fi
    fi
    return 0
}

need_fix
if [ $? -eq 0 ]; then
    echo no repair to /etc/pam.conf needed
    exit 0
fi

if [ -n "$SED" -a -x "$SED" ]; then
    sed '/rsh.*pam_centrifydc/d' /etc/pam.conf > $PAM_TMP 
    if [ -f $PAM_TMP ]; then
	mv $PAM_TMP /etc/pam.conf
	if [ $? -eq 0 ];then
	    echo repair completed.
	fi
    fi
else
    echo cannot find usable sed. no repair action taken.
    exit 1
fi

