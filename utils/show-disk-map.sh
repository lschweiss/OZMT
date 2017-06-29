#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2017  Chip Schweiss

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

. /opt/ozmt/zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

now=`${DATE} +"%F %H:%M:%S%z"`

local_pools="zpool list -H -o name"

myTMP=${TMP}/disk-map
MKDIR $myTMP



cat "$myTMP/disk_to_location" | \
while IFS='' read -r line || [[ -n "$line" ]]; do
    # Collect possible disk like
    possible_disk=`echo $line | ${AWK} -F ' ' '{print $1}'`
    if [ "$possible_disk" != '' ]; then
        mapping=`cat ${myTMP}/disk_to_location 2>/dev/null| ${GREP} "$possible_disk"`
    else
        mapping=''
    fi
    wwn=''
    bay=''
    serial=''
    if [ "$mapping" != "" ]; then
        wwn=`echo $mapping | ${CUT} -d ' ' -f 3`
        bay=`echo $mapping | ${CUT} -d ' ' -f 4`
        serial=`echo $mapping | ${CUT} -d ' ' -f 2`
        jbod=''
        if [ -f /etc/ozmt/jbod-map ]; then
            jbod=`cat /etc/ozmt/jbod-map 2>/dev/null| ${GREP}  "$wwn" | ${CUT} -d ' ' -f 2`
        fi

        if [ "$wwn" != "$last_wwn" ]; then
            echo
            last_wwn="$wwn"
        fi

        printf '%-24s | %-12s | %3s | %20s | %-30s \n' "$wwn" "$jbod" "$bay" "$serial" "$possible_disk"
    else
        #echo -n ''
        echo "${line}"
    fi
done
    

