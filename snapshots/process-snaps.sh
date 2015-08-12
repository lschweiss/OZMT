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
    local IFS='/'
    read -r pool folder <<< "$zfsfolder"
    unset IFS
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

    # Test the folder exists
    debug "Pool: $pool   Folder: $folder   Job: $job  zfsfolder: $zfsfolder"
    zfs get -H -o value creation ${zfsfolder} 1>/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        # Nothing else to check, skip it.
        debug "No ZFS folder for snapshot job $jobfolder/$snaptype/$job"
        return 0
    fi

    # Make sure we should snap this folder
    replication=`zfs get -H -o value $zfs_replication_property ${zfsfolder} 2>/dev/null`
    if [ "$replication" == "on" ]; then
        replication_dataset=`zfs get -H -o value $zfs_replication_dataset_property ${zfsfolder} 2>/dev/null`
        replication_folder_point=`zfs get -H -o source $zfs_replication_dataset_property ${zfsfolder}`
        if [ "$replication_folder_point" == "local" ]; then
            replication_folder="$folder"
        else
            replication_pool_folder=`echo "$replication_folder_point" | ${AWK} -F " " '{print $3}'`
            IFS='/'
            read -r junk replication_folder <<< "$replication_pool_folder"
            unset IFS
        fi
        replication_source=`cat /${pool}/zfs_tools/var/replication/source/${replication_dataset}`
        if [ "$replication_source" == "${pool}:${replication_folder}" ]; then
            snap_this_folder='true'
        fi
    else
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
        zfs snapshot ${recursive} ${zfsfolder}@${stamp} 2> ${TMP}/process_snap_$$ 
        if [ $? -ne 0 ]; then
            error "Failed to create snapshot ${recursive} ${zfsfolder}@${stamp}" ${TMP}/process_snap_$$
        else
            notice "Created snapshot: ${recursive} ${zfsfolder}@${stamp}"
        fi
        rm ${TMP}/process_snap_$$
    fi
    
}



# collect jobs

pools="$(pools)"

for pool in $pools; do
    jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"
    if [ -d $jobfolder/$snaptype ]; then
        jobs=`ls -1 $jobfolder/$snaptype`
        for job in $jobs; do
            debug "Running $snaptype snapshot jobs for $job"
            launch snap_job "$snaptype" "$job"
        done
    else 
        debug "process-snap: No snap type(s) $snaptype defined."
    fi
done

