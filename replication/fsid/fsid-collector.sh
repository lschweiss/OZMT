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

echo $$ > ${MYTMP}/fsid-collector.pid

$TIMEOUT $fsid_guid_timeout ../../utils/fsid/fsid_guid_address.d 1> ${MYTMP}/fsid_addresses &

$TIMEOUT $fsid_guid_timeout ../../utils/fsid/fsid_guid.d  | tee /tmp/debug_fsid.0 | \
    $AWK -F "#" '{print $2 " " $4}' | $GREP -v '@' | tee /tmp/debug_fsid.1 | \
    while read -r folder fsid; do
        # We sometimes get odd character output for the folder.  Discard these
        if [ "$folder" != '' ]; then
            zfs list -o name $folder 2>/dev/null 1>/dev/null
            if [ $? -eq 0 ]; then
                folder_file=`foldertojob $folder`
                address=`cat ${MYTMP}/fsid_addresses |$AWK -F "#" '{print $2 " " $4}'| $GREP "^$fsid" |$TAIL -1| $CUT -d ' ' -f2`
                if [ "$address" != '' ]; then
                    echo "Found fsid for $folder: $fsid at $address"
                    echo "$fsid $address" > ${MYTMP}/$folder_file
                fi
            fi
        fi
    done


