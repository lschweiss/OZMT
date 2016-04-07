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


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

. ../zfs-tools-init.sh

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

pools="$(pools)"

if [ -z $reset_replication_timeout ]; then
    reset_replication_timeout=60
fi

show_usage () {
    echo
    echo "Usage: $0 {dataset_name} [{ignore_folder_list}]"
    echo "  {dataset_name}   Name of the data set to clean all replication jobs and"
    echo "                   replication snapshots except the latest fully syncd snapshot."
    echo "                   It then puts the job back in to a status for resuming replication."  
    echo ""
    echo "  {ignore_folder_list} (optional)"
    echo "                   List of folder to ignore sanity check and clean up."
    echo "                   This is primarily used when new ZFS folders are created, that"
    echo "                   have not yet been replicated." 
    echo "                   This should be a comma separated list of ZFS folders within"
    echo "                   the dataset."
    echo ""
    echo "  The host this command is run on must be either the source host for this dataset."
    echo ""
    echo "  This is automatically run after every cut over of a dataset source or can be run"
    echo "  manually to cleanup broken replication jobs."
    echo ""
    echo "  The following data sets are active on this host:"
    for pool in $pools; do
        if [ -d /${pool}/zfs_tools/var/replication/source ]; then
            datasets=`ls -1 /${pool}/zfs_tools/var/replication/source `
            for dataset in $datasets; do
                cat "/${pool}/zfs_tools/var/replication/source/$dataset" | ${GREP} -q "$pool"
                if [ $? -eq 0 ]; then
                    echo "        $dataset"
                fi
            done
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

ignore_folder_list="$2"


die () {

    ##
    # Resume scheduling new jobs
    ##
    
    if [ "$keep_suspended" != 'true' ]; then
        rm /$source_pool/zfs_tools/var/replication/jobs/suspend_all_jobs
        if [ "$scheduling_locked" == 'true' ]; then
            release_lock "/$source_pool/zfs_tools/var/replication/jobs/scheduling"
        fi
        if [ "$runner_locked" == 'true' ]; then
            release_lock "/$source_pool/zfs_tools/var/replication/jobs/runner"
        fi
    else
        debug "Keep suspended set.  Not resuming replication."
    fi
    
    exit $1

}

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

if [ "$ignore_folder_list" != "" ]; then
    debug "Ignoring folders: $ignore_folder_list"
fi

# Where are the targets?
ds_targets=`cat /$pool/zfs_tools/var/replication/targets/${dataset}`

# Find and read the definition(s).

for check_pool in $pools; do
    if [ -d "/$check_pool/zfs_tools/var/replication/jobs/definitions" ]; then
        definitions=`${FIND} "/$check_pool/zfs_tools/var/replication/jobs/definitions/" -type f`
        for definition in $definitions; do
            source $definition
            if [ "$dataset_name" == "$dataset" ]; then
                debug "Found job definition $definition for $dataset"
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
    warning "Must be run on the dataset's source host with the pool $source_pool"
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
        die 1
    fi
done

##
# Handle running jobs
##

# Are there still jobs running?
running_begin=
running_end=
for job in $jobs; do
    source $job
    
        running_jobs=`ls -1 /${source_pool}/zfs_tools/var/replication/jobs/running/ | ${GREP} "^${dataset_name}_to_${target_pool}"`
        debug "Reported running jobs: $running_jobs"
        job_dead='false'
        info_folder=
        zfs_send_pid=
        for running_job in $running_jobs; do
            set -x
            # Test if the job is still running
            if [ -f "${TMP}/replication/job_info.${running_job}" ]; then
                info_folder=`cat "${TMP}/replication/job_info.${running_job}"`
                if [ -f "${info_folder}/zfs_send.pid" ]; then
                    zfs_send_pid=`cat "${info_folder}/zfs_send.pid"`
                    case $os in 
                        'SunOS') 
                            /usr/bin/ptree $zfs_send_pid | ${GREP} 'zfs send' | ${GREP} -q ${dataset_name}
                            result=$?
                            ;;
                        'Linux')
                            pstree -a -n -A -l -p $zfs_send_pid | ${GREP} 'zfs send' | ${GREP} -q ${dataset_name}
                            result=$?
                            ;;
                    esac
                else
                    job_dead='true'
                fi
                # Check if it's running
                if [ $result -ne 0 ]; then
                    job_dead='true'
                fi
            else
                job_dead='true'
            fi

            set +x
 
            if [ "$job_dead" == 'true' ]; then
                # Remove running status
                notice "Replication job $running_job is defunct.  Moving back to pending."
                #mv /$pool/zfs_tools/var/replication/jobs/running/${running_job} \
                #    /$pool/zfs_tools/var/replication/jobs/pending/${running_job}
                #if [[ "$DEBUG" != 'true' &&  -d "$info_folder" ]]; then
                #    rm -rf "$info_folder"
                ##    rm -f "${TMP}/replication/job_info.${running_job}"
                #    rm -f "${TMP}/replication/job_target_info.${running_job}"
                #fi
            else
                notice "Replication job $running_job is still running."
                # Job is still running collect the relevent snapshots
                # TODO:  In order to support multiple replication targets, this needs to collect snapshots for each job
                source /$pool/zfs_tools/var/replication/jobs/running/${running_job}
                running_begin="${previous_snapshot}"
                running_end="${snapshot}"
            fi
        done # for running_job

        if [ "$running_jobs" != "" ]; then
            warning "Running jobs reported for ${dataset_name}. Aborting. "
            die 1
        fi

        if [[ "$wait_for_running" == 'true' && "$job_dead" == 'false' ]]; then
            debug "Waiting for running job(s) to complete for up to $reset_replication_timeout minutes"
            sleep 5
            wait_time=5
            running=0
            while [ $running -eq 0 ]; do
                wait_minutes=$(( wait_time / 60 ))
                if [ $wait_minutes -ge $reset_replication_timeout ]; then
                    error "Waited $reset_replication_timeout minutes for $dataset running jobs to complete.  Giving up."
                    die 1
                fi
                ls -1 "/$pool/zfs_tools/var/replication/jobs/running/" | ${GREP} -q "^${dataset_name}_to_${target_pool}"
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
# Temporarily suspend scheduling and running any new jobs on the source pool
##

