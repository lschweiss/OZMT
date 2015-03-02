#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2015  Chip Schweiss

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

pools="$(pools)"

if [ -z $reset_replication_timeout ]; then
    reset_replication_timeout=60
fi

show_usage () {
    echo
    echo "Usage: $0 {dataset_name}"
    echo "  {dataset_name}   Name of the data set to clean all replication jobs and"
    echo "                   replication snapshots except the latest fully syncd snapshot."
    echo "                   It then puts the job back in to a status for resuming replication."  
    echo ""
    echo "  The host this command is run on must be either the source host for this dataset."
    echo ""
    echo "  This is automatically run after every cut over of a dataset source or can be run"
    echo "  manually to cleanup broken replication jobs."
    echo ""
    echo "  The following data sets are known:"
    for pool in $pools; do
        if [ -d /${pool}/zfs_tools/var/replication/source ]; then
            ls -1 /${pool}/zfs_tools/var/replication/source | ${SED} 's/^/    /'
        fi
    done
    exit 1
}

# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

dataset="$1"
job_count=0
ds_source=

##
# Gather information about the dataset
##

# Does it exist?
for pool in $pools; do
    debug "Checking for dataset $dataset on pool $pool"
    if [ -f /${pool}/zfs_tools/var/replication/source/${dataset} ]; then
        ds_source=`cat /${pool}/zfs_tools/var/replication/source/${dataset}`
        break
    fi
done

if [ "$ds_source" == "" ]; then
    error "Could not find dataset \"${dataset}\" on this host."
    show_usage
    exit 1
else
    debug "Found dataset $dataset on pool $pool"
fi

# Where are the targets?
ds_targets=`cat /$pool/zfs_tools/var/replication/targets/${dataset}`

# Find and read the definition(s).

for check_pool in $pools; do
    if [ -d "/$check_pool/zfs_tools/var/replication/jobs/definitions" ]; then
        definitions=`find "/$check_pool/zfs_tools/var/replication/jobs/definitions/" -type f`
        for definition in $definitions; do
            source $definition
            if [ "$dataset_name" == "$dataset" ]; then
                jobs="$definition $jobs"
                job_count=$(( job_count + 1 ))
            fi
        done        
    fi
done

##
# Is this the source host?
##

source_pool=`echo "$ds_source" | ${CUT} -d ":" -f 1`
source_folder=`echo "$ds_source" | ${CUT} -d ":" -f 2`

if islocal $source_pool; then
    debug "Confirmed running on the source host."
else
    error "Must be run on the dataset's source host with the pool $source_pool"
    exit 1
fi


##
# Is it unanimous where the source is?
##

for target in $ds_targets; do
    debug "Checking dataset source for target $target"
    target_pool=`echo "$target" | ${CUT} -d ":" -f 1`
    check_source=`${SSH} root@$target_pool cat /$target_pool/zfs_tools/var/replication/source/$dataset`
    if [ "$check_source" != "$ds_source" ]; then
        error "Dataset source is not consistent at all targets.  Target $target reports source to be $check_source.  My source: $ds_source"
        exit 1
    fi
done

##
# Suspend replication and wait for already running jobs to finish
##

for job in $jobs; do
    source $job
    update_job_status "$job_status" "suspended" "true"
done

# Are there still jobs running?
for job in $jobs; do
    source $job
        ls -1 "/$pool/zfs_tools/var/replication/jobs/running/${dataset}_to_${target_pool}:$(foldertojob $target_folder)_*"  &>/dev/null
        if [ $? -eq 0 ]; then
            debug "Waiting for running job(s) to complete for up to $reset_replication_timeout minutes"
            sleep 5
            wait_time=5
            running=0
            while [ $running -eq 0 ]; do
                wait_minutes=$(( wait_time / 60 ))
                if [ $wait_minutes -ge $reset_replication_timeout ]; then
                    error "Waited $reset_replication_timeout minutes for $dataset running jobs to complete.  Giving up."
                    exit 1
                fi
                ls -1 "/$pool/zfs_tools/var/replication/jobs/running/${dataset}_to_${target_pool}:$(foldertojob $target_folder)_*" &>/dev/null
                running=$?
                if [ $running -eq 0 ]; then
                    sleep 5
                    wait_time=$(( wait_time + 5 ))
                fi
            done
        else
            debug "No running jobs for $dataset to $target"
        fi            
