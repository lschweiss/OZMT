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
now=`${DATE} +"%F %H:%M:%S%z"`




##
#
# Only one copy of this script should run at a time.  
# Otherwise race conditions can cause bad things to happen.
#
##

job_cleaner_lock_dir="${TMP}/replication/job-cleaner"
job_cleaner_lock="${job_cleaner_lock_dir}/job-cleaner"

mkdir -p $job_cleaner_lock_dir

if [ ! -f ${job_cleaner_lock} ]; then
    touch ${job_cleaner_lock}
    init_lock ${job_cleaner_lock}
fi

wait_for_lock ${job_cleaner_lock} $zfs_replication_job_cleaner_cycle

if [ $? -ne 0 ]; then
    error "replication_job_cleaner: failed to get lock in $zfs_replication_job_cleaner_cycle seconds, aborting"
    exit 1
fi

CTMP="${TMP}/replication/cleaning"

mkdir -p ${CTMP}
cache_list=${CTMP}/cache_list_$$

clean_cache () {
    # Clean our cache
    debug "Cleaning cache"
    if [ -f $cache_list ]; then
        caches=`cat ${cache_list}| ${SORT} -u`
        
        for cache in $caches; do
            rm -f $cache
        done
        
        rm -f $cache_list
    fi

}

ctrl_c () {
    clean_cache
    exit 1
}

trap ctrl_c SIGINT



# Run repeatedly for up 1 minute or $zfs_replication_job_cleaner_cycle


