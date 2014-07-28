#!/bin/bash 

# Copyright (c) 2007-2008   Centrify Corp.
#
# Collect all necessary files for adinfo --debugcache
# Store in /var/centrify/tmp/adinfo_debugcache.tar and zipped or compressed.
#

#
# Parameter:
# None

SUPPORTFILE="$1"
DESTDIR="`echo get_temp_dir | /usr/bin/adedit`/"
DEST="${DESTDIR}adinfo_debugcache.tar"
SOURCE="/var/centrifydc/*.cache /var/centrifydc/*.idx /var/centrifydc/nis/*"
CDCSTATE=`/usr/bin/adinfo -m`

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

if [ "$CDCSTATE" = "connected" ]; then
    echo "Stopping Centrify DirectControl..."
    /usr/share/centrifydc/bin/centrifydc stop
fi
echo "Collecting information for adinfo --debugcache now..."
tar -cf $DEST $SOURCE 2> /dev/null

if [ -f $DEST ]; then
    #only Allow root read right too.
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
if [ "$CDCSTATE" = "connected" ]; then
    echo "Starting Centrify DirectControl..."
    /usr/share/centrifydc/bin/centrifydc start
fi
