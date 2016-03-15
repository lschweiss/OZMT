#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2015  Chip Schweiss

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

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

pool="$1"

if [ "x$snapshot_logfile" != "x" ]; then
    logfile="$snapshot_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$snapshot_report" != "x" ]; then
    report_name="$snapshot_report"
else
    report_name="$default_report_name"
fi

destroy_queue="/${pool}/zfs_tools/var/spool/snapshot/destroy_queue"

wait_for_lock $destroy_queue

folders=`ls -1t $destroy_queue`

mkdir -p ${TMP}/snapshots

for folder in $folders; do
    zfs_folder="$(jobtofolder $folder)"
    x=0
    # Collect snapshots
    snaps=`ls -1 $destroy_queue/$folder | ${SORT}`
    if [ "$snaps" == "" ]; then
        continue
    fi
    for snap in $snaps; do
        x=$(( x + 1 ))
        snapfile[$x]="$snap"
        snapshot[$x]=`cat $destroy_queue/$folder/$snap | ${AWK} -F '@' '{print $2}'`
    done
    # Build destroy command

    echo -n "zfs destroy -d ${zfs_folder}@${snapshot[1]}" > ${TMP}/snapshots/destroy_$$.sh

    y=2
    while [ $y -le $x ]; do
        echo -n ",${snapshot[$y]}" >> ${TMP}/snapshots/destroy_$$.sh
        y=$(( y + 1 ))
    done

    echo " 2>${TMP}/snapshots/destroy_$$.error.txt" >> ${TMP}/snapshots/destroy_$$.sh

    if [ "$DEBUG" == 'true' ]; then
        cat ${TMP}/snapshots/destroy_$$.sh
        result=0
    else   
        source ${TMP}/snapshots/destroy_$$.sh 
        result=$?
    fi

    if [ $result -ne 0 ]; then 
        warning "Failed to destroy snapshots for $zfs_folder." ${TMP}/snapshots/destroy_bulk_$$.error.txt
        # Try individually
        y=1
        while [ $y -le $x ]; do
            zfs list -o name -H ${zfs_folder}@${snapshot[$y]} 1>/dev/null 2>/dev/null 
            if [ $? -eq 0 ]; then
                echo "zfs destroy -d ${zfs_folder}@${snapshot[$y]} 2>${TMP}/snapshots/destroy_${y}_$$.error.txt"
                result=$?
                if [ $result -ne 0 ]; then
                    warning "Failed to destroy snapshot for ${zfs_folder}@${snapshot[$y]}." ${TMP}/snapshots/destroy_${y}_$$.error.txt
                else
                    rm ${destroy_queue}/${folder}/${snapfile[$y]}
                fi
            else
                rm ${destroy_queue}/${folder}/${snapfile[$y]}
            fi
            y=$(( y + 1 ))
        done                            
    else
        # Clean up 
        debug "Cleaning up destroy queue"
        y=1
        while [ $y -le $x ]; do
            rm ${destroy_queue}/${folder}/${snapfile[$y]}
            y=$(( y + 1 ))
        done
        if [ ! "$( ls -A ${destroy_queue}/${folder} )" ]; then
            rmdir ${destroy_queue}/${folder}
        fi
    fi
    
    rm ${TMP}/snapshots/destroy_$$.sh ${TMP}/snapshots/destroy_$$.error.txt ${TMP}/snapshots/destroy_*_$$.error.txt 2>/dev/null

done

release_lock $destroy_queue
        
