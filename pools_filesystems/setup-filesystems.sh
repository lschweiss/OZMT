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

source ../zfs-tools-init.sh

rm $TOOLS_ROOT/snapshots/jobs/*/* 2> /dev/null

source zfs_functions.sh

# Stop infinite loop
rm "${TMP}/setup_filesystem_replication_children" 2>/dev/null

if [ $# -ne 0 ]; then
    pools="$*"
else
    pools="$(pools)"
fi

# TODO: Add checks to make sure we don't do this while jobs can be disturbed. (Job start times)


for pool in $pools; do
    # Suspend replication
    if [ -d "/${pool}/zfs_tools/var/replication/jobs" ]; then
        debug "Suspending replication on pool $pool"
        echo "Setup filesystems running" > "/${pool}/zfs_tools/var/replication/jobs/suspend_all_jobs"
    fi
done

for pool in $pools; do

    if [ -f "/${pool}/zfs_tools/etc/pool-filesystems" ] ; then
        warning "Using depricated configuration. Creating new configuration in /${pool}/zfs_tools/etc/pool-filesystems.new"
        mkdir "/${pool}/zfs_tools/etc/pool-filesystems.new"
        gen_new_pool_config='true'
        notice "Setting up pool $pool"
        rm /${pool}/zfs_tools/etc/snapshots/jobs/*/* 2> /dev/null
        rm /${pool}/zfs_tools/etc/backup/jobs/*/* 2> /dev/null
        rm /${pool}/zfs_tools/etc/reports/jobs/*/* 2> /dev/null
        source /${pool}/zfs_tools/etc/pool-filesystems
    else 
        if [ -d "/${pool}/zfs_tools/etc/pool-filesystems" ]; then
            rm ${TMP}/setup_filesystem_replication_targets 2>/dev/null
            notice "Setting up pool $pool"
            ls -lhAt /${pool}/zfs_tools/etc/pool-filesystems
            failures=0
            # Determine which definitions have changed since last run 
            ls -1At --color=never /${pool}/zfs_tools/etc/pool-filesystems | \
                ${GREP} -v -P ".+~" | \
                ${SED} '/\.last_setup_run/q' | \
                ${GREP} -v ".last_setup_run" | \
                ${GREP} -v ".replication_setup" | \
                sort | \
                tee ${TMP}/pool-filesystems.update

            if [ -f "/${pool}/zfs_tools/etc/pool-filesystems/.replication_setup" ]; then
                replication_setup='true'
                rm "/${pool}/zfs_tools/etc/pool-filesystems/.replication_setup"
            else
                replication_setup='false'
            fi

            folders=`cat ${TMP}/pool-filesystems.update`
            for folder in $folders; do
                rm /${pool}/zfs_tools/etc/{snapshots,backup,reports,replication}/jobs/*/${pool}%${folder} 2> /dev/null
                notice "Processing folder: $folder"
                source /${pool}/zfs_tools/etc/pool-filesystems/${folder}
                if [ $? -ne 0 ]; then
                    error "Configuration for ${pool}/$(jobtofolder $folder) has failed."
                    failures=$(( failures + 1 ))
                fi
                if [ "$DEBUG" == 'true' ]; then
                    echo "Pausing 10 seconds...."
                    sleep 10
                fi
            done
            if [ $failures -eq 0 ]; then
                debug "All changes successful for pool $pool"
                touch /${pool}/zfs_tools/etc/pool-filesystems/.last_setup_run
            fi

            # Setup children which have been added 
            if [ -f "${TMP}/setup_filesystem_replication_children" ]; then
                children=`cat "${TMP}/setup_filesystem_replication_children"`
                for child in $children; do
                    cat ${TMP}/pool-filesystems.update | ${GREP} -q "^${child}$"
                    if [ $? -ne 0 ]; then
                        notice "Processing additional child folder: $child"
                        folder="$child"
                        source /${pool}/zfs_tools/etc/pool-filesystems/${child}
                        if [ $? -ne 0 ]; then
                            error "Configuration for ${pool}/$(jobtofolder $folder) has failed."
                            failures=$(( failures + 1 ))
                        fi
                    fi
                done
                rm "${TMP}/setup_filesystem_replication_children"
                
            fi

            # Update replication targets
            if [ -f ${TMP}/setup_filesystem_replication_targets ]; then
                t_list=`cat ${TMP}/setup_filesystem_replication_targets|sort -u`
                for t_host in $t_list; do
                    if [ "$DEBUG" == 'true' ]; then
                        debug "Target config updated on ${t_host}.  Debug enabled.  Run manually on the target."
                    else
                        debug "Target config updated on ${t_host}.  Triggering setup run."
                        ssh root@${t_host} "${TOOLS_ROOT}/pools_filesystems/setup-filesystems.sh"
                    fi
                done
                rm ${TMP}/setup_filesystem_replication_targets
            fi
            
        else
            warning "No file system configuration found for $pool"
        fi
    fi

done

#if [ -f "${TMP}/setup_filesystem_reset_replication" ]; then
#    datasets=`cat ${TMP}/setup_filesystem_reset_replication | ${SORT} -u`
#    # Collect folders to ignore
#    ignore_folders=
#    if [ -f "${TMP}/setup_filesystem_reset_replication_ignore" ]; then
#       ignore_folders=`cat "${TMP}/setup_filesystem_reset_replication_ignore" | ${SED} ':a;N;$!ba;s/\n/,/g'`
#    fi
#    for dataset in $datasets; do
#        notice "Resetting replication for dataset: $dataset"
#        export keep_suspended='true'
#        ../replication/reset-replication.sh $dataset $ignore_folders
#    done
#    rm ${TMP}/setup_filesystem_reset_replication
#fi

export keep_suspended='false'

# Resume replication
for pool in $pools; do
    if [ -f "/${pool}/zfs_tools/var/replication/jobs/suspend_all_jobs" ]; then
        notice "Resuming replication for pool $pool"
        rm "/${pool}/zfs_tools/var/replication/jobs/suspend_all_jobs"
    fi
done
