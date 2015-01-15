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
if [ -f "${job_status}" ]; then
    source "${job_status}"
fi

if [ "$failures" == '' ]; then
    failures=0
fi

if [ $endpoint_count -eq 1 ]; then
    $delete_snaps='-d'
else
    $delete_snaps=''
fi


# Execute ZFS send script

# TODO: Handle local replication


case $mode in
    'm') mode_option='-M' ;;
    's') mode_option='-S' ;;
         # TODO: Number of BBCP connnections needs to be tuneable
    'b') mode_option='-b 30' ;;
    'L') error "Local replication not completely coded yet!"
         exit 1 ;;
esac


if [ "$previous_snapshot" == "" ]; then
    ../utils/zfs-send.sh -n "$dataset_name" -r ${delete_snaps} -M \
        -s "${pool}/${folder}" -t "${target_folder}" -h "${target_host}" \
        -l "${pool}/${folder}@${last_snapshot}"
    send_result=$?
else
    ../utils/zfs-send.sh -n "$dataset_name" -r -I ${delete_snaps} -M \
        -s "${pool}/${folder}" -t "${target_folder}" -h "${target_host}" \
        -f "${pool}/${folder}@${previous_snapshot}" \
        -l "${pool}/${folder}@${last_snapshot}"
    send_result=$?
fi

if [ $send_result -ne 0 ]; then
    failures=$(( failures + 1 ))
    mv "${job_definition}" "${replication_dir}/failed/"
    updated_job_status "$job_status" failures $failures
else
    mv "${job_definition}" "${replication_dir}/jobs/synced/"
    notice "Replication job ${pool}/${folder} to ${target_folder} on ${target_host} completed for ${folder}@${last_snapshot}"
    updated_job_status "$job_status" "failures" "0"
    queued_jobs=$(( queued_jobs - 1 ))
    if [ $queued_jobs -lt 0 ]; then
        queued_jobs=0
    fi
    updated_job_status "$job_status" "queued_jobs" "$queued_jobs"
    if [ "$delete_snaps" != "" ]; then
        # Delete the previous snapshot
        zfs destroy -r "${pool}/${folder}@${previous_snapshot}" || \
            warning "Could not destroy replication snapshot ${pool}/${folder}@${previous_snapshot}"
    fi
fi


