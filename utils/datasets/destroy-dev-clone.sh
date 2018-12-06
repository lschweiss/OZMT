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

myTMP="${TMP}/datasets"
MKDIR $myTMP

DEBUG='true'

paused='false'

# show function usage
show_usage() {
    echo
    echo "Usage: $0 -d {dataset_name} -n {instance_name} [-p {pause_tag}] [-t]"
    echo
}

while getopts d:n:p:t opt; do
    case $opt in
        d)  # Dataset name
            clone_dataset="$OPTARG"
            debug "dataset name: $clone_dataset"
            ;;
        n)  # Dev name
            dev_name="$OPTARG"
            debug "instance_name: $dev_name"
            ;;
        t)  # Test mode
            test='true'
            debug "Running in test mode"
            ;;
        p)  # Leave replication paused
            pause="$OPTARG"
            pflag='true'
            debug "Leave replication paused.  Using tag $OPTARG"
            ;;
        ?)  # Show program usage and exit
            show_usage
            exit 0
            ;;
        :)  # Mandatory arguments not specified
            die "${job_name}: Option -$OPTARG requires an argument." 1
            ;;
    esac
done

declare -A o_source
declare -A o_paused

if [ "$pause" == '' ]; then
    pause="$$"
fi


die () {
    unset IFS

    if [ "$paused" == 'true' ]; then
        for ozmt_dataset in $ozmt_datasets; do
            this_source="${o_source[$ozmt_dataset]}"
            o_pool=`echo $this_source | $CUT -d ':' -f 1`
            debug "Releasing pause on $ozmt_dataset on pool $o_pool"
            $SSH $o_pool /opt/ozmt/replication/replication-state.sh -d $ozmt_dataset -s unpause -i $pause
        done
    fi

    if [ "$p_paused" == 'true' ]; then
        debug "Releasing pause on $p_dataset on pool $p_pool"
        $SSH $p_pool /opt/ozmt/replication/replication-state.sh -d $p_dataset -s unpause -i $pause
    fi

    rm -f ${myTMP}/dataset*_$$

    if [ $2 -ne 0 ]; then
        if [ "$1" != '' ]; then
            error "$1"
        fi
    else
        notice "$1"
    fi

    exit $2
}


# Locate dataset info
clone_pool=
debug "Finding dataset source for $clone_dataset"
dataset_source=`dataset_source $clone_dataset`
o_source["${clone_dataset}"]="$dataset_source"
if [ "$dataset_source" == '' ]; then
    die "Cannot locate source for $clone_dataset" 1
fi
debug "Found source at $dataset_source"
clone_pool=`echo $dataset_source | $CUT -d ':' -f 1`

# Collect dataset folders

rm -f ${TMP}/dataset_folders_$$
x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:folders ${clone_pool}/${clone_dataset}`
folders="$(echo -e "$x" | $TR -d '[:space:]')"
if [ "$folders" != '-' ]; then
    NUM=1
    while [ $NUM -le $folders ]; do
        $SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:folder:${NUM} ${clone_pool}/${clone_dataset} 2>/dev/null  >>${TMP}/dataset_folders_$$
        NUM=$(( NUM + 1 ))
    done
fi

rm -f ${TMP}/dataset_datasets_$$
x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:datasets ${clone_pool}/${clone_dataset}`
datasets="$(echo -e "$x" | $TR -d '[:space:]')"
if [ "$datasets" != '-' ]; then
    NUM=1
    while [ $NUM -le $datasets ]; do
        $SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:dataset:${NUM} ${clone_pool}/${clone_dataset} 2>/dev/null >>${TMP}/dataset_datasets_$$
        NUM=$(( NUM + 1 ))
    done
fi

ozmt_datasets=`cat ${TMP}/dataset_datasets_$$ 2>/dev/null`

x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:postgres ${clone_pool}/${clone_dataset}`
postgres="$(echo -e "$x" | $TR -d '[:space:]')"
x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:postgresdev ${clone_pool}/${clone_dataset}`
postgres_dev="$(echo -e "$x" | $TR -d '[:space:]')"

##
# Locate and pause all related datasets
##

source clone-functions.sh

##
# Destroy Clones
##

if [ "$ozmt_datasets" != '' ]; then
    for ozmt_dataset in $ozmt_datasets; do
        this_source="${o_source[$ozmt_dataset]}"
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
            notice "Destroying ${o_pool}/${o_folder}/dev/${dev_name}"
            if [ "$test" != 'true' ]; then
                $SSH $o_pool zfs destroy -r -f ${o_pool}/${o_folder}/dev/${dev_name} 2>${TMP}/dataset_dev_destroy_$$.txt
                result=$?
            else
                echo "TEST MODE.  Would run:"
                echo "$SSH $o_pool zfs destroy -r -f ${o_pool}/${o_folder}/dev/${dev_name} 2>${TMP}/dataset_dev_destroy_$$.txt"
            fi
            result=$?
            if [ $result -ne 0 ]; then
                warning "Failed to destroy ${o_pool}/${o_folder}/dev/${dev_name}"
                if [ $SECONDS -gt $timeout ]; then
                    error "Could not destroy ${o_pool}/${o_folder}/dev/${dev_name} aborting destroy-dev-clone." ${TMP}/dataset_dev_destroy_$$.txt
                    die "" 1 
                fi
                sleep 60
            fi
        done

    done
else
    die "Could not locate any dataset listing for ${clone_dataset}  Make sure dataset's folder paramaters are set." 1
fi


##
# Destroy Postgres clone
##

if [ "$postgres" != '-' ]; then
    $SSH $p_pool zfs list -o name -H ${p_pool}/${p_folder}/${pdev_folder}/${dev_name} 1>/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        warning "Could not location ${p_pool}/${p_folder}/${pdev_folder}/${dev_name} Skipping destroy."
        result=0
    else
        notice "Destroying ${p_pool}/${p_folder}/${pdev_folder}/${dev_name}"
        if [ "$test" != 'true' ]; then
            $SSH $p_pool zfs destroy -r -f ${p_pool}/${p_folder}/${pdev_folder}/${dev_name} 2>${TMP}/dataset_dev_destroy_$$.txt
            result=$?
        fi
    fi
    if [ $result -ne 0 ]; then
        die "Failed to destroy ${p_pool}/${p_folder}/${pdev_folder}/${dev_name}" 1
    fi
fi


if [ "$pause" == "$$" ]; then
    die "Destroying $clone_dataset complete" 0
else
    notice "Destroying $clone_dataset complete"
    exit 0
fi
