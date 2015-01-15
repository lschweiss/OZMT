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
if [ -f "${job_status}" ]; then
    source "${job_status}"
fi
previous_snapshot="$last_snapshot"

now_stamp="$(now_stamp)"
last_run=`${DATE} +"%F %H:%M:%S%z"`

# Generate new snapshot

last_snapshot="${zfs_replication_snapshot_name}_${now_stamp}"
zfs snapshot -r ${pool}/${folder}@${zfs_replication_snapshot_name}_${now_stamp}

update_job_status "${job_status}" "last_snapshot" "${last_snapshot}"

# Place job in pending status

jobname="${folder}#${target_pool}_${now_stamp}"
update_job_status "${job_status}" "last_jobname" "${jobname}"

if [ "$queued_jobs" == "" ]; then
    queued_jobs=1
else
    queued_jobs=$(( queued_jobs + 1 ))
fi
update_job_status "${job_status}" "queued_jobs" "$queued_jobs"


# Create the job file

jobfile="/${pool}/zfs_tools/var/replication/jobs/pending/${jobname}"

cp "$job_definition" "$jobfile"

echo "jobname=\"${jobname}\"" >> $jobfile
echo "previous_jobname=\"${last_jobname}\"" >> $jobfile
echo "snapshot=\"${replication_snapshot_name}_${now_stamp}\"" >> $jobfile
echo "previous_snapshot=\"${previous_snapshot}\"" >> $jobfile
echo "creation_time=\"${last_run}\"" >> $jobfile
echo "execution_number=\"1\"" >> $jobfile

# Update last run time in the status file 

update_job_status "${job_status}" "last_run" "${last_run}" 

# Launch job runner

./replication-job-runner.sh 