done


##
# Temporarily suspend scheduling any new jobs on the source pool
##
echo "Resetting replication for $dataset" > /$source_pool/zfs_tools/var/replication/jobs/suspend_all_jobs



##
# Find the newest common replication snapshot
## 

# Gather a list children folders on the source
children_folders=`zfs list -H -r -o name ${source_pool}/${source_folder} | ${TAIL} -n+2`

# Gather a list of replication snapshots from the source zfs folder. 
# Reverse sort them so we work from newest to oldest.
replication_snaps=`zfs list -H -r -t snapshot -o name ${pool}/${source_folder} | \
                   ${GREP} "$zfs_replication_snapshot_name" | \
                   ${SORT} -r`
parrent_replication_snaps=`printf '%s\n' "$replication_snaps" | \
                           ${GREP} "^${source_pool}/${source_folder}@"`
parrent_valid_snaps=


# Make sure each snapshot is also in all the children
# Eliminate from the list any snapshot that is not in all children
if [ "$children_folders" != "" ]; then
    for parrent_snap in $parrent_replication_snaps; do
        valid_snap='true'
        parrent_snap_name=`echo $parrent_snap|${CUT} -d '@' -f2`
        for child_folder in $children_folders; do
            child_snaps=`printf '%s\n' "$replication_snaps" | \
                         ${GREP} "^$child_folder@"`
            # Test if snap is good
            echo $child_snaps | ${GREP} -q "$parrent_snap_name"
            if [ $? -ne 0 ]; then
                valid_snap='false'
            fi
        done
        if [ "$valid_snap" == 'true' ]; then
            parrent_valid_snaps+=" $parrent_snap"
        fi
    done
else
    parrent_valid_snaps="$parrent_replication_snaps"
fi

parrent_snap_count=`echo $parrent_valid_snaps | ${WC} -w`
if [ $parrent_snap_count -eq 0 ]; then
    error "No replication snapshots exist in ${source_pool}/${source_folder} that are properly propigated through all children ZFS folders"
    exit 1
else
    debug "Found $parrent_snap_count possible snapshot on the source ${source_pool}/${source_folder}"
fi

# From newest to oldest check all targets including children for the snapshot
parrent_replication_snaps=`printf '%s\n' "$parrent_valid_snaps"` 


