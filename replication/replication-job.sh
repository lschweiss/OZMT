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

####
####
##
## Data file reference
##
####
####

# Job definition file:
# /${pool}/zfs_tools/var/replication/jobs/definitions/${simple_jobname}/${target_pool}:$(foldertojob $target_folder)
#
# target=
# The target definition.
# {pool}:{folder}
#
# job_status=
# The full path to the job status file.  Defined as:
# /${pool}/zfs_tools/var/replication/jobs/status/${simple_jobname}#${target_pool}:$(foldertojob $target_folder)\"
#
# target_pool=
# The target pool.
# {pool}
#
# target_folder=
# The target folder.
# {folder}
#
# dataset_name=
# Common name of this dataset on at all replication points.
# Provided by filesystem configuration.
#
# pool=
# The source pool
#
# folder=
# The source folder
#
# source_tracker=
# Full path the the source tracking file that is synced between all replication targets.
# /${pool}/zfs_tools/var/replication/source/${dataset_name}
#
# replication_count=
# Number of replication paths defined for this dataset
#
# mode=
# Mode of transport
# L     local replication within the same pool
# m     mbuffer transport
# s     ssh tunnel
# b     bbcp transport
#
# options=
# l     lz4 compress the stream
# g     gzip compress the stream
# o     encrypt the stream with openssl
#
# frequency=
# ####{unit}
# Acceptable units are:
# m     minutes
# h     hours
# d     days
# w     weeks
#
# failure_limit=
# Failures Limit before halting replication.
# Can be a positive integer or time in the same form as Frequency
# Defaults to 5, unless override specified in zfs-config with 'zfs_replication_failure_limit'
#
#
# Job status file:
# Located by job_status variable from above
#
# last_run=
# Date and time of last trigger for this job
#     date +"%F %H:%M:%S%z"
#
# suspended=
# Set to 'true' if the job is suspended and will no longer be secheduled.
#
# failures=
# Count of the number of failures since last successful sync.
#
# queued_jobs=
# The number of queued replication jobs for this dataset.

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

pools="$(pools)"
now=`${DATE} +"%F %H:%M:%S%z"`

show_usage () {

    echo "Usage: $0 {job_definition_file}"
    echo

}


# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -ne "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

job_definition="${1}"

source "$job_definition"

replication_dir="/${pool}/zfs_tools/var/replication/jobs"

wait_for_lock "${job_status}"
source "${job_status}"
release_lock "${job_status}"

if [ "$failures" == '' ]; then
    failures=0
fi

endpoint_count=`zfs get -H -o value ${zfs_replication_endpoints_property} ${pool}/${folder}`

if [ $endpoint_count -eq 2 ]; then
    delete_snaps='-d'
else
    delete_snaps=''
fi

migrating='false'



# Execute ZFS send script

# TODO: Handle local replication





# Remote replication

# Test ssh connectivity
timeout 30s ssh ${target_pool} "echo \"Hello world.\"" >/dev/null 2> /dev/null
if [ $? -eq 0 ]; then
    debug "Connection validated to ${target_pool}"
    # Confirm on the target host that this is truely the source
    target_source_reference=`ssh $target_pool cat /${target_pool}/zfs_tools/var/replication/source/${dataset_name}|head -1`
    if [ "$target_source_reference" == "migrating" ]; then
        migrating='true'
        debug "Active endpoint is being migrated"
        # collect the current active pool
        target_source_reference=`ssh $target_pool cat /${target_pool}/zfs_tools/var/replication/source/${dataset_name}|head -2|tail -1`
    fi
    if [ "$target_source_reference" != "${pool}:${folder}" ]; then
        error "Attempting replication from ${pool}:${folder} to ${target_pool}:${target_folder}.  However, sources do not match.  My source "${pool}:${folder}", target's source ${target_source_reference}.  Replication suspended."
        # Suspend replication
        update_job_status "$job_status" suspended true
        mv "$job_definition" "${replication_dir}/suspended/"
        exit 1
    fi
else 
    # Cannot connect to remote host.  Fail this job
    failures=$(( failures + 1 ))
    mv "${job_definition}" "${replication_dir}/failed/"
    notice "Cannot connect to host for ${target_pool}.  Marking job failed. $job_definition"
    update_job_status "$job_status" failures $failures
    exit 1
fi

case $mode in
    'm') mode_option='-M' ;;
    's') mode_option='-S' ;;
         # TODO: Number of BBCP connnections needs to be tuneable
    'b') mode_option='-b 30' ;;
    'L') error "Local replication not completely coded yet!"
         exit 1 ;;
esac



if [ "$previous_snapshot" == "" ]; then
    debug "Starting zfs-send.sh for first replication of ${pool}/${folder}"
    ../utils/zfs-send.sh -n "${dataset_name}" -r ${delete_snaps} -M \
        -s "${pool}/${folder}" -t "${target_pool}/${target_folder}" -h "${target_pool}" \
        -l "${pool}/${folder}@${snapshot}"
    send_result=$?
else
    debug "Starting zfs-send.sh replication of ${pool}/${folder}"
    ../utils/zfs-send.sh -n "${dataset_name}" -r -I ${delete_snaps} -M \
        -s "${pool}/${folder}" -t "${target_pool}/${target_folder}" -h "${target_pool}" \
        -f "${pool}/${folder}@${previous_snapshot}" \
        -l "${pool}/${folder}@${snapshot}"
    send_result=$?
fi

if [ $send_result -ne 0 ]; then
    failures=$(( failures + 1 ))
    mv "${job_definition}" "${replication_dir}/failed/"
    update_job_status "$job_status" failures $failures
else
    notice "Replication job ${pool}/${folder} to ${target_pool}/${target_folder} completed for ${folder}@${snapshot}"
    update_job_status "$job_status" "failures" "0"
    update_job_status "$job_status" "queued_jobs" "-1"
    if [[ "$delete_snaps" != "" && "$previous_snapshot" != "" ]]; then
        # Delete the previous snapshot
        debug "Only 2 replication endpoints.  Deleting source snapshot."
        zfs destroy -r "${pool}/${folder}@${previous_snapshot}" 2> /${TMP}/zfs_destroy_$$.txt 
        if [ $? -ne 0 ]; then
            warning "Could not destroy replication snapshot ${pool}/${folder}@${previous_snapshot}" /${TMP}/zfs_destroy_$$.txt
            zfs destroy -d -r "${pool}/${folder}@${previous_snapshot}" 2> /${TMP}/zfs_destroy2_$$.txt
            if [ $? -ne 0 ]; then
                error "Could not defer destroy replication snapshot ${pool}/${folder}@${previous_snapshot}" /${TMP}/zfs_destroy2_$$.txt
            fi
            mv "${job_definition}" "${replication_dir}/synced/"
        else
            # Move the job to completed status
            debug "Moving job to completed status"
            touch "${job_definition}"
            mkdir -p "${replication_dir}/complete/"
            mv "${job_definition}" "${replication_dir}/complete/" 
        fi
        rm /${TMP}/zfs_destroy_$$.txt 2>/dev/null
        rm /${TMP}/zfs_destroy2_$$.txt 2>/dev/null
    else
        if [ "$delete_snaps" != "" ]; then
            debug "Moving job to completed status"
            touch "${job_definition}"
            mkdir -p "${replication_dir}/complete/"
            mv "${job_definition}" "${replication_dir}/complete/"
        else
            debug "Moving job to synced status"
            mv "${job_definition}" "${replication_dir}/synced/"
        fi
    fi
        
fi