wait_for_lock "/$source_pool/zfs_tools/var/replication/jobs/scheduling" 
    if [ $? -ne 0 ]; then
        echo "Could not aquire scheduling lock." 
        exit 1
    fi
scheduling_locked='true'
wait_for_lock "/$source_pool/zfs_tools/var/replication/jobs/runner"
    if [ $? -ne 0 ]; then
        echo "Could not aquire scheduling lock."
        release_lock "/$source_pool/zfs_tools/var/replication/jobs/scheduling"
        exit 1
    fi
runner_locked='true'

echo "Resetting replication for $dataset" > /$source_pool/zfs_tools/var/replication/jobs/suspend_all_jobs



##
# Find the newest common replication snapshot
## 

# Gather a list children folders on the source
# TODO: Filter excluded folders

zfs list -H -r -o name ${source_pool}/${source_folder} | ${TAIL} -n+2 > ${TMP}/reset_replication_child_folders_$$

if [ "$ignore_folder_list" != "" ]; then
    IFS=','
    for ignore_folder in $ignore_folder_list; do
        debug "Stripping $ignore_folder from children folders"
        cat ${TMP}/reset_replication_child_folders_$$ | ${GREP} -v "^${ignore_folder}$" > ${TMP}/reset_replication_child_folders_$$_2
        mv ${TMP}/reset_replication_child_folders_$$_2 ${TMP}/reset_replication_child_folders_$$
    done
    unset IFS
fi 


children_folders=`cat ${TMP}/reset_replication_child_folders_$$`
rm ${TMP}/reset_replication_child_folders_$$

