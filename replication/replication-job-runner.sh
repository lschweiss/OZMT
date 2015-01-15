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

pools="$(pools)"
now=`${DATE} +"%F %H:%M:%S%z"`

# Parse failed jobs

for pool in $pools; do
    replication_dir="/${pool}/zfs_tools/var/replication/jobs"
    jobs=`ls -1 "${replication_dir}/failed"|sort`
    for job in $jobs; do
        # Collect job info
        source "${replication_dir}/failed/${job}"
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
done

# Parse pending jobs

for pool in $pools; do
    replication_dir="/${pool}/zfs_tools/var/replication/jobs"
    jobs=`ls -1 "${replication_dir}/pending"|sort`
    for job in $jobs; do
        source "${replication_dir}/pending/${job}"
        source "${job_status}"
        if [ "$suspended" == 'true' ]; then
            mv source "${replication_dir}/pending/${job}" "${replication_dir}/suspended/${job}"
        else
            # Confirm previous job is complete
            if [[ ! -f "${replication_dir}/synced/${previous_jobname}" && ! -f "${replication_dir}/complete/${previous_jobname}" ]]; then
                # Leave this job in pending state
                continue
            else
                # Launch the replication job
                mv "${replication_dir}/pending/${job}" "${replication_dir}/running/${job}"
                replication-job.sh "${replication_dir}/running/${job}" & 
            fi
        fi
    done
done


# Clean completed jobs

find "${replication_dir}/complete" $zfs_replication_completed_job_retention -delete

