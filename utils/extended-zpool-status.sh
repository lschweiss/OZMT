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


if [ "$1" == '' ]; then
    echo "Must specify a pool."
    exit 1
fi


# Collect zpool status

zpool status $1 > $myTMP/zpool_status_$1
if [ $? -ne 0 ]; then
    echo "Invalid pool specified.  Please run with one of these:"
    zpool list -H -o name
    rm -f $myTMP/zpool_status_$1
fi

cat $myTMP/zpool_status_$1 | grep -q "resilvering" && resilvering='true'


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
    if [ "$mapping" != "" ]; then
        wwn=`echo $mapping | ${CUT} -d ' ' -f 3`
        bay=`echo $mapping | ${CUT} -d ' ' -f 4`
        jbod=''
        if [ -f /etc/ozmt/jbod-map ]; then
            jbod=`cat /etc/ozmt/jbod-map 2>/dev/null| ${GREP}  "$wwn" | ${CUT} -d ' ' -f 2`
        fi
        if [ "$jbod" != '' ]; then
            chassis="$jbod"
        else
            chassis="$wwn"
        fi
        if [ "$resilvering" == 'true' ]; then
            printf '%-71s | %-12s | %3s \n' "$line" "$chassis" "$bay"
        else
            printf '%-60s | %-12s | %3s \n' "$line" "$chassis" "$bay"
        fi
    else
        #echo -n ''
        echo "${line}"
    fi
done < "$myTMP/zpool_status_$1"



