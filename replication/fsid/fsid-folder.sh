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


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

source ../../zfs-tools-init.sh

if [ "x$replication_logfile" != "x" ]; then
    logfile="$replication_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$replication_report" != "x" ]; then
    report_name="$replication_report"
else
    report_name="replication"
fi

show_usage () {

    echo "Usage: $0"
    echo

}

MYTMP=${TMP}/replication/fsid

MKDIR ${MYTMP}

folder="$1"

[ "$folder" != "" ] && zfs list -o name -H $folder 1>/dev/null 2>/dev/null 
if [ $? -ne 0 ]; then
    error "$0 called without valid zfs folder"
    exit 1
fi

pool=`echo $folder | $CUT -d '/' -f1`
folder_file=`foldertojob $folder`

# Wait for fsid to be found for our folder
debug "Waiting for fsid to be found for $folder"
while [ ! -f ${MYTMP}/$folder_file ]; do

    # Check if fsid-collector is running and start if necessary.
    $SCREEN -ls fsid_collector 1>/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        notice "Launching fsid-collector for $folder fsid finder"
        $SCREEN -ls fsid_collector 1>/dev/null 2>/dev/null || $SCREEN -d -m -S fsid_collector -s /bin/bash ${PWD}/fsid-collector.sh
    fi

    sleep 15
done

# Collect fsid

fsid=`cat ${MYTMP}/$folder_file | $CUT -d ' ' -f1`
mem=`cat ${MYTMP}/$folder_file | $CUT -d ' ' -f2`

if [ "$fsid" != "" ] && [ "$mem" != "" ]; then
    notice "Setting FSID for $folder to $fsid"
    zfs set ${zfs_fsid_property}="$fsid" $folder
    zfs set ${zfs_fsid_property}:${pool}="$fsid" $folder
else
    # Something went wrong.  Delete the bad data file and exit.
    error "FSID or Mem address not collected properly for $folder"
    rm ${MYTMP}/$folder_file
    exit 1
fi


