#!/bin/bash 

# Copyright (c) 2007-2008   Centrify Corp.
#
# Collect all necessary files for adinfo --support
# Store in /var/centrify/tmp/adinfo_support.tar and zipped or compressed.
#

#
# Parameter:
# $* - path of the adinfo_support.txt is in the end of additional paths

ADDITIONAL_PATHS="$*" # Get additional paths
DEST=""
REG_USERS_TMPDIR="/var/centrify/tmp/users_gp.report" # store users' gp.report directory
SOURCE="/var/log/centrify_client.log \
        /var/log/centrifydc-install.log \
        /var/adm/syslog/centrify_client.log \
        /var/adm/syslog/centrifydc-install.log \
        /etc/*release \
        /etc/centrifydc \
        /etc/ssh \
        /opt/ssh/etc \
        /etc/ssh_* \
        /etc/sshd_* \
        /usr/local/etc/ssh_* \
        /usr/local/etc/sshd_* \
        /var/centrifydc/reg/machine/gp.report \
        /var/centrify/tmp/stacktrace.txt \
        $REG_USERS_TMPDIR $ADDITIONAL_PATHS"

REG_USERS_SOURCEDIR="/var/centrifydc/reg/users"
REG_USERS_TMPDIR_BAK="/var/centrify/tmp/users_gp.report.bak.$$"

TARGET_OS=""
CMD_AWK="awk"

identify_os()
{
    UNAME=`uname -a`
    case "$UNAME" in
        SunOS*)
            TARGET_OS="solaris"
            CMD_AWK="nawk"
            ;;
    esac
}

# Get destination directory by the path of the adinfo_support.txt
# because the path of the adinfo_support.txt is in the end of path
get_dest()
{
    SUPPORTFILE=`echo $ADDITIONAL_PATHS | ${CMD_AWK} '{print $NF}'`
    DESTDIR=`echo $SUPPORTFILE|sed 's/[^/]*$//g'`
    DEST="${DESTDIR}adinfo_support.tar"
}

# maybe have many users, so copy users' gp.report files for storing adinfo_support.tar with command tar
get_users_gpfiles()
{
    if [ -d "${REG_USERS_SOURCEDIR}" ]; then
        # back up REG_USERS_TMPDIR if have
        if [ -d "${REG_USERS_TMPDIR}" ]; then
            mv "${REG_USERS_TMPDIR}" "${REG_USERS_TMPDIR_BAK}"
        fi
        mkdir -p "${REG_USERS_TMPDIR}"
        find "${REG_USERS_SOURCEDIR}" -name "gp.report" 2> /dev/null | while read line; do
            username=`echo "${line}" | ${CMD_AWK} -F "/" '{print $(NF-1)}'`
            mkdir "${REG_USERS_TMPDIR}/${username}"
            cp "${line}" "${REG_USERS_TMPDIR}/${username}/"
        done
    fi
}

cleanup_tmpdir()
{
    if [ -d "${REG_USERS_TMPDIR_BAK}" ]; then
        mv "${REG_USERS_TMPDIR_BAK}" "${REG_USERS_TMPDIR}"
    fi
    rm -rf "${REG_USERS_TMPDIR}"
}

# main
identify_os
get_users_gpfiles
get_dest

if [ "$DESTDIR" = "/var/centrify/tmp/" ]; then
    DESTDIR="`echo get_temp_dir | /usr/bin/adedit`/"
fi
if [ -f $DEST ]; then
    echo "Remove previous $DEST"
    rm -f $DEST
fi
if [ -f $DEST.gz ]; then
    echo "Remove previous $DEST.gz"
    rm -f $DEST.gz
fi
if [ -f $DEST.Z ]; then
    echo "Remove previous $DEST.Z"
    rm -f $DEST.Z
fi

echo "Collecting information for adinfo --support now..."
# skip directory and any file, which name end with key, 
# e.g ssh private key
# Note: the max length of command line is OS dependent, e.g. HPUX ARG_MAX is 2M , while RHEL seems like just 131K. 
# So, we may also need to check the length of the arg, when the number of files to pack increases. 
SOURCE_TO_PACK=`
find $SOURCE 2>/dev/null | while read line
do
    test -d $line 2>/dev/null \
    || ( echo $line | grep -v "key$" > /dev/null \
    && echo $line )
done`
tar -cf $DEST $SOURCE_TO_PACK 2>/dev/null

cleanup_tmpdir

if [ -f $DEST ]; then
    #Like adinfo_support.txt file, only Allow root read right too.
    chmod 400 $DEST
    
    echo "Collection finished. Compress now."
    gzip $DEST

    if [ $? -eq 0 ]; then
        echo "Successfully gzip $DEST."
    else
        echo "gzip failed, using compress instead."
        compress $DEST
        
        if [ $? -eq 0 ]; then
            echo "Successfully compress $DEST."
        else 
            echo "compress failed. Keep $DEST."
        fi
    fi
else
    echo "Collection failed!"
fi
