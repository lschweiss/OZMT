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

now=`{DATE} +"%F %H:%M:%S%z"`

pools="$(pools)"

for pool in $pools; do
    replication_def_dir="/${pool}/zfs_tools/var/replication/jobs/definition"
    if [ -d "$replication_def_dir" ]; then
        folder_defs=`ls -1 "$replication_def_dir"|sort`
        for folder_def in $folder_defss; do
            target_defs=`ls -1 "${replication_def_dir}/${folder_defs}"|sort`
            for target_def in $target_defs; do
                last_run=
                job_definition="${replication_def_dir}/${folder_def}/${target_def}"
                source "${job_definition}"
                if [ -f "${job_status}" ]; then
                    source "${job_status}"
                fi 

                # Test if this is the active dataset
                active=`cat "$source_tracker"`
                if [ "$active" != "${pool}:${folder}" ]; then
                    # This folder is receiving.
                    continue
                fi
                # Test if $frequency has passed since last run
                if [ "$last_run" == "" ]; then
                    # Never run before trigger first run 
                    ./trigger-replication.sh "$job_definition" &
                    continue
                fi     
                last_run_secs=`${DATE} -d "$last_run" +%s`
                now_sec=`${DATE} -d "$now" +%s`
                duration_sec="$(( now_secs - last_run_secs ))"
                duration_min="$(( (duration_sec + 30) / 60 ))"
                duration_hour="$(( duration_min / 60 ))"
                duration_day="$(( duration_hour / 24 ))"
                duration_week="$(( duration_day / 7 ))"

                freq_num=`echo $frequency|${SED} 's/[^0-9]//g'`
                freq_unit=`echo $frequency|${SED} 's/[^a-z]//g'`

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

                case $freq_unit in 
                    'm')
                        if [ $duration_min -ge $freq_num ]; then
                            ./trigger-replication.sh "${job_definition}" &
                        fi
                        ;;
                    'h')
                        if [ $duration_hour -ge $freq_num ]; then
                            ./trigger-replication.sh "${job_definition}" &
                        fi
                        ;;
                    'd')
                        if [ $duration_day -ge $freq_num ]; then
                            ./trigger-replication.sh "${job_definition}" &
                        fi
                        ;;
                    'w')
                        if [ $duration_week -ge $freq_num ]; then
                            ./trigger-replication.sh "${job_definition}" &
                        fi
                        ;;
                    *)
                        error "Invalid replication frequency ($frequency) specified for $folder to $target"
                        ;;
                esac 
                    
            done
        done
    fi
done 
