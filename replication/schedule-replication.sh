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

####
####
##
## Data file reference
##
####
####

# Job definition file:
# /${pool}/zfs_tools/var/replication/jobs/definitions/${simple_jobname}/${target_pool}:$(foldertojob $target_folder)
#
# target=
# The target definition.
# {pool}:{folder}
#
# job_status=
# The full path to the job status file.  Defined as:
# /${pool}/zfs_tools/var/replication/jobs/status/${simple_jobname}#${target_pool}:$(foldertojob $target_folder)\"
#
# target_pool=
# The target pool.
# {pool}
#
# target_folder=
# The target folder.
# {folder}
#
# dataset_name=
# Common name of this dataset on at all replication points.
# Provided by filesystem configuration.
#
# pool=
# The source pool
#
# folder=
# The source folder
#
# source_tracker=
# Full path the the source tracking file that is synced between all replication targets.
# /${pool}/zfs_tools/var/replication/source/${dataset_name}
#
# replication_count=
# Number of replication paths defined for this dataset
#
# mode=
# Mode of transport
# L     local replication within the same pool
# m     mbuffer transport
# s     ssh tunnel
# b     bbcp transport
#
# options=
# l     lz4 compress the stream
# g     gzip compress the stream
# o     encrypt the stream with openssl
#
# frequency=
# ####{unit}
# Acceptable units are:
# m     minutes
# h     hours
# d     days
# w     weeks
#
# failure_limit=
# Failures Limit before halting replication.
# Can be a positive integer or time in the same form as Frequency
# Defaults to 5, unless override specified in zfs-config with 'zfs_replication_failure_limit'
#
#
# Job status file:
# Located by job_status variable from above
#
# last_run=
# Date and time of last trigger for this job
#     date +"%F %H:%M:%S%z"
#
# suspended=
# Set to 'true' if the job is suspended and will no longer be secheduled.
#
# failures=
# Count of the number of failures since last successful sync.
#
# queued_jobs=
# The number of queued replication jobs for this dataset.


cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

if [ "x$replication_logfile" != "x" ]; then
    logfile="$replication_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$replication_report" != "x" ]; then
    report_name="$replication_report"
else
    report_name="$default_report_name"
fi

now=`${DATE} +"%F %H:%M:%S%z"`

pools="$(pools)"
pids=

job_runner () {
    if [ -t 1 ]; then
        sleep 10
    else
        sleep 5
    fi
    count=0
    if [ -t 1 ]; then
        limit=1
    else 
        limit=10
    fi
    while [ $count -le $limit ]; do
        launch ./replication-job-runner.sh
        count=$(( count + 1 ))
        sleep 5
    done
}


# Launch job runner

job_runner &
 

# look for jobs to run
for pool in $pools; do
    debug "Looking for replication jobs on pool $pool"
    replication_job_dir="/${pool}/zfs_tools/var/replication/jobs"
    replication_def_dir="${replication_job_dir}/definitions"
    if [ -d "$replication_def_dir" ]; then
        if [ -f "$replication_job_dir/suspend_all_jobs" ]; then
            debug "Skipping job scheduling because $replication_job_dir/suspend_all_jobs is present"
            if test `find "$replication_job_dir/suspend_all_jobs" -mtime +1`; then
                error "Skipping job scheduling because $replication_job_dir/suspend_all_jobs is present for more than 24 hours"
            fi
            continue
        fi
        folder_defs=`ls -1 "$replication_def_dir"|sort`
        for folder_def in $folder_defs; do
            debug "Replication job for $folder_def found"
            target_defs=`ls -1 "${replication_def_dir}/${folder_def}"|sort`
            for target_def in $target_defs; do
                debug "to target $target_def"
                last_run=
                job_definition="${replication_def_dir}/${folder_def}/${target_def}"
                source "${job_definition}"
                if [ -f "${job_status}" ]; then
                    source "${job_status}"
                fi 

                # Test if this is the active dataset
                active=`cat "$source_tracker" 2>/dev/null| head -1`
                if [ "$active" == "" ]; then
                    warning "active copy not set in $source_tracker"
                    continue
                fi
                if [ "$active" == "migrating" ]; then
                    # Pool is being migrated.  Don't schedule new jobs.
                    debug "is being migrated"
                    continue
                fi
                if [ "$active" != "${pool}:${folder}" ]; then
                    # This folder is receiving.
                    debug "is receiving."
                    continue
                fi

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
                    # Jobs are stacking up start increasing the scheduling duration for minute and hour increment jobs
                    if [[ "$freq_unit" == 'm' || "$freq_unit" == 'h' ]]; then
                        freq_num=$(( freq_num * queued_jobs ))
                    fi
                fi

                if [ $queued_jobs -gt $zfs_replication_queue_max_count ]; then
                    # Don't queue any more jobs until we complete one.
                    continue
                fi
                  
                # TODO: add support for replication start days, times
    
                if [ -t 1 ]; then
                    echo "last_run=$last_run"
                    echo "last_run_secs=$last_run_secs"
                    echo "now=$now"
                    echo "now_secs=$now_secs"
                    echo "freq_unit=${freq_unit}"
                    echo "freq_num=${freq_num}"
                    echo "duration"
                    echo "s: $duration_sec"
                    echo "m: $duration_min"
                    echo "h: $duration_hour"
                    echo "d: $duration_day"
                    echo "w: $duration_week"
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
                    
            done # for target_def
        done # for folder_def
        
   
    fi # if [ -d "$replication_def_dir" ]
done # for pool 

# Wait for trigger_replication.sh jobs to completed
for pid in $pids; do
    debug "Waiting for trigger_replication.sh pid $pid to complete"
    wait $pid
done


