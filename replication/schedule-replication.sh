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

now=`${DATE} +"%F %H:%M:%S%z"`

pools="$(pools)"
pids=

sync_now="$1"


# look for jobs to run
for pool in $pools; do
    debug "Looking for replication jobs on pool $pool"
    replication_job_dir="/${pool}/zfs_tools/var/replication/jobs"
    replication_def_dir="${replication_job_dir}/definitions"
    schedule_lock_dir="${TMP}/replication/scheduling"
    schedule_lock="${schedule_lock_dir}/scheduling-${pool}"
    mkdir -p "${schedule_lock_dir}"
    if [ -d "$replication_def_dir" ]; then
        # Lock on scheduling
        if [ ! -f "${schedule_lock}" ]; then
            touch "${schedule_lock}"
            init_lock "${schedule_lock}"
        fi
        wait_for_lock "${schedule_lock}"
        if [ $? -ne 0 ]; then
            warning "Could not aquire scheduling lock for pool $pool"
            continue
        fi

        if [ -f "$replication_job_dir/suspend_all_jobs" ]; then
            debug "Skipping job scheduling because $replication_job_dir/suspend_all_jobs is present"
            if test `find "$replication_job_dir/suspend_all_jobs" -mmin +${zfs_replication_suspended_error_time}`; then
                error "Skipping relication because $replication_job_dir/suspend_all_jobs is present for more than ${zfs_replication_suspended_error_time} minutes.  Reason: $(cat $replication_job_dir/suspend_all_jobs)"
            fi
            release_lock "${schedule_lock}"
            continue
        fi

        folder_defs=`ls -1 "$replication_def_dir"|sort`
        for folder_def in $folder_defs; do
            active=
            source_tracker=
            debug "Replication job for $folder_def found"
            target_defs=`ls -1 "${replication_def_dir}/${folder_def}"|sort`
            for target_def in $target_defs; do
                suspended=
                debug "to target $target_def"
                last_run=
                job_status=
                job_definition="${replication_def_dir}/${folder_def}/${target_def}"
                source "${job_definition}"
                if [ -f "${job_status}" ]; then
                    wait_for_lock "${job_status}"
                    source "${job_status}"
                    release_lock "${job_status}"
                else
                    touch "${job_status}"
                    init_lock "${job_status}"
                fi


                # Test if this is the active dataset
                if [ ! -f "$source_tracker" ]; then
                    warning "Source tracker not defined for dataset $dataset_name"
                    continue
                fi

                active=`cat "$source_tracker" 2>/dev/null| head -1`
                if [ "$active" == "" ]; then
                    warning "active copy not set in $source_tracker"
                    continue
                fi
                if [ "$active" == "migrating" ]; then
                    # Dataset is being migrated.  Don't schedule new jobs.
                    debug "is being migrated"
                    continue
                fi
                if [ "$active" != "${pool}:${folder}" ]; then
                    # This folder is receiving.
                    debug "is receiving."
                    # Test if $frequency has passed since last cleanup run





                    
                    continue
                fi

                if [ "$sync_now" == "" ]; then
                    # Test if $frequency has passed since last run
                    if [ "$last_run" == "" ]; then
                        # Never run before trigger first run 
                        debug "triggering first run."
                        init_lock "${job_status}"
                        launch ./trigger-replication.sh "$job_definition"
                        pids="$pids $launch_pid"
                        continue
                    fi     
                    last_run_secs=`${DATE} -d "$last_run" +%s`
                    now_secs=`${DATE} -d "$now" +%s`
                    duration_sec="$(( now_secs - last_run_secs ))"
                    # Round up to nearest minute
                    duration_min="$(( (duration_sec + 30) / 60 ))"
                    # no more rounding
                    duration_hour="$(( duration_min / 60 ))"
                    duration_day="$(( duration_hour / 24 ))"
                    duration_week="$(( duration_day / 7 ))"

                    freq_num=`echo $frequency|${SED} 's/[^0-9]//g'`
                    freq_unit=`echo $frequency|${SED} 's/[^a-z]//g'`

                    if [ "$queued_jobs" == "" ]; then
                        queued_jobs=0
                    fi

                    # Based on number queued jobs, increase the duration between job creation.
                    if [ $queued_jobs -gt $zfs_replication_queue_delay_count ]; then
                        # Jobs are stacking up start increasing the scheduling duration for second, minute and hour increment jobs
                        if [[ "$freq_unit" == 's' || "$freq_unit" == 'm' ]]; then
                            freq_num=$(( freq_num * queued_jobs * queued_jobs ))
                        fi
                        if [ "$freq_unit" == 'h' ]; then
                            freq_num=$(( freq_num * queued_jobs ))
                        fi
                    fi

                    if [ $queued_jobs -gt $zfs_replication_queue_max_count ]; then
                        # Don't queue any more jobs until we complete one.
                        continue
                    fi
                      
                    # TODO: add support for replication start days, times
    
                    if [ -t 1 ]; then
                        echo "queued_jobs=$queued_jobs"
                        echo "last_run=$last_run"
                        echo "last_run_secs=$last_run_secs"
                        echo "now=$now"
                        echo "now_secs=$now_secs"
                        echo "frequency=$frequency"
                        echo "freq_unit=${freq_unit}"
                        echo "freq_num=${freq_num}"
                        echo "duration"
                        echo "s: $duration_sec"
                        echo "m: $duration_min"
                        echo "h: $duration_hour"
                        echo "d: $duration_day"
                        echo "w: $duration_week"
                    fi

                    if [ "$suspended" == 'true' ]; then
                        if [ $duration_min -ge $zfs_replication_suspended_error_time ]; then
                            error "Replication for dataset $dataset_name has been suspended for more than $zfs_replication_suspended_error_time minutes"
                        fi
                        continue
                    fi

                    case $freq_unit in 
                        'm')
                            if [ $duration_min -ge $freq_num ]; then
                                debug "hasn't run in $freq_num minutes.  Triggering"
                                launch ./trigger-replication.sh "${job_definition}" 
                                pids="$pids $launch_pid"
                            fi
                            ;;
                        'h')
                            if [ $duration_hour -ge $freq_num ]; then
                                debug "hasn't run in $freq_num hours.  Triggering"
                                launch ./trigger-replication.sh "${job_definition}" 
                                pids="$pids $launch_pid"
                            fi
                            ;;
                        'd')
                            if [ $duration_day -ge $freq_num ]; then
                                debug "hasn't run in $freq_num days.  Triggering"
                                launch ./trigger-replication.sh "${job_definition}" 
                                pids="$pids $launch_pid"
                            fi
                            ;;
                        'w')
                            if [ $duration_week -ge $freq_num ]; then
                                debug "hasn't run in $freq_num weeks.  Triggering"
                                launch ./trigger-replication.sh "${job_definition}"
                                pids="$pids $launch_pid"
                            fi
                            ;;
                        *)
                            error "Invalid replication frequency ($frequency) specified for $folder to $target"
                            ;;
                    esac
                    
                else
                    if [ "$dataset_name" == "$sync_now" ]; then
                        notice "Triggering replication for $dataset_name"
                        launch ./trigger-replication.sh "${job_definition}"
                    fi
                fi # if $sync_now

            done # for target_def
        done # for folder_def

        release_lock "${schedule_lock}"

    fi # if [ -d "$replication_def_dir" ]
    
done # for pool 

# Wait for trigger_replication.sh jobs to completed
for pid in $pids; do
    debug "Waiting for trigger_replication.sh pid $pid to complete"
    wait $pid
done

for pool in ${pools}; do
    replication_job_dir="/${pool}/zfs_tools/var/replication/jobs"
    rm -f "${replication_job_dir}/schedule_in_progress"
done


