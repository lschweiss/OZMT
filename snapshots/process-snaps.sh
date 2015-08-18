#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012  Chip Schweiss

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

snaptype="$1"

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


snap_job () {

    local snaptype="$1"
    local job="$2"
    
    local pool=
    local folder=
    local zfsfolder=`echo $job|${SED} 's,%,/,g'`
   
    pool=`echo $zfsfolder | ${CUT} -d '/' -f 1`
    folder=`echo $zfsfolder | ${CUT} -d '/' -f 2`

    local jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"
    local keepcount=`cat $jobfolder/$snaptype/$job`
    local replication=
    local replication_dataset=
    local replication_endpoints=
    local replication_source=
    local replication_folder_point=
    local replication_pool_folder=
    local replication_folder=
    local snap_this_folder='false'
    local now=
    local stamp=
    local recursive=
    local result=


    mkdir -p ${TMP}

    # Test the folder exists
    debug "Pool: $pool   Folder: $folder   Job: $job  zfsfolder: $zfsfolder"
    zfs get -H -o value creation ${zfsfolder} 1>/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        # Nothing else to check, skip it.
        debug "No ZFS folder for snapshot job $jobfolder/$snaptype/$job"
        return 0
    fi

    # Make sure we should snap this folder
    replication=`zfs_cache get -H -o value $zfs_replication_property ${zfsfolder}`
    if [ "$replication" == "on" ]; then
        debug "Replication: on"
        replication_dataset=`zfs_cache get -H -o value $zfs_replication_dataset_property ${zfsfolder} 2>/dev/null`
        replication_folder_point=`zfs_cache get -H -o source $zfs_replication_dataset_property ${zfsfolder}`
        if [ "$replication_folder_point" == "local" ]; then
            replication_folder="$folder"
        else
            replication_pool_folder=`echo "$replication_folder_point" | ${AWK} -F " " '{print $3}'`
            replication_folder=`echo "$replication_pool_folder" | ${CUT} -d '/' -f 2`
        fi
        replication_source=`cat /${pool}/zfs_tools/var/replication/source/${replication_dataset}`
        if [ "$replication_source" == "${pool}:${replication_folder}" ]; then
            snap_this_folder='true'
        fi
    else
        debug "Replication: off"
        snap_this_folder='true'
    fi

    if [ "$snap_this_folder" == 'false' ]; then
        debug "Skipping snapshot for ${zfsfolder} Replication dataset: $replication_dataset Replication source: $replication_source 
               Replication folder: ${replication_folder} Replication folder point: $replication_folder_point" 
        # Skip this job
        return 0
    fi

    if [ "${keepcount:0:1}" == "x" ]; then
        keepcount="${keepcount:1}"
    fi

    if [ "${keepcount:0:1}" == "r" ]; then
        keepcount="${keepcount:1}"
        recursive='-r'
    fi

    now=`${DATE} +%F_%H:%M%z`
    stamp="${snaptype}_${now}"
    if [ "${keepcount:0:1}" != "x" ]; then
        zfs snapshot ${recursive} ${zfsfolder}@${stamp} 2>${TMP}/process_snap_$$ ; result=$?
        if [ $result -ne 0 ]; then
            error "Failed to create snapshot, error code: {$result}, $$ ${recursive} ${zfsfolder}@${stamp}" ${TMP}/process_snap_$$
        else
            notice "Created snapshot: ${recursive} ${zfsfolder}@${stamp}"
            rm ${TMP}/process_snap_$$
        fi
    fi
    
}



# collect jobs

pools="$(pools)"

debug "Pools: $pools"

for pool in $pools; do
    debug "Pool: $pool"
    jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"
    if [ -d $jobfolder/$snaptype ]; then
        jobs=`ls -1 $jobfolder/$snaptype`
        debug "Snapshot jobs: $jobs"
        for job in $jobs; do
            debug "Running $snaptype snapshot jobs for $job"
            launch snap_job "$snaptype" "$job"
        done
    else 
        debug "process-snap: No snap type(s) $snaptype defined."
    fi
done