while [ $SECONDS -lt $zfs_replication_job_cleaner_cycle ]; do

    # Parse synced jobs
    
    for pool in $pools; do
        debug "Finding synced replication jobs on pool $pool"
        replication_dir="/${pool}/zfs_tools/var/replication/jobs"
        mkdir -p "/${pool}/zfs_tools/var/replication/jobs/cleaning"
        # Check if all jobs suspended
        if [ -f "$replication_dir/suspend_all_jobs" ]; then
            notice "All jobs suspended. Not running clean up jobs on pool: $pool"
            continue
        fi
        if [ -d "${replication_dir}/synced" ]; then
            jobs=`ls -1 "${replication_dir}/synced"|sort`
            for job in $jobs; do
                #debug "found job: $job"
                # Collect job info
                source "${replication_dir}/synced/${job}"
                
                # Validate that this pool is still the source
                data_source=`cat /${pool}/zfs_tools/var/replication/source/${dataset_name}`    
                if [ "$data_source" != "${pool}:${folder}" ]; then
                    # Primary data source moved
                    notice "Primary dataset has moved for $dataset_name removing job $job"
                    rm "${replication_dir}/synced/${job}"
                    continue
                fi

                if [ "$previous_jobname" == "" ]; then
                    # This is the first replication job since replication start or previous reset
                    if [ "$previous_snapshot" != "" ]; then
                        debug "This is the first replication job since replication start or previous reset, cleaning job $job"
                        mv "${replication_dir}/synced/${job}" "${replication_dir}/cleaning/"
                    else
                        debug "No previous snapshot for job ${job}.  Moving to complete"
                        echo "completion_time=\"$(job_stamp)\"" >> "${replication_dir}/synced/${job}"
                        mv "${replication_dir}/synced/${job}" "${replication_dir}/complete/"
                        update_job_status "$job_status" 'clean_failures' '#REMOVE#' \
                            'clean_missing_snapshot' '#REMOVE#' \
                            'last_complete' "$(job_stamp)"

                    fi
                else
                    # Confirm previous job is in complete status
                    if [ -f ${replication_dir}/complete/${previous_jobname} ]; then
                        debug "Previous job is complete, cleaning job $job"
                        mv "${replication_dir}/synced/${job}" "${replication_dir}/cleaning/"
                    fi
                fi
    
            done
        fi 
    done
    
    # Parse cleaning jobs

    for pool in $pools; do
        debug "Finding cleaning replication jobs on pool $pool"
        replication_dir="/${pool}/zfs_tools/var/replication/jobs"
        # Check if all jobs suspended
        if [ -f "$replication_dir/suspend_all_jobs" ]; then
            notice "All jobs suspended. Not running clean up jobs on pool: $pool"
            continue
        fi
        if [ -d "${replication_dir}/cleaning" ]; then
            jobs=`ls -1 "${replication_dir}/cleaning" | ${SORT}`
            for job in $jobs; do
                clean_failures=0
                clean_missing_snapshot=0
                suspended=
                last_snapshot=
                last_jobname=
                last_run=
                failures=
                queued_jobs=
                last_complete=
                jobname=
                previous_jobname=
                snapshot=
                previous_snapshot=



                
                debug "found job: $job"
                # Collect job info
                source "${replication_dir}/cleaning/${job}"

                source "${job_status}"

                if [ "$suspended" == 'true' ]; then
                    debug "Replication suspended for ${dataset_name}. Skipping cleaning"
                    continue
                fi

                ##
                # Trap repeating failures
                ##

                if [ $clean_missing_snapshot -ge 2 ]; then
                    warning "Attempting clean job $job $clean_missing_snapshot times."
                fi

                if [ $clean_missing_snapshot -ge 4 ]; then
                    error "Suspending replication on ${dataset_name}.  Previous snapshot is missing."
                    update_job_status "${job_status}" 'suspended' 'true'
                    continue
                fi

                if [ $clean_failures -ge 2 ]; then
                    error "Suspending replication on ${dataset_name}.  Repeated attempts to clean previous snapshots has failed."
                    update_job_status "${job_status}" 'suspended' 'true'
                    continue
                fi
                

                # Validate that this pool is still the source
                data_source=`cat /${pool}/zfs_tools/var/replication/source/${dataset_name}`
                if [ "$data_source" != "${pool}:${folder}" ]; then
                    # Primary data source moved
                    notice "Primary dataset has moved for $dataset_name removing job $job"
                    rm "${replication_dir}/cleaning/${job}"
                    continue
                fi

                ##
                # Part #1
                # Collect source folder snapshots with 'previous_snapshot'
                ##
                debug "Collecting source previous snapshots ${pool}/${folder}"
                source_snapshots=`(zfs_cache list -t snapshot -r -H -o name ${pool}/${folder} 3>>${cache_list}
                    echo $?>${CTMP}/result_$$ ) | ${GREP} "@${previous_snapshot}$"`
                if [ $(cat ${CTMP}/result_$$) -ne 0 ]; then
                    warning "Could not collect source previous snapshots for ${pool}/${folder}."
                    continue
                fi
                # Verify 'previous_snapshot' on all coresponding target folders
                debug "Collecting target previous snapshots ${target_pool}/${target_folder}"
                target_snapshots=`(remote_zfs_cache list -t snapshot -r -H -o name ${target_pool}/${target_folder} 3>>${cache_list} 
                    echo $?>${CTMP}/result_$$ ) | ${GREP} "@${previous_snapshot}$"`
                if [ $(cat ${CTMP}/result_$$) -ne 0 ]; then
                    warning "Could not collect target previous snapshots for ${target_pool}/${target_folder}."
                    continue
                fi

                match='false'
                for source_snapshot in $source_snapshots; do 
                    #debug "Checking source snapshot: $source_snapshot"
                    # Strip pool/folder
                    test_source="${source_snapshot#"${pool}/${folder}"}"

                    match='false'
                    for target_snapshot in $target_snapshots; do
                        # Strip pool/folder
                        test_target="${target_snapshot#"${target_pool}/${target_folder}"}"

                        # Check for match
                        if [ "$test_source" == "$test_target" ]; then
                            #debug "      $souce_snapshot matches"
                            match='true'
                            break
                        fi
                        
                    done
                    if [ "$match" == 'false' ]; then
                        debug "No match found."
                        nomatch="$source_snapshot"
                        break
                    fi        
                done
                
                if [ "$match" == 'false' ]; then
                    clean_cache
                    warning "Could not find coresponding previous snapshot to $nomatch on target $target_pool/$target_folder"
                    update_job_status "$job_status" 'clean_missing_snapshot' '+1'
                    continue # Next job
                fi
    
                ##
                # Part #2
                # Collect source folders with 'snapshot'
                ##
                debug "Collecting source snapshots"
                source_snapshots=`(zfs_cache list -t snapshot -r -H -o name ${pool}/${folder} 3>>${cache_list} 
                    echo $?>${CTMP}/result_$$ ) | ${GREP} "@${snapshot}$"`
                if [ $(cat ${CTMP}/result_$$) -ne 0 ]; then
                    warning "Could not collect source snapshots for ${pool}/${folder}."
                    continue
                fi


                # Verify 'snapshot' on all coresponding target folders
                debug "Collecting target snapshots"
                target_snapshots=`(remote_zfs_cache list -t snapshot -r -H -o name ${target_pool}/${target_folder} 3>>${cache_list}
                    echo $?>${CTMP}/result_$$ ) | ${GREP} "@${snapshot}$"`
                if [ $(cat ${CTMP}/result_$$) -ne 0 ]; then
                    warning "Could not collect target snapshots for ${target_pool}/${target_folder}."
                    continue
                fi


                match='false'
                for source_snapshot in $source_snapshots; do
                    #debug "Checking source snapshot: $source_snapshot"
                    # Strip pool/folder
                    test_source="${source_snapshot#"${pool}/${folder}"}"

                    match='false'
                    for target_snapshot in $target_snapshots; do
                        # Strip pool/folder
                        test_target="${target_snapshot#"${target_pool}/${target_folder}"}"

                        # Check for match
                        if [ "$test_source" == "$test_target" ]; then
                            #debug "      matches"
                            match='true'
                            break
                        fi

                    done
                    if [ "$match" == 'false' ]; then
                        debug "No match found."
                        nomatch="$source_snapshot"
                        break
                    fi
                done

                if [ "$match" == 'false' ]; then
                    debug "Could not find coresponding snapshot to $nomatch on target $target_pool/$target_folder"
                    clean_cache
                    update_job_status "$job_status" 'clean_missing_snapshot' '+1'
                    continue # Next job
                fi

                ##
                # Part #3
                # We got this far, everything validates.  We can now destroy the 'previous_snapshot' on the source and target.
                ##
                clean='true'
                if [ "$DEBUG" != 'true' ]; then
                    ssh $target_pool "zfs destroy -d -r \"${target_pool}/${target_folder}@${previous_snapshot}\"" 2> ${CTMP}/destroy_target_snap_$$.txt
                    if [ $? -ne 0 ]; then
                        clean='false'
                        error "Failed to destroy target snapshot ${target_pool}/${target_folder}@${previous_snapshot}" ${CTMP}/destroy_target_snap_$$.txt
                        update_job_status "$job_status" 'clean_failures' '+1'
                    fi

                    if [ "$clean" == 'true' ]; then 
                        zfs destroy -d -r "${pool}/${folder}@${previous_snapshot}" 2> ${CTMP}/destroy_source_snap_$$.txt
                        if [ $? -ne 0 ]; then
                            cat ${CTMP}/destroy_source_snap_$$.txt | ${GREP} -q "dataset is busy"
                            if [ $? -ne 0 ]; then
                                zfs holds "${pool}/${folder}@${previous_snapshot}" >> ${CTMP}/destroy_source_snap_$$.txt
                                zfs userrefs "${pool}/${folder}@${previous_snapshot}" >> ${CTMP}/destroy_source_snap_$$.txt
                                clean='false'
                                error "Failed to destroy source snapshot ${pool}/${folder}@${previous_snapshot}" ${CTMP}/destroy_source_snap_$$.txt
                                update_job_status "$job_status" 'clean_failures' '+1'
                            else
                                warning "Destroy source snapshot ${pool}/${folder}@${previous_snapshot} was defered"
                            fi
                        fi
                    fi
                fi

                if [ "$clean" == 'true' ]; then
                    if [ "$DEBUG" != 'true' ]; then
                        notice "Removed previous snapshot ${pool}/${folder}@${previous_snapshot} from dataset ${dataset_name}. Job is complete."
                        echo "completion_time=\"$(job_stamp)\"" >> "${replication_dir}/cleaning/${job}"
                        mv "${replication_dir}/cleaning/${job}" "${replication_dir}/complete/${job}"
                        update_job_status "$job_status" 'clean_failures' '#REMOVE#' \
                            'clean_missing_snapshot' '#REMOVE#' \
                            'last_complete' "$(job_stamp)"
                        #update_job_status "$job_status" 'clean_missing_snapshot' '#REMOVE#'
                    else
                        notice "Would have removed previous snapshot ${pool}/${folder}@${previous_snapshot} from dataset ${dataset_name}. Job is complete."
                    fi
                fi

            done # for job
        fi # if cleaning directory

    done # for pool

    sleep 5
    
done # Less than $zfs_replication_job_cleaner_cycle

clean_cache

release_lock ${job_cleaner_lock}
