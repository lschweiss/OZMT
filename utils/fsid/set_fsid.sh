#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2021  Chip Schweiss

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# fast-zfs-mount.sh mounts zfs folders as fast as possible by calling all
# non-blocking 'zfs mount' commands in parallel

# Requires gnu parallel
# GNU Parallel - The Command-Line Power Tool
# http://www.gnu.org/software/parallel/

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../../zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

zfs_folder="$1"

if [ "$DEBUG" == "true" ]; then
    VERBOSE='-v '
else
    VERBOSE=''
fi

MKDIR ${TMP}/fsid

#TODO: This only works on datasets with no ZFS subfolders

pool=`echo $zfs_folder | $AWK -F '/' '{print $1}'`
folder=`echo $zfs_folder | $AWK -F '/' '{print $2}'`
fsid=`zfs get -s local,received -o value -H $zfs_fsid_property $zfs_folder 2>/dev/null`
my_fsid=`zfs get -s local,received -o value -H ${zfs_fsid_property}:${pool} $zfs_folder 2>/dev/null`
tag_name=`foldertojob $zfs_folder`

if [ -f ${TMP}/fsid/${tag_name}_set ]; then
    notice "FSID is already set for $zfs_folder  Doing nothing."
    exit 0
fi

if [ "$fsid" == "$my_fsid" ]; then
    notice "FSID is on orginating pool.  No override necessary."
else
    notice "Need to set FSID on $zfs_folder to $fsid"
    # Start collecting memory addresses 
    if [ -f ${TMP}/fsid/address_collector.pid ]; then
        address_collector_pid=`cat ${TMP}/fsid/address_collector.pid`
        debug "Checking for address collector with pid $address_collector_pid"
        if [ "$($BASENAME $($READLINK /proc/$address_collector_pid/path/255 2>/dev/null) 2>/dev/null)" != "fsid_address_collector.sh" ]; then
            address_collector_pid=''
        fi
    fi

    if [ "$address_collector_pid" == '' ]; then
        debug "Starting fsid address collection"
        ./fsid_address_collector.sh &
        address_collector_pid="$!"
        echo $address_collector_pid > ${TMP}/fsid/address_collector.pid
    else
        debug "Address collector is already running under pid $address_collector_pid"
    fi


    # Find my_fsid
    if [ "$my_fsid" == '' ]; then
        notice "Collecting fsid for $zfs_folder"
        my_fsid=`./fsid_guid.d 2>/dev/null| $GREP "#${zfs_folder}#" | $HEAD -1 | $AWK -F '#' '{print $4}'| $AWK -F '0x' '{print $2}'`
        debug "Found current FSID to be $my_fsid"
    else
        debug "Using stored fsid for $zfs_folder as $my_fsid"
    fi

    if [ "$my_fsid" == "$fsid" ]; then
        notice "FSID is already set for $zfs_folder.  No need to update."
        touch ${TMP}/fsid/${tag_name}_set
        exit 0
    fi

    if [ "$my_fsid" == '' ]; then
        error "Could not collect current fsid for $zfs_folder.  Override failed"
        exit 1
    fi

    # Wait for memory address to be found
    start="$SECONDS"
    address=''
    notice "Trying to find memory address for fsid $my_fsid"
    while [ "$address" == '' ]; do
        time="$(( SECONDS - start ))"
        if [ $time -gt 3600 ]; then
            error "Timeout of 1 hour exceeded to get memory address for $zfs_folder FSID $my_fsid"
            exit 1
        fi

        address=`cat ${TMP}/fsid/address_maps 2>/dev/null | $GREP "#0x${my_fsid}#" $HEAD -1 | $AWK -F '#' '{print $4}'`
        if [ "$address" == '' ]; then
            # Try to tickle the folder to alert dtrace
            zfs unmount $zfs_folder
            zfs mount $zfs_folder
            zfs share $zfs_folder
            mkdir -p $TMP/fsid/$folder
            mount -F nfs 127.0.0.1:/$folder $TMP/fsid/$folder
            $TIMEOUT 30s find $TMP/fsid/$folder 1>/dev/null 2>/dev/null
            sleep 3
            umount $TMP/fsid/$folder
            sleep 3
            address=`cat ${TMP}/fsid/address_maps | $GREP "#0x${my_fsid}#" $HEAD -1 | $AWK -F '#' '{print $4}'`
        fi
    done


    # Overwrite FSID

    /usr/bin/mdb -kw -e "${address}/Z $fsid"


    # Re-mount folder

    zfs unmount $zfs_folder
    zfs mount $zfs_folder
    zfs share $zfs_folder

    touch ${TMP}/fsid/${tag_name}_set

fi
