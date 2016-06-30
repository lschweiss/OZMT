#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2015  Chip Schweiss

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


show_usage () {
    echo
    echo "Usage: $0 {dataset_name} [{ignore_folder_list}]"
    echo "  {dataset_name}   Name of the data set to clean all replication jobs and"
    echo "                   replication snapshots except the latest fully syncd snapshot."
    echo "                   It then puts the job back in to a status for resuming replication."  
    echo ""
    echo "  {ignore_folder_list} (optional)"
    echo "                   List of folder to ignore sanity check and clean up."
    echo "                   This is primarily used when new ZFS folders are created, that"
    echo "                   have not yet been replicated." 
    echo "                   This should be a comma separated list of ZFS folders within"
    echo "                   the dataset."
    echo ""
    echo "  The host this command is run on must be either the source host for this dataset."
    echo ""
    echo "  This is automatically run after every cut over of a dataset source or can be run"
    echo "  manually to cleanup broken replication jobs."
    echo ""
    echo "  The following data sets are active on this host:"
    for pool in $pools; do
        if [ -d /${pool}/zfs_tools/var/replication/source ]; then
            datasets=`ls -1 /${pool}/zfs_tools/var/replication/source `
            for dataset in $datasets; do
                cat "/${pool}/zfs_tools/var/replication/source/$dataset" | ${GREP} -q "$pool"
                if [ $? -eq 0 ]; then
                    echo "        $dataset"
                fi
            done
        fi
    done
    exit 1
}


RTMP=${TMP}/replication/setup
RVAR=/var/zfs_tools/replication/setup

mkdir -p ${RTMP} ${RVAR}

dataset_list="${RTMP}/datasets_$$"
dataset_cache="${RVAR}/datasets_cache"
datasets=
dataset_new='false'
dataset_folder=

while getopts d:n opt; do
    case $opt in
        d)  # Existing dataset
            dataset_name="$OPTARG"
            ;;
        n)  # Define new dataset
            dataset_new='true'
            ;;
        ?)  # Show program usage and exit
            show_usage
            return 0
            ;;
        :)  # Mandatory arguments not specified
            error "setupzfs: Option -$OPTARG requires an argument."
            ;;
    esac
done

source ${TOOLS_ROOT}/utils/dialog/setup-vars

source replication-functions.sh





load_datasets () {

    rm -f $dataset_list

    for pool in $(cluster_pools); do
        remote_zfs_cache get -r -s local,received -o value,name -H ${zfs_dataset_property} $pool 3>>$dataset_cache >> $dataset_list
    done

    datasets=`cat ${dataset_list} | ${CUT} -f 1 | ${SORT} -u`

    ${SORT} --output ${dataset_list} ${dataset_list}

    dataset_count=`cat $dataset_list | ${WC} -l`

}


reload_datasets () {

    local cache=
    local caches=

    if [ -f $dataset_cache ]; then
        caches=`cat ${dataset_cache}`
        for cache in $caches; do   
            rm -f $cache
        done
        rm -f $dataset_cache
    fi
    load_datasets

}

##
# Choose a dataset we will be working on
##

clear
echo "$(color blue)Collecting existing dataset information..."

load_datasets

clear


if [ $dataset_count -eq 0 ]; then
    echo "$(color red)No datasets defined.  Assuming new dataset.$(color)"
    dataset_name='{new}'
else
    #cp "${dataset_list}" "${dataset_list}_plus"
    #echo -e "new\tNew dataset" >> "${dataset_list}_plus"
    while [ "$dataset_name" == '' ]; do
        select_dataset "${dataset_list}" 'true'
        retval=$?
    
        if [ $retval -ne 0 ]; then
            echo "$(color bd red)Replication Setup Cancelled"
            exit 1
        fi
        dataset_name=`cat $dialog_out`
    
    done
fi

# Collect new dataset name and validate it.
while [ "$dataset_name" == '{new}' ]; do

    dataset_new='true'
    echo
    echo -n "$(color)New dataset name: "

    read choice

    cat $dataset_list | ${CUT} -f 1 | ${GREP} -q "$choice"
    if [ $? -eq 0 ]; then
        echo "$(color bd red)Dataset name $choice is already in use."
    else
        if [ "$choice" == 'new' ]; then
            echo "$(color bd red)Dataset name 'new' is a reserved word and cannot be used for a dataset name."
            continue
        fi
        ${GREP} -qv '[^0-9A-Za-z\$\%\(\)\=\+\-\#\:\{\}]' <<< $choice
        if [ $? -eq 0 ]; then
            dataset_name="$choice"
        else
            echo "$(color bd red)Dataset name $choice contains invalid characters."
        fi
    fi
done


echo "$(color bd yellow)Configuring dataset: $dataset_name"


if [ "$dataset_new" == 'true' ]; then

    select_zfs_folder
    retval=$?

    if [ $retval -ne 0 ]; then
        echo "$(color bd red)Replication Setup Cancelled"
        exit 1
    fi

    dataset_zfs_folder=`cat $dialog_out`

    pool=`echo $dataset_zfs_folder | ${CUT} -d '/' -f 1`

    current_dataset_name=`ssh $pool zfs get -o value -H ${zfs_dataset_property} $dataset_zfs_folder`

    if [ "$current_dataset_name" = '-' ]; then 
        echo "$(color bd yellow)Setting dataset name \"$dataset_name\" on zfs folder $dataset_zfs_folder$(color)"
        ssh $pool zfs set ${zfs_dataset_property}="$dataset_name" $dataset_zfs_folder
        echo -e "${dataset_name}\t${dataset_zfs_folder}" >> $dataset_list
    else
        echo "$(color bd red)Dataset name, \"$current_dataset_name\" is already active on ${dataset_zfs_folder}$(color)"
        exit 1
    fi

fi




##
#
# Load dataset replication and vip info
#
##

set -x
load_replication_data $dataset_zfs_folder







rm $dataset_list
exit 0












