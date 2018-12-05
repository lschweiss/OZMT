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
    echo "Usage: $0 -p {pool} -d {dataset_name} "
    echo "  -p {pool}        All Datasets on a given pool."
    echo "                   This parameter is repeatable."
    echo ""
    echo "  -d {dataset_name}   Name of the data set to set the replication state"
    echo "                      This parameter can be repeated."
    echo ""
    echo "  -r                  Return the current state."
    echo ""
    echo "  -s {state}"
    echo "                      Set the replication state to:"
    echo "                        pause - Do not schedule new jobs, but finish any already running"
    echo "                        unpause - Release the pause"
    echo "                        suspend - Do not schedule, or clean any jobs, finish any running jobs"
    echo "                        unsuspend - Release the suspend"
    echo "                        run - Set to normal replication operation"
    echo ""
    echo "  -i {id}"
    echo "                      Set the ID of the process pausing or suspending the job"
    echo ""
    echo "  If process IDs are used, unpause, unsuspend, and run will only remove this processes's hold"
    echo "  The job will only be resumed if all holds are removed"
    echo ""
    echo "  The host this command is run on must be the source host for this dataset."
    echo ""
    echo "  The following data sets are active on this host:"
    for pool in $pools; do
        if [ -d /${pool}/zfs_tools/var/replication/source ]; then
            datasets=`ls -1 /${pool}/zfs_tools/var/replication/source `
            echo "    $pool"
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
MIN_ARGS=3

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi


while getopts d:s:p:i:r opt; do
    case $opt in
        p)  # All dataset in a pool
            pool="$OPTARG"
            if [ -d /${pool}/zfs_tools/var/replication/source ]; then
                p_datasets=`ls -1 /${pool}/zfs_tools/var/replication/source`
                for p_dataset in $p_datasets; do
                    cat "/${pool}/zfs_tools/var/replication/source/$p_dataset" | ${GREP} -q "$pool"
                    if [ $? -eq 0 ]; then
                        debug "Dataset: $p_dataset"
                        datasets="$datasets $p_dataset"
                    fi
                done
            else
                warning "No datasets found on pool $pool"
            fi
            ;;

        d)  # Dataset name
            datasets="$datasets $OPTARG"
            debug "Dataset: $OPTARG"
            ;;
        s)  # State
            state="$OPTARG"
            debug "State to be set to: $OPTARG"
            ;;
        i)  # ID of calling process
            id="$OPTARG"
            debug "Process ID: $OPTARG"
            ;;
        r)  # Query the state
            q_state='true'
            ;;
        ?)  # Show usage
            show_usage
            exit 0
            ;;
        :)  # Mandatory arguments not specified
            echo "${job_name}: Option -$OPTARG requires an argument."
            exit 1
            ;;

    esac
done




die () {

    exit $1

}

trap die SIGINT

