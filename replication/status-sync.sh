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

# Keep certain files in sync across all replication hosts

# /{pool}/zfs_tools/var/replication/source/{dataset_name}

# ${zfs_replication_sync_filelist}

pools="$(pools)"

# Handle dataset sources
rm ${TMP}/sync_datafiles_$$ 2> /dev/null

for pool in $pools; do
    debug "Syncing dataset sources for pool $pool"
    datasets=`ls -1 /${pool}/zfs_tools/var/replication/source/`
    for dataset in $datasets; do
        debug "Syncing dataset $dataset"
        targets=`cat /${pool}/zfs_tools/var/replication/targets/${dataset}`
        for target in $targets; do
            debug "Syncing dataset $dataset with target $target"
            # Separate pool and folder
            IFS=':'
            read -r t_pool t_folder <<< "${target}"
            unset IFS
            # Inventory the pool for other operations
            echo $t_pool >> ${TMP}/sync_datafiles_$$
            if [ "$pool" != "$t_pool" ]; then
                zpool list $t_pool &> /dev/null 
                if [ $? -ne 0 ]; then
                    # t_pool is not local, push and pull from the target pool
                    # newest version gets copied, fail silently in the background
                    launch ${RSYNC} -cptgo --update -e ssh \
                        /${pool}/zfs_tools/var/replication/source/${dataset} \
                        ${t_pool}:/${t_pool}/zfs_tools/var/replication/source/${dataset} &> /dev/null || \
                        debug "Could not sync from /${pool}/zfs_tools/var/replication/source/${dataset} to ${t_pool}:/${t_pool}/zfs_tools/var/replication/source/${dataset}"
                    launch ${RSYNC} -cptgo --update -e ssh \
                        ${t_pool}:/${t_pool}/zfs_tools/var/replication/source/${dataset} \
                        /${pool}/zfs_tools/var/replication/source/${dataset} &> /dev/null || \
                        debug "Could not sync from ${t_pool}:/${t_pool}/zfs_tools/var/replication/source/${dataset} to /${pool}/zfs_tools/var/replication/source/${dataset}"
                else
                    # t_pool is local, no ssh necessary
                    ${RSYNC} -cptgo --update \
                        /${pool}/zfs_tools/var/replication/source/${dataset} \
                        /${t_pool}/zfs_tools/var/replication/source/${dataset} &> /dev/null || \
                        debug "Could not sync from /${pool}/zfs_tools/var/replication/source/${dataset} to /${t_pool}/zfs_tools/var/replication/source/${dataset}"
                    ${RSYNC} -cptgo --update \
                        /${t_pool}/zfs_tools/var/replication/source/${dataset} \
                        /${pool}/zfs_tools/var/replication/source/${dataset} &> /dev/null || \
                        debug "Could not sync from /${t_pool}/zfs_tools/var/replication/source/${dataset} to /${pool}/zfs_tools/var/replication/source/${dataset}"
                fi
            fi
        done # for target
    done # for dataset
done # for pool

# Sync other files in ${zfs_replication_sync_filelist}
cat ${TMP}/sync_datafiles_$$|sort -U > ${TMP}/sync_datafiles_sort_$$
all_pools=`cat ${TMP}/sync_datafiles_sort_$$`
rm ${TMP}/sync_datafiles_sort_$$ ${TMP}/sync_datafiles_$$

IFS=':'
for file in ${zfs_replication_sync_filelist}; do
    unset IFS
    if [[ "$file" == *"{pool}"* ]] then
        # Were syncing across all known pools
        for pool in $pools; do
            source_file=`echo $file | ${SED} "s,{pool},${pool},g"`
            for t_pool in $all_pools; do
                if [ "$pool" != "$t_pool" ]; then
                    zpool list $t_pool &> /dev/null
                    if [ $? -ne 0 ]; then
                        # t_pool is not local, push and pull from the target pool, fail silently in the background
                        target_file=`echo $file | ${SED} "s,{pool},${t_pool},g"`
                        launch ${RSYNC} -cptgo --update -e ssh \
                            ${source_file} \
                            ${t_pool}:${target_file} &> /dev/null 
                        launch ${RSYNC} -cptgo --update -e ssh \
                            ${t_pool}:${target_file} \
                            ${source_file} &> /dev/null 
                    else
                        # t_pool is local, no ssh necessary
                        ${RSYNC} -cptgo --update \
                            ${source_file} \
                            ${target_file} &> /dev/null
                        ${RSYNC} -cptgo --update \
                            ${target_file} \
                            ${source_file} &> /dev/null
                    fi
                fi
            done # for t_pool
        done # for pool
    else
        # File is fixed path, sync with all pool holding hosts
        for t_pool in $all_pools; do
            if [ "$pool" != "$t_pool" ]; then
                zpool list $t_pool &> /dev/null
                if [ $? -ne 0 ]; then
                    # t_pool is not local, push and pull from the target pool, fail silently in the background
                    launch ${RSYNC} -cptgo --update -e ssh \
                        ${file} \
                        ${t_pool}:${file} &> /dev/null 
                    launch ${RSYNC} -cptgo --update -e ssh \
                        ${t_pool}:${file} \
                        ${file} &> /dev/null 
                fi
                # Nothing to do for local
            fi
        done # for t_pool
    fi
    IFS=':'
done # for file


                
        
                    
            
