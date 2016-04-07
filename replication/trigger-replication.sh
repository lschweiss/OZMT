#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2015  Chip Schweiss

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

source ../zfs-tools-init.sh

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

previous_snapshot=

job_definition="${1}"

mkdir -p ${TMP}/replication

if [ -f "$job_definition" ]; then
    source "$job_definition"
else
    error "Job defintion not found: $job_definition"
    exit 1
fi

# Check if all jobs suspended
if [ -f "$replication_dir/suspend_all_jobs" ]; then
    notice "All jobs suspended. Trigger replication aborted for job $job_definition."
    exit 0
fi

wait_for_lock "${job_status}"
if [ $? -ne 0 ]; then
    error "Failed to get lock for job status: ${job_status}.  Failing job."
    exit 1
fi
source "${job_status}"
#release_lock "${job_status}"

if [ "$suspended" == 'true' ]; then
    debug "Replication is suspended for data set $dataset_name"
    exit 0
fi

# previous_snapshot may have been defined in job_status file for a first run.
if [ "$previous_snapshot" == "" ]; then
    previous_snapshot="$last_snapshot"
fi

# Confirm on the target host that this is truely the source

timeout 1m ssh $target_pool cat /${target_pool}/zfs_tools/var/replication/source/${dataset_name} \
    > ${TMP}/target_check_$$ \
    2> ${TMP}/target_check_error_$$
errorcode=$?

case "$errorcode" in 
    '124')
        warning "Attempting replication from ${pool}:${folder} to ${target_pool}:${target_folder}. SSH to remore host timed out after 1m.  Setting job to failed."
        update_job_status "${job_status}" "failures" "+1"
        release_lock "${job_status}"
        rm -f ${TMP}/target_check_$$
        rm -f ${TMP}/target_check_error_$$
        exit 1
        ;;
    '0')  
        target_source_reference=`cat ${TMP}/target_check_$$`
        if [ "$target_source_reference" != "${pool}:${folder}" ]; then
            error "Attempting replication from ${pool}:${folder} to ${target_pool}:${target_folder}.  However, sources do not match.  My source "${pool}:${folder}", target's source $target_source_reference"
            update_job_status "${job_status}" "suspended" "true"
            release_lock "${job_status}"
            suspended="true"
            exit 1
        fi
        rm -f ${TMP}/target_check_$$
        rm -f ${TMP}/target_check_error_$$
        ;;
    *)  
        warning "Attempting replication from ${pool}:${folder} to ${target_pool}:${target_folder}. SSH to remore host failed with error code $errorcode  Setting job to failed." ${TMP}/target_check_error_$$
        update_job_status "${job_status}" "failures" "+1"
        release_lock "${job_status}"
        rm -f ${TMP}/target_check_$$
        rm -f ${TMP}/target_check_error_$$
        exit 1
        ;;
esac


now_stamp="$(now_stamp)"
last_run=`${DATE} +"%F %H:%M:%S%z"`

# ##
# # Get new children folder in sync and move info into specific job definition
# ##
# 
# pause 
# 
# set -x
# 
# if [ "$new_children" != "" ]; then
#     if [ "$last_snapshot" == "" ]; then
#         skip_new_children='true'
#     else
#         count=1
#         while [ $count -le $new_children ]; do
#             # Create "previous" snapshots
#             timeout 2m zfs snapshot ${pool}/${new_child[$count]}@${last_snapshot}
#             count=$(( count + 1 ))
#         done
#     fi
# fi
# 
# set +x
# 
# pause


# Copy quota,refquota to user parameters

quota_folders=`zfs list -o name -H -p -r ${pool}/${folder}`

for quota_folder in $quota_folders; do
    quota=`zfs get -o value -H -p quota $quota_folder`
    current=`zfs get -o value -H -p -s local ${zfs_quota_property} $quota_folder 2>/dev/null`
    if [ "$current" != "$quota" ]; then
        zfs set ${zfs_quota_property}="$quota" $quota_folder
    fi
done

for refquota_folder in $quota_folders; do
    refquota=`zfs get -o value -H -p refquota $refquota_folder`
    current=`zfs get -o value -H -p -s local ${zfs_refquota_property} $refquota_folder 2>/dev/null`
    if [ "$current" != "$refquota" ]; then
        zfs set ${zfs_refquota_property}="$refquota" $refquota_folder
    fi
done


# Generate new snapshot

last_snapshot="${zfs_replication_snapshot_name}_${now_stamp}"

debug "Generating snapshot ${pool}/${folder}@${zfs_replication_snapshot_name}_${now_stamp}"
timeout 20m zfs snapshot -r ${pool}/${folder}@${zfs_replication_snapshot_name}_${now_stamp} 2> ${TMP}/replication_snapshot_$$.txt
errorcode=$?

if [ $errorcode -ne 0 ]; then
    error "Replication: Failed to create snapshot ${pool}/${folder}@${zfs_replication_snapshot_name}_${now_stamp} errorcode $errorcode" \
        ${TMP}/replication_snapshot_$$.txt
    update_job_status "${job_status}" "suspended" "true"
    rm ${TMP}/replication_snapshot_$$.txt 2> /dev/null
    release_lock "${job_status}"
    exit 1
fi

rm ${TMP}/replication_snapshot_$$.txt 2> /dev/null

update_job_status "${job_status}" "last_snapshot" "${last_snapshot}"

# Place job in pending status

jobname="${dataset_name}_to_${target_pool}:$(foldertojob $target_folder)_${now_stamp}"
update_job_status "${job_status}" "last_jobname" "${jobname}"

if [ "$queued_jobs" == "" ]; then
    queued_jobs=1
    update_job_status "${job_status}" "queued_jobs" "1"
else
    queued_jobs=$(( queued_jobs + 1 ))
    update_job_status "${job_status}" "queued_jobs" "+1"
fi


# Remove previous_snapshot from status file if it is there.  This is only necesary for the first job.

update_job_status "${job_status}" "previous_snapshot" "#REMOVE#"

# Create the job file

jobfile="${TMP}/replication/new-job_$$"
pendingfile="/${pool}/zfs_tools/var/replication/jobs/pending/${jobname}"

cp "$job_definition" "$jobfile"

echo "jobname=\"${jobname}\"" >> $jobfile
echo "previous_jobname=\"${last_jobname}\"" >> $jobfile
echo "snapshot=\"${zfs_replication_snapshot_name}_${now_stamp}\"" >> $jobfile
echo "previous_snapshot=\"${previous_snapshot}\"" >> $jobfile
echo "creation_time=\"${last_run}\"" >> $jobfile
echo "execution_number=\"1\"" >> $jobfile

# if [ "$new_children" != "" ]; then
#     if [ "$skip_new_children" != 'true' ]; then
#         # Move new children information to the job file.
#         echo "new_children=\"$new_children\"" >> $jobfile
#     fi
#     update_job_status "${job_status}" "new_children" "#REMOVE#"
#     count=1
#     while [ $count -le $new_children ]; do
#         count=$(( count + 1 ))
#         if [ "$skip_new_children" != 'true' ]; then
#             echo "new_child[$count]=\"${new_child[$count]}\"" >> $jobfile
#             update_job_status "${job_status}" "${new_child[$count]}" "#REMOVE#"
#         fi
#     done
# fi
# 
# pause

# Update last run time in the status file 

update_job_status "${job_status}" "last_run" "${last_run}" 
mv "$jobfile" "$pendingfile"

release_lock "${job_status}"