for parrent_snap in $parrent_replication_snaps; do
    valid_snap='true'
    parrent_snap_name=`echo $parrent_snap|${CUT} -d '@' -f2`

    for ds_target in $ds_targets; do
        if [ "$ds_target" != "${source_pool}:${source_folder}" ]; then
            target_pool=`echo $ds_target| ${CUT} -d ":" -f1`
            target_folder=`echo $ds_target| ${CUT} -d ":" -f2`
            # Collect snapshots
            debug "Collecting snapshots from ${target_pool}/${target_folder}"
            target_snaps=`ssh $target_pool zfs list -H -r -t snapshot -o name ${target_pool}/${target_folder} 2>/dev/null | \
                          ${GREP} "$zfs_replication_snapshot_name"`
            if [ "$target_snaps" == "" ]; then
                error "Could not collect snapshots from ${target_pool}/${target_folder}"
                exit 1
            fi
            target_parrent_snaps=`printf '%s\n' "$target_snaps" | ${GREP} "^${target_pool}/${target_folder}@"`
            debug "Checking for snapshot \"$parrent_snap_name\" on $ds_target"
            printf '%s\n' "$target_parrent_snaps" | ${GREP} -q "$parrent_snap_name"
            if [ $? -ne 0 ]; then
                debug "Snapshot not found."
                valid_snap='false'
            fi
            # Check child snaps
            if [[ "${valid_snap}" == 'true' && "$children_folders" != "" ]]; then
                for child_folder in $children_folders; do
                    child_folder_short="${child_folder:${#ds_source}}"
                    debug "Checking for snapshot on ${ds_target}${child_folder_short}"
                    printf '%s\n' "$target_snaps" | ${GREP} -q "${target_pool}/${target_folder}${child_folder_short}@${parrent_snap_name}"
                    if [ $? -ne 0 ]; then
                        debug "Snapshot not found \"${target_pool}/${target_folder}${child_folder_short}@${parrent_snap_name}\""
                        valid_snap='false'
                        break
                    fi
                done
            fi
        fi    
    done
    if [ "$valid_snap" == 'true' ]; then
        # This snap is the newest common snapshot
        debug "Success! Snapshot $parrent_snap_name is on all targets."
        common_snap="$parrent_snap_name"
        break
    fi

done


if [[ "$valid_snap" != 'true' || "$common_snap" == "" ]]; then
    error "Could not find a common snapshot to sync for dataset ${dataset}.   Replication will need to be restarted."
    exit 1
fi


##
# Destroy all other replication snapshots
##

# Destroy source snapshots
for snap in $replication_snaps; do
    echo "$snap" | ${GREP} -q "$common_snap"
    if [ $? -ne 0 ]; then
        debug "Destroying source snapshot $snap"
        if [ "$DEBUG" != 'true' ]; then
            zfs destroy $snap
        fi
    fi
done

# Destroy target snapshots
for ds_target in $ds_targets; do
    if [ "$ds_target" != "${source_pool}:${source_folder}" ]; then
        target_pool=`echo $ds_target| ${CUT} -d ":" -f1`
        target_folder=`echo $ds_target| ${CUT} -d ":" -f2`
        # Collect snapshots
        debug "Collecting snapshots from ${target_pool}/${target_folder}"
        target_snaps=`ssh $target_pool zfs list -H -r -t snapshot -o name ${target_pool}/${target_folder} 2>/dev/null |
                      ${GREP} "$zfs_replication_snapshot_name"`
        if [ "$target_snaps" == "" ]; then
            error "Could not collect snapshots from ${target_pool}/${target_folder}"
            exit 1
        fi
        for snap in $target_snaps; do
            echo "$snap" | ${GREP} -q "$common_snap"
            if [ $? -ne 0 ]; then
                debug "Destroying target snapshot $snap"
                if [ "$DEBUG" != 'true' ]; then
                    ssh $target_pool "zfs destroy $snap"
                fi
            fi
        done
    fi
done



##
# Remove all completed, suspended, failed, pending and synced jobs
##
stattypes="complete suspended failed pending synced"

for job in $jobs; do
    source $job
    for stattype in $stattypes; do
        if [ "$DEBUG" != 'true' ]; then
            rm /${pool}/zfs_tools/var/replication/jobs/${stattype}/${dataset}_to_${target_pool}\:$(foldertojob $target_folder)_* 2>/dev/null
            if [ $? -eq 0 ]; then
                debug "Removed ${stattype} status for ${dataset}_to_${target_pool}"
            else
                debug "No ${stattype} status jobs for ${dataset}_to_${target_pool}"
            fi
        else
            debug "Would remove ${stattype} status jobs for ${dataset}_to_${target_pool}"
        fi
    done
    # Reset the status to the latest snapshot
    echo "previous_snapshot=\"$common_snap\"" > $job_status

done


##
# Resume scheduling new jobs
##

rm /$source_pool/zfs_tools/var/replication/jobs/suspend_all_jobs


notice "Replication successfully reset for dataset $dataset"

