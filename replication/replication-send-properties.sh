#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2017  Chip Schweiss

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

send_properties_lock_dir="${TMP}/replication/send-properties"
send_properties_lock="${send_properties_lock_dir}/send-properties"

MKDIR $send_properties_lock_dir

if [ ! -f ${send_properties_lock} ]; then
    touch ${send_properties_lock}
    init_lock ${send_properties_lock}
fi

wait_for_lock ${send_properties_lock} $zfs_replication_send_properties_cycle

if [ $? -ne 0 ]; then
    warning "replication_send_properties: failed to get lock in $zfs_replication_send_properties_cycle seconds, aborting"
    exit 1
fi



for pool in $pools;do
    replication_folders=`zfs_cache get -r -H -o name -s local,received $zfs_replication_property $pool 3>/dev/null`
    
    for replication_folder in $replication_folders; do 
        dataset=`zfs_cache get -H -o value -s local,received $zfs_dataset_property $replication_folder 3>/dev/null`
        if [ "$dataset" == '' ]; then
            error "Dataset not defined on $replication_folder, however, replication is"
            continue
        fi
        
        ds_source=`cat /${pool}/zfs_tools/var/replication/source/${dataset}`

        ##
        # Is this the source host?
        ##
        
        source_pool=`echo "$ds_source" | ${CUT} -d ":" -f 1`
        source_folder=`echo "$ds_source" | ${CUT} -d ":" -f 2`
        
        if islocal $source_pool; then
            debug "Confirmed running on the source host."
        else
            debug "Skipping.  ${dataset} source not on this host on $pool"
            continue
        fi
        
        
        ##
        # Is it unanimous where the source is?
        ##

        target_count=`zfs_cache get -o value -H ${zfs_replication_property}:endpoints $replication_folder 3>/dev/null`
        if [ "$target_count" = '-' ]; then
            error "${dataset}: Replication defined, however, ${zfs_replication_property}:endpoints is not set on $replication_folder"
            continue
        fi

        target=0
        skip='false'

        while [ $target -lt $target_count ]; do
            target=$(( target + 1 ))
            this_target=`zfs_cache get -o value -H ${zfs_replication_property}:endpoint:${target} $replication_folder 3>/dev/null`
            if [ "$this_target" == '-' ]; then
                error "${dataset}: Replication defined, however, ${zfs_replication_property}:endpoint:${target} is not set on $replication_folder"
                skip='true'
                continue
            fi
            target_pool=`echo "$this_target" | ${CUT} -d ":" -f 1`
            target_folder=`echo "$this_target" | ${CUT} -d ":" -f 2`
        
            debug "Checking dataset source for target $this_target"
            check_source=`${SSH} root@${target_pool} cat /${target_pool}/zfs_tools/var/replication/source/$dataset`
            if [ "$check_source" != "$ds_source" ]; then
                error "Dataset source is not consistent at all targets.  Target $target reports source to be $check_source.  My source: $ds_source"
                skip='true'
                continue
            else
                debug "${dataset}: Dataset source confirmed on $this_target"
            fi
        done

        if [ "$skip" == 'true' ]; then
            continue
        fi

        
    
        ##
        # Push locally set zfs properties to the target
        ##

        # Collect properties

        folder_list=`zfs list -o name -H -t filesystem -r $replication_folder`

        updates='false'

        MKDIR "${TMP}/replication/zfs_properties/${dataset}"

        post_sync_file="${TMP}/replication/zfs_properties/${dataset}/local_zfs_properties"


        if [ ! -f $post_sync_file ]; then
            MKDIR ${TMP}/replication/zfs_properties/${dataset}
            touch $post_sync_file
            init_lock $post_sync_file
        fi
        wait_for_lock $post_sync_file
        rm $post_sync_file
        touch $post_sync_file


        for folder in $folder_list; do
            child="${folder:${#replication_folder}}"
            local_properties=`zfs get -s local,default,inherited -o property -H all ${replication_folder}${child} | ${GREP} -v '^quota$' | ${GREP} -v '^refquota$'`
            for property in $local_properties; do
                updates='true'
                echo -e "${child:1}\t$property" >> $post_sync_file
                debug "${dataset}: Updating ${target_folder}${child}   $property"
            done
        done

        release_lock $post_sync_file


        target_count=`zfs_cache get -o value -H ${zfs_replication_property}:endpoints $replication_folder 3>/dev/null`
        if [ "$target_count" = '-' ]; then
            error "${dataset}: Replication defined, however, ${zfs_replication_property}:endpoints is not set on $replication_folder"
            continue
        fi

        target=0

        debug "${dataset}: Target count: $target_count"

        while [ $target -lt $target_count ]; do
            target=$(( target + 1 ))
            this_target=`zfs_cache get -o value -H ${zfs_replication_property}:endpoint:${target} $replication_folder 3>/dev/null`
            if [ "$this_target" == '-' ]; then
                error "${dataset}: Replication defined, however, ${zfs_replication_property}:endpoint:${target} is not set on $replication_folder"
                continue
            fi
            target_pool=`echo "$this_target" | ${CUT} -d ":" -f 1`
            target_folder=`echo "$this_target" | ${CUT} -d ":" -f 2`
        
            if [ "$replication_folder" == "${target_pool}/${target_folder}" ]; then
                debug "${dataset}: Skipping property replication to self."
                continue
            fi

            # Send properties to target(s)

            debug "${dataset}: Sending properties to $this_target"

            ##
            # Run 'zfs inherit -S' on source zfs properties which are local so the replicated value becomes active
            ##

            local_prop_file="${TMP}/replication/zfs_properties/${dataset}/local_zfs_properties"
            replicated_props="${TMP}/replication/zfs_properties/${dataset}/replicated_zfs_properties_$(foldertojob $this_target)"
            props_to_replicate="${TMP}/replication/zfs_properties_${dataset}_$$"
            new_props="${TMP}/replication/zfs_new_properties_${dataset}_$$"
            update_err="${TMP}/replication/zfs_properties/property_update_err_$$"
            if [ -f $local_prop_file ]; then
                wait_for_lock $local_prop_file
                if [ -f $replicated_props ]; then
                    ${GREP} -v -x -f $replicated_props $local_prop_file > $new_props
                else
                    cp $local_prop_file $new_props
                fi

                if [ -f $new_props ]; then
                    lines=`cat $new_props | ${WC} -l`
                    x=0
                    while [ $x -lt $lines ]; do
                        x=$(( x + 1 ))
                        line=`cat $new_props | head -n $x | tail -1`
                        prop_folder=`cat $new_props | head -n $x | tail -1 | ${CUT} -f 1`
                        property=`cat $new_props | head -n $x | tail -1 | ${CUT} -f 2`

                        if [ "$prop_folder" != "" ]; then
                            prop_folder="/${prop_folder}"
                        fi
                        notice "${dataset}: Updating $property on ${target_pool}/${target_folder}${prop_folder}"
                        echo -e "zfs inherit -S $property ${target_pool}/${target_folder}${prop_folder}" >> $props_to_replicate
                        echo "$line" >> $replicated_props
                    done
                fi

                unset IFS
                rm -f $new_props
                release_lock $local_prop_file
            fi

            if [ -f $props_to_replicate ]; then
                ${SED} -i '1i#! /bin/bash' $props_to_replicate
                if [ -t 1 ]; then
                    echo "Executing on ${target_pool}:"
                    cat $props_to_replicate
                    #pause
                fi
                ${SSH} ${target_pool} < $props_to_replicate 2>${update_err}
                if [[ $? -ne 0 && -f ${update_err} ]]; then
                    err_lines=`cat ${update_err} | ${GREP} -v "Pseudo-terminal" | ${WC} -l`
                    if [ $err_lines -ge 1 ]; then
                        if [ -t 1 ]; then
                            cat ${TMP}/property_update_err_$$
                        fi
                        warning "${dataset}: Errors running property updates" ${update_err}
                    fi
                fi
                rm -f ${TMP}/property_update_err_$$ $props_to_replicate
            fi

        done # while target

    done # replication_folder

done # pool

release_lock ${send_properties_lock}
