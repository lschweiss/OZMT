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

# Keep certain files in sync across all replication hosts

# /{pool}/zfs_tools/var/replication/source/{dataset_name}

# ${zfs_replication_sync_filelist}

pools="$(pools)"

# Handle dataset sources
rm ${TMP}/sync_datafiles_$$ 2> /dev/null

for pool in $pools; do
    debug "Syncing dataset sources for pool $pool"
    if [ -d /${pool}/zfs_tools/var/replication/source ]; then
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
                        debug "remote sync"
                        launch ${RSYNC} --rsync-path=${RSYNC} -cptgo --update -e ssh \
                            /${pool}/zfs_tools/var/replication/source/${dataset} \
                            ${t_pool}:/${t_pool}/zfs_tools/var/replication/source/${dataset} &> /dev/null || \
                            debug "Could not sync from /${pool}/zfs_tools/var/replication/source/${dataset} to ${t_pool}:/${t_pool}/zfs_tools/var/replication/source/${dataset}"
                        launch ${RSYNC} --rsync-path=${RSYNC} -cptgo --update -e ssh \
                            ${t_pool}:/${t_pool}/zfs_tools/var/replication/source/${dataset} \
                            /${pool}/zfs_tools/var/replication/source/${dataset} &> /dev/null || \
                            debug "Could not sync from ${t_pool}:/${t_pool}/zfs_tools/var/replication/source/${dataset} to /${pool}/zfs_tools/var/replication/source/${dataset}"
                    else
                        debug "local sync"
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
    fi # if -d /${pool}/zfs_tools/var/replication/source
done # for pool

# Sync other files in ${zfs_replication_sync_filelist}
cat ${TMP}/sync_datafiles_$$ | ${SORT} --unique > ${TMP}/sync_datafiles_sort_$$
all_pools=`cat ${TMP}/sync_datafiles_sort_$$`
debug "all_pools: $all_pools"
rm ${TMP}/sync_datafiles_sort_$$ ${TMP}/sync_datafiles_$$


files=`echo ${zfs_replication_sync_filelist} | sed 's,:,\n,g'`
for file in $files; do
    debug "Syncing file $file"
    if [[ "$file" == *"{pool}"* ]]; then
        debug " to pool based folders"
        # Were syncing across all known pools
        for pool in $pools; do 
            debug "   From pool $pool"
            source_file=`echo "/${file}" | ${SED} "s,{pool},${pool},g"`
            debug "       Source file $source_file"
            for t_pool in $all_pools; do
                debug "            to pool $t_pool"
                if [ "$pool" != "$t_pool" ]; then
                    target_file=`echo "/${file}" | ${SED} "s,{pool},${t_pool},g"`
                    debug "          Target file $target_file"
                    zpool list $t_pool &> /dev/null
                    if [ $? -ne 0 ]; then
                        debug "remote sync"
                        # t_pool is not local, push and pull from the target pool, fail silently in the background
                        launch ${RSYNC} --rsync-path=${RSYNC} -cptgo -v --update -e ssh \
                            ${source_file} \
                            ${t_pool}:${target_file} #&> /dev/null 
                        launch ${RSYNC} --rsync-path=${RSYNC} -cptgo -v --update -e ssh \
                            ${t_pool}:${target_file} \
                            ${source_file} #&> /dev/null 
                    else
                        debug "local sync"
                        # t_pool is local, no ssh necessary
                        ${RSYNC} -cptgo -v --update \
                            ${source_file} \
                            ${target_file} #&> /dev/null
                        ${RSYNC} -cptgo -v --update \
                            ${target_file} \
                            ${source_file} #&> /dev/null
                    fi
                fi
            done # for t_pool
        done # for pool
    else
        # File is fixed path, sync with all pool holding hosts
        debug " to fixed path"
        for t_pool in $all_pools; do
            if [ "$pool" != "$t_pool" ]; then
                zpool list $t_pool &> /dev/null
                if [ $? -ne 0 ]; then
                    debug "to host with pool $t_pool"
                    # t_pool is not local, push and pull from the target pool, fail silently in the background
                    launch ${RSYNC} --rsync-path=${RSYNC} -cptgo --update -e ssh \
                        ${file} \
                        ${t_pool}:${file} # &> /dev/null 
                    launch ${RSYNC} --rsync-path=${RSYNC} -cptgo --update -e ssh \
                        ${t_pool}:${file} \
                        ${file} #&> /dev/null 
                else
                    # Nothing to do for local
                    debug "nothing to do for local"
                fi
            fi
        done # for t_pool
    fi
done # for file


                
        
# Sync Samba configurations

debug "Syncing Samba configurations"

for pool in $pools; do
    # Collect samba datasets
    folders=`zfs_cache get -r -H -o name -s local,received $zfs_cifs_property $pool 3>/dev/null`
    for folder in $folders; do  
        debug "Getting dataset for folder $folder"
        dataset=`zfs_cache get -H -o value -s local,received $zfs_dataset_property $folder 3>/dev/null`
        if [ "$dataset" != "" ]; then
            source_folder="/${pool}/zfs_tools/etc/samba/${dataset}"
            targets=`cat /${pool}/zfs_tools/var/replication/targets/${dataset}`
            for target in $targets; do
                if [ "$target" != "${folder}" ]; then
                    debug "Syncing Samba config for dataset $dataset with target $target, folder $folder"
                    # Separate pool and folder
                    IFS=':'
                    read -r t_pool t_folder <<< "${target}"
                    unset IFS

                    target_folder="/${t_pool}/zfs_tools/etc/samba/${dataset}"
                
                    zpool list $t_pool &> /dev/null
                    if [ $? -ne 0 ]; then
                        debug "remote sync "
                        # t_pool is not local, push and pull from the target pool, fail silently in the background
                        debug "   to target"
                        launch ${RSYNC} --rsync-path=${RSYNC} -rcptgo -v --update -e ssh \
                            --exclude=running \
                            ${source_folder}/ \
                            ${t_pool}:${target_folder} #&> /dev/null
                        debug "   to source"
                        launch ${RSYNC} --rsync-path=${RSYNC} -rcptgo -v --update -e ssh \
                            --exclude=running \
                            ${t_pool}:${target_folder}/ \
                            ${source_folder} #&> /dev/null
                    else
                        debug "local sync"
                        # t_pool is local, no ssh necessary
                        debug "   to target"
                        ${RSYNC} -rcptgo -v --update \
                            --exclude=running \
                            ${source_folder}/ \
                            ${target_folder} #&> /dev/null
                        debug "   to source"
                        ${RSYNC} -rcptgo -v --update \
                            --exclude=running \
                            ${target_folder}/ \
                            ${source_folder} #&> /dev/null
                    fi
                fi # if $target
            done # for target
        fi # if $dataset
    done # for folders
done # for pool
                    
            
