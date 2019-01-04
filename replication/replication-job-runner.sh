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

job_runner_lock_dir="${TMP}/replication/job-runner"
job_runner_lock="${job_runner_lock_dir}/job-runner"

MKDIR $job_runner_lock_dir

if [ ! -f ${job_runner_lock} ]; then
    touch ${job_runner_lock}
    init_lock ${job_runner_lock}
fi

wait_for_lock ${job_runner_lock} $zfs_replication_job_runner_cycle

if [ $? -ne 0 ]; then
    error "replication_job_runner: failed to get lock in $zfs_replication_job_runner_cycle seconds, aborting"
    exit 1
fi



# Run repeatedly for up 1 minute or $zfs_replication_job_runner_cycle
pending_cycles=0

# Limit to 10 seconds on the terminal

if [ -t 1 ]; then
    zfs_replication_job_runner_cycle=10
fi

while [ $SECONDS -lt $zfs_replication_job_runner_cycle ]; do

    # Parse failed jobs
    
    for pool in $pools; do
        debug "Finding FAILED replication jobs on pool $pool"
        replication_dir="/${pool}/zfs_tools/var/replication/jobs"
        MKDIR ${job_runner_lock_dir}/${pool}
        runner_lock="${job_runner_lock_dir}/${pool}/runner"
        # Lock on running
        if [ ! -f "${runner_lock}" ]; then
            touch "${runner_lock}"
            init_lock "${runner_lock}"
        fi

        wait_for_lock "${runner_lock}"
        if [ $? -ne 0 ]; then
            warning "Could not aquire runner lock for pool $pool"
            continue
        fi

        # Check if all jobs suspended
        if [ -f "$replication_dir/suspend_all_jobs" ]; then
            notice "All jobs suspended. Not running jobs on pool: $pool"
            release_lock "${runner_lock}"
            continue
        fi
        if [ -d "${replication_dir}/failed" ]; then
            jobs=`ls -1 "${replication_dir}/failed"|sort`
            for job in $jobs; do
                suspended=
                failures=
                previous_jobname=
                failure_limit=
                debug "found job: $job"
                # Collect job info
                source "${replication_dir}/failed/${job}"
                wait_for_lock "${job_status}"
                if [ $? -ne 0 ]; then
                    error "Failed to get lock for job status: ${job_status}.  Failing job."
                    continue
                fi
                source "${job_status}"
                release_lock "${job_status}"
                # Test is okay to try again
                if [[ "$failure_limit" == "" || "$failure_limit" == "default" ]]; then
                    failure_limit="$zfs_replication_failure_limit"
                fi
                limit_num=`echo $failure_limit|${SED} 's/[^0-9]//g'`
                limit_unit=`echo $failure_limit|${SED} 's/[^a-z]//g'`
                if [ "$limit_unit" != "" ]; then
                    # Calculate duration since job creation
                    start_secs=`${DATE} -d "$creation_time" +%s`
                    now_secs=`${DATE} -d "$now" +%s`
                    duration_sec="$(( now_secs - start_secs ))"
                    duration_min="$(( (duration_sec + 30) / 60 ))"
                    duration_hour="$(( duration_min / 60 ))"
                    duration_day="$(( duration_hour / 24 ))"
                    duration_week="$(( duration_day / 7 ))"
                    case $limit_unit in
                        'm')
                            unit="minute"
                            if [ $duration_min -lt $limit_num ]; then
                                reschedule='true'
                                remaining=$(( limit_num - duration_min ))
                            else
                                reschedule='false'
                            fi
                            ;;
                        'h')
                            unit="hour"
                            if [ $duration_hour -lt $limit_num ]; then
                                reschedule='true'
                                remaining=$(( limit_num - duration_hour ))
                            else
                                reschedule='false'
                            fi
                            ;;
                    
                        'd')
                            unit="day"
                            if [ $duration_day -lt $limit_num ]; then
                                reschedule='true'
                                remaining=$(( limit_num - duration_day ))
                            else
                                reschedule='false'
                            fi
                            ;;
                        'w')
                            unit="week"
                            if [ $duration_week -lt $limit_num ]; then
                                reschedule='true'
                                remaining=$(( limit_num - duration_week ))
                            else
                                reschedule='false'
                            fi
                            ;;
                    esac
                    if [ "$reschdule" == 'true' ]; then
                        notice "Replication job ${folder} to ${target_pool} has failed $failures times.  Re-trying for up to ${remaining} more ${unit}(s)."            else
                        error "Replication job ${folder} to ${target_pool} has failed for the past ${limit_num} ${unit}(s).  Suspending replication."
                    fi
                else
                    # Limit is based on number of trys
                    if [ $failures -lt $limit_num ]; then
                        # Put the job back in pending status
                        reschedule='true'
                        notice "Replication job ${folder} to ${target_pool} has failed $failures times.  Re-trying up to $limit_num times."
                    else
                        reschedule='false'
                        error "Replication job ${folder} to ${target_pool} has failed $failures times.  Suspending replication."
                    fi
                fi
    
                if [ "$reschedule" == 'true' ]; then
                    mv "${replication_dir}/failed/${job}" "${replication_dir}/pending/${job}"
                else
                    mv "${replication_dir}/failed/${job}" "${replication_dir}/suspended/${job}"
                    update_job_status "${job_status}" "suspended" "true"
                fi        
    
                if [ $SECONDS -gt $zfs_replication_job_runner_cycle ]; then
                    release_lock "${runner_lock}"
                    release_lock ${job_runner_lock}
                    exit 0
                fi

            done # for jobs
        fi
        release_lock "${runner_lock}"
    done
    
    # Parse pending jobs

    pending_cycles=$(( pending_cycles + 1 ))
    
    for pool in $pools; do
        debug "Finding PENDING replication jobs on pool $pool"
        replication_dir="/${pool}/zfs_tools/var/replication/jobs"


        if [ -f "$replication_dir/suspend_all_jobs" ]; then
            notice "All jobs suspended. Not running jobs on pool: $pool"
            continue
        fi
        elapsed=0

        if [ -f "${replication_dir}/schedule_in_progress" ]; then
            # Jump to the next pool.
            continue
        fi

        if [ -d "${replication_dir}/pending" ]; then
            MKDIR ${job_runner_lock_dir}/${pool}
            runner_lock="${job_runner_lock_dir}/${pool}/runner"
            # Lock on running
            if [ ! -f "${runner_lock}" ]; then
                touch "${runner_lock}"
                init_lock "${runner_lock}"
            fi

            wait_for_lock "${runner_lock}"
            if [ $? -ne 0 ]; then
                warning "Could not aquire runner lock for pool $pool"
                continue
            fi


            jobs=`ls -1 "${replication_dir}/pending"|sort`
            for job in $jobs; do
                debug "found job: $job"
                if [ -f "${replication_dir}/pending/${job}" ]; then
                    suspended=
                    previous_jobname=
                    source "${replication_dir}/pending/${job}"
                    wait_for_lock "${job_status}"
                    if [ $? -ne 0 ]; then
                        error "Failed to get lock for job status: ${job_status}.  Failing job."
                        continue
                    fi
                    source "${job_status}"
                    release_lock "${job_status}"
                    if [ -f "${replication_dir}/schedule_in_progress" ]; then
                        # Jump to the next job.
                        continue
                    fi
                    if [ "$suspended" == 'true' ]; then
                        debug "replication is suspended.  Skipping job."
                        continue
                    elif [ "$paused" == 'true' ]; then
                        debug "replication is paused.  Skipping job."
                        continue
                    else
                        # Confirm previous job is complete
                        if [[ "$previous_jobname" != "" && \
                              ! -f "${replication_dir}/synced/${previous_jobname}" && \
                              ! -f "${replication_dir}/complete/${previous_jobname}" ]]; then
                            # Leave this job in pending state
                            debug "Previous job is not complete.   Leave in pending state.  previous_jobname=$previous_jobname"
                            continue
                        else
                            if [ -f "${replication_dir}/schedule_in_progress" ]; then
                                # Jump to the next job.
                                continue
                            fi
                            # Launch the replication job
                            debug "Launching replication job ${job}"
                            mv "${replication_dir}/pending/${job}" "${replication_dir}/running/${job}"
                            launch ./replication-job.sh "${replication_dir}/running/${job}" 
                        fi 
                    fi # $suspended == true
                fi # -f "${replication_dir}/pending/${job}"

                if [ $SECONDS -gt $zfs_replication_job_runner_cycle ]; then
                    release_lock "${runner_lock}"
                    release_lock ${job_runner_lock}
                    exit 0
                fi

            done # for job
     
            release_lock "${runner_lock}"

        fi # if [ -d "${replication_dir}/pending" ]
    done

    sleep 5
    
done # Less than $zfs_replication_job_runner_cycle

notice "Pending job processing cycles: $pending_cycles"

release_lock ${job_runner_lock}

# Clean completed jobs
if [ -d "${replication_dir}/complete" ]; then
    debug "Cleaning completed job folder.   find ${replication_dir}/complete $zfs_replication_completed_job_retention -delete"
    find ${replication_dir}/complete $zfs_replication_completed_job_retention -delete >/dev/null
fi
