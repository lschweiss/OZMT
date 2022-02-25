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

#logging_level="0"



##
#
# Only one copy of this script should run at a time.  
# Otherwise race conditions can cause bad things to happen.
#
##

job_cleaner_lock_dir="${TMP}/replication/job-cleaner"
job_cleaner_lock="${job_cleaner_lock_dir}/job-cleaner"

MKDIR $job_cleaner_lock_dir

if [ ! -f ${job_cleaner_lock} ]; then
    touch ${job_cleaner_lock}
    init_lock ${job_cleaner_lock}
fi

wait_for_lock ${job_cleaner_lock} $zfs_replication_job_cleaner_cycle

if [ $? -ne 0 ]; then
    warning "replication_job_cleaner: failed to get lock in $zfs_replication_job_cleaner_cycle seconds, aborting"
    exit 1
fi

CTMP="${TMP}/replication/cleaning"

MKDIR ${CTMP}
cache_list=${CTMP}/cache_list_$$

clean_cache () {

    local dataset="$1"


    if [ "$dataset" == '' ]; then
        # Clean all of our caches
        debug "Cleaning all caches"
        cache_lists=`ls -1 ${cache_list}*`
        for this_cache_list in $cache_lists; do 
            if [ -f $this_cache_list ]; then
                caches=`cat ${this_cache_list}| ${SORT} -u`
                
                for cache in $caches; do
                    rm -f $cache
                    rm -f ${cache}.lastused
                done
                
                rm -f $this_cache_list
            fi
        done
    else
        # Clean one dataset cache
        debug "Cleaning $dataset cache"
        if [ -f ${cache_list}_${dataset} ]; then
            caches=`cat ${cache_list}_${dataset} | ${SORT} -u`

            for cache in $caches; do
                rm -f $cache
                rm -f ${cache}.lastused
            done

            rm -f ${cache_list}_${dataset}
        fi
    fi

}

ctrl_c () {
    clean_cache
    release_lock ${job_cleaner_lock}
    exit 1
}

trap ctrl_c SIGINT



# Run repeatedly for up 1 minute or $zfs_replication_job_cleaner_cycle

#if [ -t 1 ]; then
#    zfs_replication_job_cleaner_cycle=10
#fi



