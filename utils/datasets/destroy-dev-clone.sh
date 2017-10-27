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

myTMP="${myTMP}/datasets"
MKDIR $myTMP

# show function usage
show_usage() {
    echo
    echo "Usage: $0 -d {dataset_name} -n {instance_name}"
    echo
}

while getopts d:n: opt; do
    case $opt in
        d)  # Dataset name
            clone_dataset="$OPTARG"
            debug "dataset name: $clone_dataset"
            ;;
        n)  # Dev name
            dev_name="$OPTARG"
            debug "instance_name: $dev_name"
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

die () {
    rm -f ${myTMP}/dataset*_$$
    exit $1
}


# Locate dataset info
clone_pool=
debug "Finding dataset source for $clone_dataset"
dataset_source=`dataset_source $clone_dataset`
o_source["${clone_dataset}"]="$dataset_source"
if [ "$dataset_source" == '' ]; then
    error "Cannot locate source for $clone_dataset"
    die 1
fi
debug "Found source at $dataset_source"
clone_pool=`echo $dataset_source | $CUT -d ':' -f 1`

# Collect dataset folders

rm -f ${TMP}/dataset_folders_$$
folders=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:folders ${clone_pool}/${clone_dataset}`
if [ "$folders" != ' - ' ]; then
    NUM=1
    while [ $NUM -le $folders ]; do
        $SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:folder:${NUM} ${clone_pool}/${clone_dataset} 2>/dev/null  >>${TMP}/dataset_folders_$$
        NUM=$(( NUM + 1 ))
    done
fi

rm -f ${TMP}/dataset_datasets_$$
datasets=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:datasets ${clone_pool}/${clone_dataset}`
if [ "$datasets" != ' - ' ]; then
    NUM=1
    while [ $NUM -le $datasets ]; do
        $SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:dataset:${NUM} ${clone_pool}/${clone_dataset} 2>/dev/null >>${TMP}/dataset_datasets_$$
        NUM=$(( NUM + 1 ))
    done
fi

ozmt_datasets=`cat ${TMP}/dataset_datasets_$$ 2>/dev/null`

# Locate datasets
if [ "$ozmt_datasets" != '' ]; then
    # Create stub clones
    for ozmt_dataset in $ozmt_datasets; do
        debug "Finding dataset source for $ozmt_dataset"
        this_source=`dataset_source $ozmt_dataset`
        debug "Found source as: $this_source"
        o_source["$ozmt_dataset"]="$this_source"
        o_pool=`echo $this_source | $CUT -d ':' -f 1`
        o_folder=`echo $this_source | $CUT -d ':' -f 2`
       
        replication=`$SSH $o_pool zfs get -s local,received ${zfs_replication_property} ${o_pool}/${o_folder}`
        if [ "$replication" == 'on' ]; then
            timeout=900
        else
            timeout=60
        fi
        
        result=1
        SECONDS=0
        while [ $result -ne 0 ]; do
            $SSH $o_pool zfs list -o name ${o_pool}/${o_folder}/dev/${dev_name} 1>/dev/null 2>/dev/null
            if [ $? -ne 0 ]; then
                warning "Could not locate ${o_pool}/${o_folder}/dev/${dev_name}  Skipping destroy."
                result=0
                continue
            fi
            debug "Destroying ${o_pool}/${o_folder}/dev/${dev_name}"
            $SSH $o_pool zfs destroy -r -f ${o_pool}/${o_folder}/dev/${dev_name} 2>${TMP}/dataset_dev_destroy_$$.txt
            result=$?
            if [ $result -ne 0 ]; then
                debug "Failed to destroy ${o_pool}/${o_folder}/dev/${dev_name}"
                if [ $SECONDS -gt $timeout ]; then
                    error "Could not destroy ${o_pool}/${o_folder}/dev/${dev_name} aborting destroy-dev-clone." ${TMP}/dataset_dev_destroy_$$.txt
                    die 1 
                fi
                sleep 60
            fi
        done

    done
else
    error "Could not locate any dataset listing for ${clone_dataset}  Make sure dataset's folder paramaters are set."
    die 1
fi

die 0
