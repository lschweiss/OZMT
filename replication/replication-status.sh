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

# Minimum number of arguments needed by this program
MIN_ARGS=0

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

dataset="$1"




for pool in $pools; do
    is_mounted $pool || continue

    rm -f ${TMP}/replication/datasets_$$
    zfs get -r -s local,received -o value,name -H ${zfs_dataset_property} $pool | ${SORT}  >> ${TMP}/replication/datasets_$$


    ##
    # Report vitals about each dataset
    ##
    
    
    while IFS='' read -r dataset || [[ -n "$dataset" ]]; do
        dataset_name=`echo $dataset | ${CUT} -d ' ' -f 1`
        zfs_folder=`echo $dataset | ${CUT} -d ' ' -f 2` 
    
       
    
        replication=`zfs get -s local,received -o value -H ${zfs_replication_property} ${zfs_folder}`
        echo -e "$(color bd blue)Dataset: $(color bd yellow)${dataset_name}\t $(color bd blue)ZFS folder: $(color bd yellow)${zfs_folder}"
        echo -e -n "$(color bd blue)Replication: $(color bd yellow)${replication}\t "
        
        if [ "$replication" == 'on' ]; then
            source=`cat /${pool}/zfs_tools/var/replication/source/${dataset_name}`
            if [ "$source" == "$(echo $zfs_folder | ${SED} '0,/\//{s/\//\:/}')" ]; then
                source='local'
                echo "$(color bd blue)Source: $(color bd yellow)local"
            else
                echo "$(color bd blue)Source: $(color bd yellow)${source}"
            fi
            echo

            if [ "$source" == 'local' ]; then
                
                # Find replication jobs for this dataset

                

                # Report on status                





            fi

            
    
        fi

        
    
       
    
    done < "${TMP}/replication/datasets_$$"



done









exit 0












