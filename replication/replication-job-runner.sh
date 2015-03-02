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

if [ -t 1 ]; then
    background=''
else
    background='&'
fi

pools="$(pools)"
now=`${DATE} +"%F %H:%M:%S%z"`

# Parse failed jobs

for pool in $pools; do
    debug "Finding FAILED replication jobs on pool $pool"
    replication_dir="/${pool}/zfs_tools/var/replication/jobs"
    if [ -d "${replication_dir}/failed" ]; then
        jobs=`ls -1 "${replication_dir}/failed"|sort`
        for job in $jobs; do
            debug "found job: $job"
            # Collect job info
            source "${replication_dir}/failed/${job}"
            wait_for_lock "${job_status}"
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

        done
    fi 
done

# Parse pending jobs

for pool in $pools; do
    debug "Finding PENDING replication jobs on pool $pool"
    replication_dir="/${pool}/zfs_tools/var/replication/jobs"
    if [ -d "${replication_dir}/pending" ]; then
        jobs=`ls -1 "${replication_dir}/pending"|sort`
        for job in $jobs; do
            debug "found job: $job"
            if [ -f "${replication_dir}/pending/${job}" ]; then
                source "${replication_dir}/pending/${job}"
                wait_for_lock "${job_status}"
                source "${job_status}"
                release_lock "${job_status}"
                if [ "$suspended" == 'true' ]; then
                    debug "replication is suspended.  Suspending job."
                    mv "${replication_dir}/pending/${job}" "${replication_dir}/suspended/${job}"
                else
                    # Confirm previous job is complete
                    if [[ "$previous_jobname" != "" && \
                          ! -f "${replication_dir}/synced/${previous_jobname}" && \
                          ! -f "${replication_dir}/complete/${previous_jobname}" ]]; then
                        # Leave this job in pending state
                        debug "Previous job is not complete.   Leave in pending state.  previous_jobname=$previous_jobname"
                        continue
                    else
                        # Launch the replication job
                        debug "Launching replication job"
                        mv "${replication_dir}/pending/${job}" "${replication_dir}/running/${job}"
                        launch ./replication-job.sh "${replication_dir}/running/${job}" 
                    fi 
                fi # $suspended == true
            fi # -f "${replication_dir}/pending/${job}"
        done # for job
    fi # if [ -d "${replication_dir}/pending" ]
    # Clean completed jobs
    if [ -d "${replication_dir}/complete" ]; then
        debug "Cleaning completed job folder.   find ${replication_dir}/complete $zfs_replication_completed_job_retention -delete"
        find ${replication_dir}/complete $zfs_replication_completed_job_retention -delete
    fi
done



