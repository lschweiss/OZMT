#!/bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2016  Chip Schweiss

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

# fast-zpool-import.sh is drop in replacement for 'zpool import' and will drastically
# decrease the time to import a zpool

# Any parameter passed before the pool name will be preserved and passed to zpool import.
# All imported NFS folders will be mounted in parallel followed by
# "zfs mount" being called in parallel from the root trough the children

# Requires gnu parallel
# GNU Parallel - The Command-Line Power Tool
# http://www.gnu.org/software/parallel/


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

. ../zfs-tools-init.sh


clear; 

trap end_watch SIGHUP SIGINT SIGTERM

end_watch () {

    quit='true'
}

pools="$(pools)"

print_num () {

    local text="$1"
    local num="$2"
    local thresh="$3"

    if [ "$num" == '' ]; then 
        echo -n "$(color)${text}0"
        return
    fi

    if [ "$num" == '0' ]; then
        echo -n "$(color)${text}0"
        return
    fi

    if [ "$thresh" != '' ]; then
        if [ $num -lt $thresh ]; then
            echo -n "$(color green)${text}${num}$(color)"
        else 
            echo -n "$(color red)${text}${num}$(color)"
        fi
    else
        echo -n "$(color green)${text}${num}$(color)"
    fi

    return

}

while [ "$quit" != 'true' ]; do 
    echo -n "\033[0;0f"

    for pool in $pools; do
        echo "                                                                                                 "
        echo -n "Pool ${pool}, jobs: "

        # Collect defined jobs
        replication_job_dir="/${pool}/zfs_tools/var/replication/jobs"
        replication_def_dir="${replication_job_dir}/definitions"
        if [ -d "$replication_def_dir" ]; then 
            if [ -f "$replication_job_dir/suspend_all_jobs" ]; then
                echo " SUSPENDED for all jobs"               
            else
                echo "                       "
            fi
            echo "                                                                                                 "
            folder_defs=`ls -1 "$replication_def_dir"|sort`
            for folder_def in $folder_defs; do

                active=
                source_tracker=
                target_defs=`ls -1 "${replication_def_dir}/${folder_def}"|sort`
                for target_def in $target_defs; do
                    suspended=
                    last_run=
                    job_status=
                    last_complete=
                    active=
                    job_definition="${replication_def_dir}/${folder_def}/${target_def}"
                    source "${job_definition}"
                    echo -n "${dataset_name} to ${target}, ${frequency}"
                    
                    if [ -f "${job_status}" ]; then
                        source "${job_status}"
                    else
                        continue
                    fi
        
                    # Test if this is the active dataset
                    if [ ! -f "$source_tracker" ]; then
                        echo "                                                         "
                        continue
                    fi

                    active=`cat "$source_tracker" 2>/dev/null| head -1`
                    if [ "$active" == "" ]; then
                        echo "WARNING: active copy not set in $source_tracker          "
                        continue
                    fi
                    if [ "$active" == "migrating" ]; then
                        # Dataset is being migrated.  Don't schedule new jobs.
                        echo ", MIGRATING                                              "
                        continue
                    fi
                    if [ "$active" != "${pool}:${folder}" ]; then
                        # This folder is receiving.
                        echo ", RECEIVING                                              "
                        continue
                    fi
                    if [ "$suspended" == 'true' ]; then
                        echo -n ", $(color red)SUSPENDED$(color)"
                    fi

                    jobname="${dataset_name}_to_${target_pool}:$(foldertojob $target_folder)"

                    # TODO:  This is a heavy weight way of counting these since it repeats for every job.
                    #        Probably better to collect this outside the loop and filter for each job."
                    running_jobs=`ls -1 ${replication_job_dir}/running | ${GREP} "${jobname}" | ${WC} -l`
                    pending_jobs=`ls -1 ${replication_job_dir}/pending | ${GREP} "${jobname}" | ${WC} -l`
                    failed_jobs=`ls -1 ${replication_job_dir}/failed | ${GREP} "${jobname}" | ${WC} -l`
                    synced_jobs=`ls -1 ${replication_job_dir}/synced | ${GREP} "${jobname}" | ${WC} -l`
                    cleaning_jobs=`ls -1 ${replication_job_dir}/cleaning | ${GREP} "${jobname}" | ${WC} -l`
                    
                    echo -n ", SENDING                                                 "
                    echo -e -n "\033[55GSynced to: $last_complete \033[92G"
                    echo -e -n "$(print_num 'Pend: ' $pending_jobs 5) "
                    echo -e -n "$(print_num 'Run: ' $running_jobs 2) "
                    echo -e -n "$(print_num 'Fail: ' $failed_jobs 1) "
                    echo -e -n "$(print_num 'Sync: ' $synced_jobs 2) "
                    echo -e -n "$(print_num 'Clean: ' $cleaning_jobs 2)  "
                    
                done # for target_def
                echo "                                                                                                                                   "

            done # for folder_def

        fi # if replication_def_dir
    
    done # for pool

    sleep 0.1

done # while [ 1 ]



