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

source ${TOOLS_ROOT}/utils/locate-disks/locate-functions.sh

if [ ! -f $myTMP/disks ]; then
    collect_disk_info
fi

if [ ! -f $myTMP/expanders ]; then
    collect_expander_info
fi

if [ ! -f $myTMP/pools ]; then
    locate_in_use_disks
fi

source $myTMP/disks
source $myTMP/expanders


if [ "$1" == '-w' ]; then
    wide='true'
fi


#jbods=`cat /etc/ozmt/jbod-map 2> /dev/null | ${AWK} -F ' ' '{print $2}' | ${SORT} `
#
#cat $myTMP/disk_to_location 2> /dev/null | ${CUT} -f 3 | ${SORT} -u > ${myTMP}/unnamed_jbod.txt
#
#for jbod in $jbods; do
#    wwn=`cat /etc/ozmt/jbod-map | ${GREP} $jbod | ${CUT} -d ' ' -f 1`
#    cat ${myTMP}/unnamed_jbod.txt | ${GREP} -v "$wwn" > ${myTMP}/unnamed_jbod.txt2
#    mv ${myTMP}/unnamed_jbod.txt2 ${myTMP}/unnamed_jbod.txt
#done
    
output_map () {
    local possible_disk=
    local mapping=
    local wwn="$1"
    local bay=
    local serial=
    local model=
    local last_wwn=
    local line=
    local path=
    local paths=
   
    if [ "$1" == '' ]; then
        echo "Bad call to output_map"
        return 1
    fi

    # Output header
    if [ "${expander["${wwn}_name"]}" != "" ]; then
        name="${expander["${wwn}_name"]}, WWN: $wwn"
    else
        name="WWN: $wwn"
    fi
    
    paths="${expander["${wwn}_paths"]}"

    echo "1: Predictive Failure   2: Slot Disabled   3: Ident on   4: Fault on   5: Slot power off"
    echo
   
    echo "JBOD: $name, Model: ${expander["${wwn}_model"]}, FW: ${expander["${wwn}_fwrev"]}, Paths (${paths}):"
    path=1
    while [ $path -le $paths ]; do
        echo "   ${expander["${wwn}_path_${path}"]}"
        path=$(( path + 1 ))
    done

    if [ "$wide" == 'true' ]; then    
        printf '%3s | %-22s | %-15s | %-9s | %-15s | %-4s | %-8s | %-10s | %-9s | %-5s | %-5s | %-16s | %-16s | %-16s | %-16s\n' \
            "Bay" "OS Name" "Serial" "Vendor" "Model" "FW" "Status" "Pool" "vdev" "sd" "12345" "Slot Status" "wwn" "Addr 1" "Addr 2"
    else
        printf '%3s | %-22s | %-15s | %-9s | %-15s | %-4s | %-8s | %-10s | %-9s | %-5s | %-14s\n' \
            "Bay" "OS Name" "Serial" "Vendor" "Model" "FW" "Status" "Pool" "vdev" "12345" "Slot Status"
    fi 
    
    bays="${expander["${wwn}_slots"]}"

    bay=0
    highlight=0

    while [ $bay -lt $bays ]; do
        disk_osname="${expander["${wwn}_diskosname_${bay}"]}"
        disk_wwn="${expander["${wwn}_diskwwn_${bay}"]}"
        disk_addr1="${expander["${wwn}_sasaddr_${bay}_1"]}"
        disk_addr2="${expander["${wwn}_sasaddr_${bay}_2"]}"
        disk_serial="${disk["${disk_wwn}_serial"]}"
        disk_vendor="${disk["${disk_wwn}_vendor"]}"
        disk_model="${disk["${disk_wwn}_model"]}"
        disk_fwrev="${disk["${disk_wwn}_fwrev"]}"
        disk_status="${disk["${disk_wwn}_status"]}"
        disk_pool="${disk["${disk_wwn}_pool"]}"
        disk_vdev="${disk["${disk_wwn}_vdev"]}"
        disk_sdnum="${disk["${disk_wwn}_sdnum"]}"

        slot_pfailure="${expander["${wwn}_pfailure_${bay}"]}"
        slot_disabled="${expander["${wwn}_disabled_${bay}"]}"
        slot_status="${expander["${wwn}_status_${bay}"]}"
        slot_ident="${expander["${wwn}_ident_${bay}"]}"
        slot_fault="${expander["${wwn}_fault_${bay}"]}"
        slot_off="${expander["${wwn}_off_${bay}"]}"

        compact_status="${slot_pfailure}${slot_disabled}${slot_ident}${slot_fault}${slot_off}"

        if [ $highlight -eq 1 ]; then
            echo -n "$(color bd cyan )"
            highlight=0
        else
            echo -n "$(color bd yellow )"
            highlight=1
        fi
        if [ "$wide" == 'true' ]; then
            printf '%3s | %-22s | %-15s | %-9s | %-15s | %-4s | %-8s | %-10s | %-9s | %-5s | %-5s | %-16s | %-16s | %-16s | %-16s | %-16s\n' \
                "$(( bay + 1 ))" "$disk_osname" "$disk_serial" "$disk_vendor" "$disk_model" "$disk_fwrev" \
                "$disk_status" "$disk_pool" "$disk_vdev" "$disk_sdnum" "$compact_status" "$slot_status" \
                "$disk_wwn" "$disk_addr1" "$disk_addr2"
        else
            printf '%3s | %-22s | %-15s | %-9s | %-15s | %-4s | %-8s | %-10s | %-9s | %-5s | %-14s\n' \
                "$(( bay + 1 ))" "$disk_osname" "$disk_serial" "$disk_vendor" "$disk_model" "$disk_fwrev" \
                "$disk_status" "$disk_pool" "$disk_vdev" "$compact_status" "$slot_status"
        fi
        bay=$(( bay + 1 ))
    done

    echo "$(color)"
    
}
unset IFS

# Show mapped JBODs

if [ -f /etc/ozmt/jbod-map ]; then
    jbod_list=`cat /etc/ozmt/jbod-map | ${GREP} -v "^\#" | ${GREP} -v "^$"| ${AWK} -F ' ' '{print $1}'`
    
    for jbod in $jbod_list; do
        found=0
        for wwn in $expander_list; do
            if [ "$wwn" == "$jbod" ]; then
                output_map $wwn
                found=1
                break
            fi
        done
    done

fi

# Show unmapped JBODs

for wwn in $expander_list; do
    cat /etc/ozmt/jbod-map 2> /dev/null | grep -q $wwn || output_map $wwn
done

    