# Gather a list of replication snapshots from the source zfs folder. 
# Reverse sort them so we work from newest to oldest.
replication_snaps=`zfs list -H -r -t snapshot -o name ${pool}/${source_folder} | \
                   ${GREP} "@$zfs_replication_snapshot_name" | \
                   ${SORT} -r`
parent_replication_snaps=`printf '%s\n' "$replication_snaps" | \
                           ${GREP} "^${source_pool}/${source_folder}@"`
parent_valid_snaps=

debug "Found snaps in parent folder ${source_pool}/${source_folder}: $parent_replication_snaps"


# Make sure each snapshot is also in all the children
# Eliminate from the list any snapshot that is not in all children
if [ "$children_folders" != "" ]; then
    debug "Testing if snaps are in children folders"
    for parent_snap in $parent_replication_snaps; do
        valid_snap='true'
        parent_snap_name=`echo $parent_snap|${CUT} -d '@' -f2`
        parent_snap_creation=`zfs get -o value -H -p creation ${pool}/${source_folder}@${parent_snap_name}`
        for child_folder in $children_folders; do
            # Test if child folder was created after the parent snapshot
            child_folder_creation=`zfs get -o value -H -p creation $child_folder`    
            if [ $child_folder_creation -gt $parent_snap_creation ]; then
                debug "Child folder $child_folder was created after parent snapshot.  Skipping."
            else
                child_snaps=`printf '%s\n' "$replication_snaps" | \
                             ${GREP} "^$child_folder@"`
                # Test if snap is good
                echo $child_snaps | ${GREP} -q "$parent_snap_name"
                if [ $? -ne 0 ]; then
                    debug "Parent snapshot ${parent_snap}, is not in child folder $child_folder"
                    valid_snap='false'
                fi
            fi
        done
        if [ "$valid_snap" == 'true' ]; then
            parent_valid_snaps+=" $parent_snap"
        fi
    done
else
    parent_valid_snaps="$parent_replication_snaps"
fi

parent_snap_count=`echo $parent_valid_snaps | ${WC} -w`
if [ $parent_snap_count -eq 0 ]; then
    error "No replication snapshots exist in ${source_pool}/${source_folder} that are properly propigated through all children ZFS folders"
    die 1
else
    debug "Found $parent_snap_count possible snapshot on the source ${source_pool}/${source_folder}"
fi

# From newest to oldest check all targets including children for the snapshot
parent_replication_snaps=`printf '%s\n' "$parent_valid_snaps"` 


for parent_snap in $parent_replication_snaps; do
    valid_snap='true'
    parent_snap_name=`echo $parent_snap|${CUT} -d '@' -f2`
    parent_snap_creation=`zfs get -o value -H -p creation ${pool}/${source_folder}@${parent_snap_name}`

    for ds_target in $ds_targets; do
        if [ "$ds_target" != "${source_pool}:${source_folder}" ]; then
            target_pool=`echo $ds_target| ${CUT} -d ":" -f1`
            target_folder=`echo $ds_target| ${CUT} -d ":" -f2`
            # Collect snapshots
            debug "Collecting snapshots from ${target_pool}/${target_folder}"
            target_snaps=`ssh $target_pool zfs list -H -r -t snapshot -o name ${target_pool}/${target_folder} 2>/dev/null | \
                          ${GREP} "@$zfs_replication_snapshot_name"`
            if [ "$target_snaps" == "" ]; then
                error "Could not collect snapshots from ${target_pool}/${target_folder}"
                die 1
            fi
            target_parent_snaps=`printf '%s\n' "$target_snaps" | ${GREP} "^${target_pool}/${target_folder}@"`
            debug "Checking for snapshot \"$parent_snap_name\" on $ds_target"
            printf '%s\n' "$target_parent_snaps" | ${GREP} -q "$parent_snap_name"
            if [ $? -ne 0 ]; then
                debug "Snapshot not found."
                valid_snap='false'
            fi
            # Check child snaps
            if [[ "${valid_snap}" == 'true' && "$children_folders" != "" ]]; then
                for child_folder in $children_folders; do
                    # Test if source child folder was created after the parent source snapshot
                    child_folder_creation=`zfs get -o value -H -p creation $child_folder`    
                    if [ $child_folder_creation -gt $parent_snap_creation ]; then
                        debug "Child folder $child_folder was created after parent snapshot.  Skipping."
                    else
                        child_folder_short="${child_folder:${#ds_source}}"
                        debug "Checking for snapshot on ${ds_target}${child_folder_short}"
                        printf '%s\n' "$target_snaps" | ${GREP} -q "${target_pool}/${target_folder}${child_folder_short}@${parent_snap_name}"
                        if [ $? -ne 0 ]; then
                            debug "Snapshot not found \"${target_pool}/${target_folder}${child_folder_short}@${parent_snap_name}\""
                            valid_snap='false'
                            break
                        fi
                    fi
                done
            fi
        fi    
    done
    if [ "$valid_snap" == 'true' ]; then
        # This snap is the newest common snapshot
        debug "Success! Snapshot $parent_snap_name is on all targets."
        common_snap="$parent_snap_name"
        break
    fi

