#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2017  Chip Schweiss

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

. /opt/ozmt/zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

now=`${DATE} +"%F %H:%M:%S%z"`

pools="$(pools)"



# show function usage
show_usage() {
    echo
    echo "Usage: $0 -d {dataset_name} -D {dev_instance_name} -s {snapname}"
    echo
}

while getopts d:D:s: opt; do
    case $opt in
        d)  # Dataset name
            clone_dataset="$OPTARG"
            debug "dataset name: $clone_dataset"
            ;;
        D)  # Dev name
            dev_name="$OPTARG"
            debug "dev instance_name: $dev_name"
            ;;
        s)  # Snapshot name / type
            snap_name="$OPTARG"
            debug "snap name: $snap_name"
            ;;
        ?)  # Show program usage and exit
            show_usage
            exit 0
            ;;
        :)  # Mandatory arguments not specified
            die "${job_name}: Option -$OPTARG requires an argument."
            ;;
    esac
done


find_snap () {

    local zfs_folder="$1"
    local snap="$2"
    local pool=`echo $zfs_folder | $CUT -d '/' -f 1`
    local folder=`echo $zfs_folder | $CUT -d '/' -f 2`
    
    $SSH $pool zfs list -t snapshot ${zfs_folder}@${snap} 1>/dev/null 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "$snap"
        return 0
    else
        $SSH $pool zfs list -H -o name -t snapshot -d 1 ${zfs_folder} | \
            $GREP "^${zfs_folder}@${snap}_" | $SORT -r | $HEAD -1 | $CUT -d '@' -f 2
        return $?
    fi
}

# Locate dataset info
clone_pool=
debug "Finding dataset source for $clone_dataset"
dataset_source=`dataset_source $clone_dataset`
if [ "$dataset_source" == '' ]; then
    error "Cannot locate source for $clone_dataset"
    exit 1
fi
debug "Found source at $dataset_source"
clone_pool=`echo $dataset_source | $CUT -d ':' -f 1`

# Check if clone already exists

$SSH ${clone_pool} zfs list ${clone_pool}/${clone_dataset}/dev/${dev_name}  1>/dev/null 2>/dev/null
if [ $? -eq 0 ]; then
    error "Clone already exists for $dev_name"
    exit 1
else
    debug "Safe to create ${clone_pool}/dev/${dev_name}"
fi

# TODO: Check if clones exist in all additional folders and datasets



##
# Create the clone(s)
##

clone_folders=`$SSH $clone_pool cat /${clone_dataset}/.ozmt-folders 2>/dev/null`
debug "Cloning the following folders: $clone_folders"

snap=`find_snap "${clone_pool}/${clone_dataset}" "$snap_name"`
if [ "$snap" == '' ]; then
    error "Could not find snapshot: $snap_name"
    exit 1
else
    debug "Found snapshot $snap"
fi

$SSH $clone_pool zfs clone ${clone_pool}/${clone_dataset}@${snap} ${clone_pool}/${clone_dataset}/dev/${dev_name}
ozmt_datasets=`$SSH $clone_pool cat /${clone_dataset}/.ozmt-datasets 2>/dev/null`
if [ "$ozmt_datasets" != '' ]; then
    # Create stub clones
    for ozmt_dataset in $ozmt_datasets; do
        o_source=`dataset_source $ozmt_dataset`
        o_pool=`echo $o_source | $CUT -d ':' -f 1`
        o_folder=`echo $o_source | $CUT -d ':' -f 2`
        # Clone it
        debug "Creating stub ${o_pool}/${o_folder}/dev/${dev_name} from ${o_pool}/${o_folder}@${snap}"
        $SSH $o_pool zfs clone ${o_pool}/${o_folder}@${snap} ${o_pool}/${o_folder}/dev/${dev_name}
    done
fi


for clone_folder in $clone_folders; do
    debug "Cloning folder: $clone_folder"

    # Clone the primary dataset folder
    $SSH $clone_pool zfs clone ${clone_pool}/${clone_dataset}/${clone_folder}@${snap} \
        ${clone_pool}/${clone_dataset}/dev/${dev_name}/${clone_folder}

    origin_path="/${clone_dataset}/${clone_folder}"

    ozmt_datasets=`$SSH $clone_pool cat ${origin_path}/.ozmt-datasets 2>/dev/null`
    $SSH $clone_pool "$FIND ${origin_path} -maxdepth 3 -type l -exec ls -l {} \;" | \
        $GREP REPARSE | $AWK -F ' ' '{printf("%s\t%s\n",$9,$11)}' > ${TMP}/dataset_reparse_${clone_folder}_$$

    if [ "$ozmt_datasets" != '' ]; then
        for ozmt_dataset in $ozmt_datasets; do
            o_source=`dataset_source $ozmt_dataset`
            o_pool=`echo $o_source | $CUT -d ':' -f 1`
            o_folder=`echo $o_source | $CUT -d ':' -f 2`
            # Clone it
            debug "Creating ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder} from ${o_pool}/${o_folder}/${clone_folder}@${snap}"
            $SSH $o_pool zfs clone ${o_pool}/${o_folder}/${clone_folder}@${snap} ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder}

            # Fix up any reparse points
            cat ${TMP}/dataset_reparse_${clone_folder}_$$ | $GREP ":zfs-${ozmt_dataset}:" > ${TMP}/dataset_reparse_${ozmt_dataset}_$$
    
            target_script="${TMP}/dataset_reparse_run_$$"

            while IFS=$(echo -e '\t\n') read -r link_path link_target || [[ -n "$line" ]]; do
                unset IFS

                link_name=`basename $link_path`
                # Strip origin
                link_path="${link_path:$(( ${#origin_path} + 1 ))}"

                target_link="/${clone_dataset}/dev/${dev_name}/${clone_folder}/${link_path}"
                target_target="zfs-${ozmt_dataset}:/${ozmt_dataset}/dev/${dev_name}/${clone_folder}/${link_path}"
                
        
                # Replace reparse point        
                echo "rm $target_link" >> $target_script
                echo "nfsref add ${target_link} ${target_target}" >> $target_script
        
                IFS=$(echo -e '\t\n')
            done < "${TMP}/dataset_reparse_${ozmt_dataset}_$$"
            unset IFS
            
            # Execute reparse fix-up
            chmod +x $target_script
            $SSH $o_pool "bash -s " < ${target_script}
            
            rm $target_script
            rm ${TMP}/dataset_reparse_${ozmt_dataset}_$$
            
        done
        
        rm ${TMP}/dataset_reparse_${clone_folder}_$$

    fi
done





