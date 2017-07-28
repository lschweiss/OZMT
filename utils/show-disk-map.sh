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

jbods=`cat /etc/ozmt/jbod-map 2> /dev/null | ${AWK} -F ' ' '{print $2}' | ${SORT} `

cat $myTMP/disk_to_location 2> /dev/null | ${CUT} -f 3 | ${SORT} -u > ${myTMP}/unnamed_jbod.txt

for jbod in $jbods; do
    wwn=`cat /etc/ozmt/jbod-map | ${GREP} $jbod | ${CUT} -d ' ' -f 1`
    cat ${myTMP}/unnamed_jbod.txt | ${GREP} -v "$wwn" > ${myTMP}/unnamed_jbod.txt2
    mv ${myTMP}/unnamed_jbod.txt2 ${myTMP}/unnamed_jbod.txt
done
    
output_map () {
    local possible_disk=
    local mapping=
    local wwn=
    local bay=
    local serial=
    local model=
    local last_wwn=
    local line=
   
    if [ "$1" == '' ]; then
        echo "Bad call to output_map"
        return 1
    fi
    
    cat "$myTMP/disk_to_location" | ${GREP} "$1" | ${SORT} -k 4g | \
    while IFS='' read -r line || [[ -n "$line" ]]; do
        # Collect possible disk like
        possible_disk=`echo $line | ${AWK} -F ' ' '{print $1}'`
        if [ "$possible_disk" != '' ]; then
            cat ${myTMP}/disk_to_location 2>/dev/null| ${GREP} "$possible_disk" > ${myTMP}/mapping
        else
            rm -f ${myTMP}/mapping
        fi
        wwn=''
        bay=''
        serial=''
        if [ -f ${myTMP}/mapping ]; then
            wwn=`cat ${myTMP}/mapping | ${CUT} -f 3`
            bay=`cat ${myTMP}/mapping | ${CUT} -f 4`
            serial=`cat ${myTMP}/mapping | ${CUT} -f 2`
            vendor=`cat ${myTMP}/mapping | ${CUT} -f 5`
            model=`cat ${myTMP}/mapping | ${CUT} -f 6`
            firmware=`cat ${myTMP}/mapping | ${CUT} -f 7`
            jbod=''
            show_wwn=
            show_jbod=
            if [ -f /etc/ozmt/jbod-map ]; then
                jbod=`cat /etc/ozmt/jbod-map 2>/dev/null| ${GREP}  "$wwn" | ${CUT} -d ' ' -f 2`
            fi
    
            if [ "$wwn" != "$last_wwn" ]; then
                echo
                last_wwn="$wwn"
                show_wwn="$wwn"
                show_jbod="$jbod"
            fi
    
            printf '%-24s | %-12s | %3s | %-22s | %20s | %-9s | %-12s | %-4s\n' \
                "$show_wwn" "$show_jbod" "$bay" "$possible_disk" "$serial" "$vendor" "$model" "$firmware"
        else
            #echo -n ''
            echo "${line}"
        fi
    done

}

for jbod in $jbods; do
    wwn=`cat /etc/ozmt/jbod-map | ${GREP} $jbod | ${CUT} -d ' ' -f 1`
    output_map $wwn
done

for wwn in $(cat ${myTMP}/unnamed_jbod.txt); do
    output_map $wwn
done
    