done


if [[ "$valid_snap" != 'true' || "$common_snap" == "" ]]; then
    error "Could not find a common snapshot to sync for dataset ${dataset}.   Replication will need to be restarted."
    die 1
fi

if [ "$running_end" != "" ]; then
    if [ "$running_begin" == "$common_snap" ]; then
        notice "Reset replication matched $common_snap on source and target."
        notice "Selecting $running_end as reset snapshot to allow running job to complete."
        common_snap="$running_end"
        snap_grep="${running_begin}\|${common_snap}"
    else
        error "Running zfs send job does not have common beginning snapshot across dataset source and target"
        die 1
    fi
else
    snap_grep="${common_snap}"
fi


##
# Destroy all other replication snapshots
##

# TODO: zfs destroy can have multiple snapshots in one command per zfs folder.   This should be done to speed this process.
# TODO: Use GNU parallel to speed this process too.

# Destroy source snapshots
for snap in $replication_snaps; do
    echo "$snap" | ${GREP} -q "$snap_grep" 
    if [ $? -ne 0 ]; then
        debug "Destroying source snapshot $snap"
        if [ "$DEBUG" != 'true' ]; then
            zfs destroy -d $snap
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
                      ${GREP} "@$zfs_replication_snapshot_name"`
        if [ "$target_snaps" == "" ]; then
            error "Could not collect snapshots from ${target_pool}/${target_folder}"
            die 1
        fi
        for snap in $target_snaps; do
            echo "$snap" | ${GREP} -q "$snap_grep"
            if [ $? -ne 0 ]; then
                debug "Destroying target snapshot $snap"
                if [ "$DEBUG" != 'true' ]; then
                    ssh $target_pool "zfs destroy -d $snap"
                fi
            fi
        done
    fi
done

##
# Reset job status
##





##
# Remove all completed, suspended, failed, pending and synced jobs
##
stat_types="complete suspended failed pending synced cleaning"

debug "Cleaning job status for $dataset"

for job in $jobs; do
    debug "Checking job $job"    
    source $job
    for stat_type in $stat_types; do
        if [ "$DEBUG" != 'true' ]; then
            rm -f /${pool}/zfs_tools/var/replication/jobs/${stat_type}/${dataset}_to_${target_pool}\:$(foldertojob $target_folder)_* 2>/dev/null
            if [ $? -eq 0 ]; then
                debug "Removed ${stat_type} status for ${dataset}_to_${target_pool}"
            else
                debug "No ${stat_type} status jobs for ${dataset}_to_${target_pool}"
            fi
        else
            debug "Would remove ${stat_type} status jobs for ${dataset}_to_${target_pool}"
        fi
    done
    if [ "$running_end" == "" ]; then
        # Reset the status to the latest snapshot
        echo "previous_snapshot=\"$common_snap\"" > $job_status
    fi

done


notice "Replication successfully reset for dataset $dataset"

die 0