while [ $SECONDS -lt $zfs_replication_job_cleaner_cycle ]; do

    # Parse synced jobs
    
    for pool in $pools; do
        is_mounted $pool || continue
        debug "Finding synced replication jobs on pool $pool"
        replication_dir="/${pool}/zfs_tools/var/replication/jobs"
        mounted=`zfs get -o value -H mounted ${pool}/zfs_tools`
        if [ "$mounted" != 'yes' ]; then
            notice "zfs_tools not mounted on ${pool}. Skipping"
            continue
        fi
        MKDIR "/${pool}/zfs_tools/var/replication/jobs/cleaning"

        if [ -f "${job_cleaner_lock_dir}/abort_cleaning" ]; then
            notice "Early abort of cleaning requested"
            clean_cache
            release_lock ${job_cleaner_lock}
            rm "${job_cleaner_lock_dir}/abort_cleaning"
            exit 0
        fi

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
        is_mounted $pool || continue
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
                nowork='true'



                
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
                source_snapshots=`(zfs_cache list -t snapshot -r -H -o name ${pool}/${folder} 3>>${cache_list}_${dataset_name}
                    echo $?>${CTMP}/result_$$ ) | ${GREP} "@${previous_snapshot}$"`
                if [ $(cat ${CTMP}/result_$$) -ne 0 ]; then
                    warning "Could not collect source previous snapshots for ${pool}/${folder}."
                    continue
                fi
                # Verify 'previous_snapshot' on all coresponding target folders
                debug "Collecting target previous snapshots ${target_pool}/${target_folder}"
                target_snapshots=`(remote_zfs_cache list -t snapshot -r -H -o name ${target_pool}/${target_folder} 3>>${cache_list}_${dataset_name}
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
                    clean_cache $dataset_name
                    warning "Could not find coresponding previous snapshot to $nomatch on target $target_pool/$target_folder"
                    update_job_status "$job_status" 'clean_missing_snapshot' '+1'
                    continue # Next job
                fi
    
                ##
                # Part #2
                # Collect source folders with 'snapshot'
                ##
                debug "Collecting source snapshots"
                source_snapshots=`(zfs_cache list -t snapshot -r -H -o name ${pool}/${folder} 3>>${cache_list}_${dataset_name}
                    echo $?>${CTMP}/result_$$ ) | ${GREP} "@${snapshot}$"`
                if [ $(cat ${CTMP}/result_$$) -ne 0 ]; then
                    warning "Could not collect source snapshots for ${pool}/${folder}."
                    rm ${CTMP}/result_$$
                    continue
                fi

                rm ${CTMP}/result_$$ 2>/dev/null


                # Verify 'snapshot' on all coresponding target folders
                debug "Collecting target snapshots"
                target_snapshots=`(remote_zfs_cache list -t snapshot -r -H -o name ${target_pool}/${target_folder} 3>>${cache_list}_${dataset_name}
                    echo $?>${CTMP}/result_$$ ) | ${GREP} "@${snapshot}$"`
                if [ $(cat ${CTMP}/result_$$) -ne 0 ]; then
                    warning "Could not collect target snapshots for ${target_pool}/${target_folder}."
                    continue
                fi
            
                rm ${CTMP}/result_$$ 2>/dev/null


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
                    clean_cache ${dataset_name}
                    update_job_status "$job_status" 'clean_missing_snapshot' '+1'
                    continue # Next job
                fi

                ##
                # Part #3
                # We got this far, everything validates.  We can now destroy the 'previous_snapshot' on the source and target.
                ##
                clean='true'
                if [ "$DEBUG" != 'true' ]; then
                    $SSH $target_pool "zfs destroy -d -r \"${target_pool}/${target_folder}@${previous_snapshot}\"" 2> ${CTMP}/destroy_target_snap_$$.txt
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
                rm ${CTMP}/destroy_source_snap_$$.txt 2>/dev/null
                rm ${CTMP}/destroy_target_snap_$$.txt 2>/dev/null

                if [ "$clean" == 'true' ]; then
                    if [ "$DEBUG" != 'true' ]; then
                        notice "Removed previous snapshot ${pool}/${folder}@${previous_snapshot} from dataset ${dataset_name}. Job is complete."
                        echo "completion_time=\"$(job_stamp)\"" >> "${replication_dir}/cleaning/${job}"
                        mv "${replication_dir}/cleaning/${job}" "${replication_dir}/complete/${job}"
                        update_job_status "$job_status" 'clean_failures' '#REMOVE#' \
                            'clean_missing_snapshot' '#REMOVE#' \
                            'last_complete' "$(job_stamp)"
                        #update_job_status "$job_status" 'clean_missing_snapshot' '#REMOVE#'
                        nowork='false'
                    else
                        notice "Would have removed previous snapshot ${pool}/${folder}@${previous_snapshot} from dataset ${dataset_name}. Job is complete."
                    fi
                fi

                ##
                # Part #4
                # Run 'zfs inherit -S' on source zfs properties which are local so the replicated value becomes active
                ##

                local_prop_file="${TMP}/replication/zfs_properties/${dataset_name}/local_zfs_properties"
                replicated_props="${TMP}/replication/zfs_properties/${dataset_name}/replicated_zfs_properties"
                props_to_replicate="${TMP}/replication/zfs_properties_${dataset_name}_$$"
                new_props="${TMP}/replication/zfs_new_properties_${dataset_name}_$$"
                update_err="${TMP}/replication/zfs_properties/property_update_err_$$"
                if [ -f $local_prop_file ]; then
                    wait_for_lock $local_prop_file
                    if [ -f $replicated_props ]; then
                        ${GREP} -v -x -f $replicated_props $local_prop_file > $new_props
                    fi 
                    
                    if [ -f $new_props ]; then
                        lines=`cat $new_props | ${WC} -l`
                        x=0
                        while [ $x -lt $lines ]; do
                            x=$(( x + 1 ))
                            line=`cat $new_props | head -n $x | tail -1`
                            prop_folder=`cat $new_props | head -n $x | tail -1 | ${CUT} -f 1`
                            property=`cat $new_props | head -n $x | tail -1 | ${CUT} -f 2`

                            if [ "$prop_folder" != "" ]; then
                                prop_folder="/${prop_folder}"
                            fi
                            notice "${dataset_name}: Updating $property on ${target_pool}/${target_folder}${prop_folder}"
                            echo -e "zfs inherit -S $property ${target_pool}/${target_folder}${prop_folder}" >> $props_to_replicate
                            echo "$line" >> $replicated_props
                        done 
                    fi
                    unset IFS
                    rm -f $new_props
                    rm $local_prop_file
                    touch $local_prop_file
                    release_lock $local_prop_file
                fi

                if [ -f $props_to_replicate ]; then
                    ${SED} -i '1i#! /bin/bash' $props_to_replicate
                    if [ -t 1 ]; then
                        echo "Executing on ${target_pool}:"
                        cat $props_to_replicate
                    fi
                    ${SSH} ${target_pool} < $props_to_replicate 2>${update_err}
                    if [[ $? -ne 0 && -f ${update_err} ]]; then
                        err_lines=`cat ${update_err} | ${GREP} -v "Pseudo-terminal" | ${WC} -l`
                        if [ $err_lines -ge 1 ]; then
                            if [ -t 1 ]; then
                                cat ${TMP}/property_update_err_$$
                            fi
                            warning "${dataset_name}: Errors running property updates" ${update_err}
                        fi
                    fi
                    rm -f ${TMP}/property_update_err_$$ $props_to_replicate
                fi

                if [ -f "${job_cleaner_lock_dir}/abort_cleaning" ]; then
                    break
                fi

            done # for job
 
            if [ "$nowork" == 'true' ]; then
                # We didn't find any jobs to clean.  Cache may be too out of date.
                debug "No cleaning jobs this cycle.  Cleaning cache."
                clean_cache
                nowork='true'
            fi
                

            if [ -f "${job_cleaner_lock_dir}/abort_cleaning" ]; then
                debug "Early abort of cleaning requested"
                clean_cache
                release_lock ${job_cleaner_lock}
                rm "${job_cleaner_lock_dir}/abort_cleaning"
                exit 0
            fi

            if [ $SECONDS -gt $zfs_replication_job_cleaner_cycle ]; then
                debug "Out of time. Exiting"
                clean_cache
                release_lock ${job_cleaner_lock}
                exit 0
            fi                                                

        fi # if cleaning directory

    done # for pool

    sleep 5
    
done # Less than $zfs_replication_job_cleaner_cycle

clean_cache

release_lock ${job_cleaner_lock}
