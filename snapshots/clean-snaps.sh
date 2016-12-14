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

jobfolder="$TOOLS_ROOT/snapshots/jobs"

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

# collect jobs

pools="$(pools)"

if [ "$1" == "" ]; then
    types="$snaptypes"
else
    types="$1"
fi

for pool in $pools; do

    # Collect snapshot data
    if [ ! -d /${pool}/zfs_tools/var/spool/snapshot/destroy_queue ]; then
        mkdir -p /${pool}/zfs_tools/var/spool/snapshot/destroy_queue
        init_lock /${pool}/zfs_tools/var/spool/snapshot/destroy_queue
    fi

    zfs list -H -o name -r -t snapshot ${pool} > /${pool}/zfs_tools/var/spool/snapshot/${pool}_snapshots
    zfs_cache list -H -r -o name,$zfs_replication_property,$zfs_replication_dataset_property,$zfs_replication_endpoints_property ${pool} > \
            /${pool}/zfs_tools/var/spool/snapshot/${pool}_replication_properties 3>/dev/null

    for snaptype in $types; do

        #rm -f ${TMP}/snapshots/clean/$snaptype/* 2>/dev/null
        folders=`zfs_cache get -H -o name -s local,received -r ${zfs_snapshot_property}:${snaptype} $pool 3>/dev/null`
        
        # sort folders  
        for folder in $folders; do
            clean_this_folder='false'
            recursive='false'
            snap_grep="^${folder}@${snaptype}_"
            folder_fixed="$(foldertojob $folder)"
            destroy_queue="/${pool}/zfs_tools/var/spool/snapshot/destroy_queue/$folder_fixed"
            mkdir -p $destroy_queue

            folder_props=`cat /${pool}/zfs_tools/var/spool/snapshot/${pool}_replication_properties | ${GREP} "^${folder}\s"`
            # Make sure we should clean this folder
            replication=`echo $folder_props | ${CUT} -d ' ' -f 2`
            if [ "$replication" == "on" ]; then
                debug "Replication: on"
                replication_dataset=`zfs_cache get -H -o value $zfs_replication_dataset_property ${folder} 3>/dev/null`
                replication_folder_point=`zfs_cache get -H -o source $zfs_replication_dataset_property ${folder} 3>/dev/null`
                # This could be a child folder, handle appropriately
                if [[ "$replication_folder_point" == "local" || "$replication_folder_point" == "received" ]]; then
                    replication_folder="${folder#*/}"
                else
                    # This is a child folder.  Find the parent folder that is the replication point.
                    replication_pool_folder=`echo "$replication_folder_point" | ${AWK} -F " " '{print $3}'`
                    replication_folder="${replication_pool_folder#*/}"
                fi
                # Get the known source
                if [ -f "/${pool}/zfs_tools/var/replication/source/${replication_dataset}" ]; then
                    replication_source=`cat /${pool}/zfs_tools/var/replication/source/${replication_dataset}`
                    if [ "$replication_source" == "${pool}:${replication_folder}" ]; then
                        clean_this_folder='true'
                    fi
                fi
            else
                #debug "Replication: off"
                clean_this_folder='true'
            fi
        
            if [ "$clean_this_folder" == 'false' ]; then
                debug "Skipping cleaning for ${folder} Replication dataset: $replication_dataset Replication source: $replication_source
                       Replication folder: ${replication_folder} Replication folder point: $replication_folder_point"
                # Skip this job
                continue
            fi


            keepcount=`zfs_cache get -H -o value ${zfs_snapshot_property}:${snaptype} ${folder} 3>/dev/null`

            debug "Keeping $keepcount snapshots for ${folder}"
        
            if [ "${keepcount:0:1}" == "r" ]; then
                keepcount="${keepcount:1}"
                recursive='true'
            fi

            if [[ "$keepcount" != "" && $keepcount -ne 0 ]]; then
                # Queue snapshots for removal
                delete_list=`cat /${pool}/zfs_tools/var/spool/snapshot/${pool}_snapshots | \
                    ${AWK} -F " " '{print $1}' | \
                    ${GREP} "${snap_grep}" | \
                    ${SORT} -r | \
                    ${TAIL} -n +$(( $keepcount + 1 ))`
                for snap in $delete_list; do
                    notice "Destroying: ${snap}, keeping ${keepcount} of type ${snaptype}"
                    echo "$snap" > ${destroy_queue}/${folder_fixed}_$(${DATE} +%s.%N)
                done
            fi
                
        done # for folder

    done # for snaptype

    launch ./process-destroy-queue.sh $pool

done