for dataset in $datasets; do

    job_count=0
    ds_source=
    skip_dataset='false'
    running_end=
    jobs=
    abort=
    ds_source=
    ds_targets=
    definitions=
    target_pool=
    check_source=
    job_dead=
    running_jobs=
    info_folder=
    suspended=
    paused=


    ##
    # Gather information about the dataset
    ##
    
    # Does it exist?
    for pool in $pools; do
        debug "Checking for dataset $dataset on pool $pool"
        if [ -f /${pool}/zfs_tools/var/replication/source/${dataset} ]; then
            ds_source=`cat /${pool}/zfs_tools/var/replication/source/${dataset}`
            break
        fi
    done
    
    if [ "$ds_source" == "" ]; then
        error "Could not find dataset \"${dataset}\" on this host."
        show_usage
        continue
    else
        debug "Found dataset $dataset on pool $pool"
    fi
    
    
    # Where are the targets?
    
    if [ ! -f /$pool/zfs_tools/var/replication/targets/${dataset} ]; then
        error "Missing /$pool/zfs_tools/var/replication/targets/${dataset} cannot change replication state with out it."
        continue
    else
        ds_targets=`cat /$pool/zfs_tools/var/replication/targets/${dataset}`
    fi
    
    # Find and read the definition(s).
    
    for check_pool in $pools; do
        if [ -d "/$check_pool/zfs_tools/var/replication/jobs/definitions" ]; then
            definitions=`${FIND} "/$check_pool/zfs_tools/var/replication/jobs/definitions/" -type f`
            for definition in $definitions; do
                source $definition
                if [ "$dataset_name" == "$dataset" ]; then
                    debug "Found job definition $definition for $dataset"
                    jobs="$definition $jobs"
                    job_count=$(( job_count + 1 ))
                fi
            done        
        fi
    done
    
    ##
    # Is this the source host?
    ##
    
    source_pool=`echo "$ds_source" | ${CUT} -d ":" -f 1`
    source_folder=`echo "$ds_source" | ${CUT} -d ":" -f 2`
    
    if islocal $source_pool; then
        debug "Confirmed running on the source host."
    else
        warning "Must be run on the dataset's source host with the pool $source_pool"
        continue
    fi
    
    
    ##
    # Is it unanimous where the source is?
    ##
    
    for target in $ds_targets; do
        debug "Checking dataset source for target $target"
        target_pool=`echo "$target" | ${CUT} -d ":" -f 1`
        check_source=`${SSH} root@$target_pool cat /$target_pool/zfs_tools/var/replication/source/$dataset`
        if [ "$check_source" != "$ds_source" ]; then
            error "Dataset source is not consistent at all targets.  Target $target reports source to be $check_source.  My source: $ds_source"
            abort='true'
        fi
    done
    if [ "$abort" == 'true' ]; then
        abort=
        # Jump to next dataset
        continue
    fi

    
    for job in $jobs; do
        suspended=
        paused=
        pause_array=
        suspend_array=

        source $job
        job_prefix="${dataset_name}_to_${target}"


        ##
        # Query state
        ##

        if [ "$q_state" == 'true' ]; then
            source $job_status
            running='true'
            if [ "$suspended" == 'true' ]; then
                echo -e "${dataset}\tSUSPENDED"
                running='false'
            fi
            if [ "$paused" == 'true' ]; then
                echo -e -n "${dataset}\tPAUSED"
                running='false'
            fi
            if [ "$running" == 'true' ]; then
                echo -e "${dataset}\tRUNNING"
            else
                if [ -f ${pool}/zfs_tools/var/replication/jobs/running/${job_prefix}* ]; then
                    echo -n ",RUNNING"
                fi
                if [ -f ${pool}/zfs_tools/var/replication/jobs/sync/${job_prefix}* ]; then
                    echo -n ",SYNC"
                fi
                if [ -f ${pool}/zfs_tools/var/replication/jobs/cleaning/${job_prefix}* ]; then
                    echo -n ",CLEAN"
                fi
                if [ -f ${pool}/zfs_tools/var/replication/jobs/failed/${job_prefix}* ]; then
                    echo -n ",FAIL"
                fi
                echo
            fi
            continue
        fi
    
    
    
        ##
        # Set the repliction state
        ##
        case "$state" in
            'pause')
                update_job_status "$job_status" "paused" "true"
                if [ "$id" != "" ]; then
                    pause_array="$id $pause_array"
                    update_job_status "$job_status" "pause_array" "$pause_array"
                fi
                ;;
            'unpause')
                if [ "$id" != "" ]; then
                    new_array=
                    for x in $pause_array; do
                        if [ "$x" != "$id" ]; then
                            new_array="$x $new_array"
                        fi
                    done
                    update_job_status "$job_status" "pause_array" "$new_array"
                    if [ "$new_array" == '' ]; then
                        update_job_status "$job_status" "paused" 'false'
                    fi
                else
                    update_job_status "$job_status" "paused" "false"
                    update_job_status "$job_status" "pause_array" ""
                fi
                ;;
            'suspend')
                update_job_status "$job_status" "suspended" 'true'
                if [ "$id" != "" ]; then
                    suspend_array="$id $suspend_array"
                    update_job_status "$job_status" "suspend_array" "$suspend_array"
                fi
                ;;
            'unsuspend')
                if [ "$id" != "" ]; then
                    new_array=
                    for x in $suspend_array; do
                        if [ "$x" != "$id" ]; then
                            new_array="$x $new_array"
                        fi
                    done
                    update_job_status "$job_status" "suspend_array" "$new_array"
                    if [ "$new_array" == '' ]; then
                        update_job_status "$job_status" "suspended" 'false'
                    fi
                else
                    update_job_status "$job_status" "suspended" "false"
                    update_job_status "$job_status" "suspended_array" ""
                fi
                ;;
            'run')
                if [ "$id" != "" ]; then
                    new_array=
                    for x in $pause_array; do
                        if [ "$x" != "$id" ]; then
                            new_array="$x $new_array"
                        fi
                    done
                    update_job_status "$job_status" "pause_array" "$new_array"
                    if [ "$new_array" == '' ]; then
                        update_job_status "$job_status" "paused" 'false'
                    fi
                    new_array=
                    for x in $suspend_array; do
                        if [ "$x" != "$id" ]; then
                            new_array="$x $new_array"
                        fi
                    done
                    update_job_status "$job_status" "suspend_array" "$new_array"
                    if [ "$new_array" == '' ]; then
                        update_job_status "$job_status" "suspended" 'false'
                    fi
                else        
                    update_job_status "$job_status" "suspended" 'false' "paused" 'false' "suspend_array" "" "pause_array" ""
                fi
                ;;
        esac

    done # for job
    
done # for dataset

die 0
