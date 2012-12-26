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

jobstatusdir="$TOOLS_ROOT/backup/jobs/glacier_status"

job="$1"

die () {

    echo "$1" >&2
    exit 1

}

if [ ! -f "${jobstatusdir}/definition/${job}" ]; then
    
    die "Job \"$job\" not defined. Nothing to do."
   
fi

# Collect job information
jobroot=`cat ${jobstatusdir}/definition/${job}|cut -f 1`
jobsnapname=`cat ${jobstatusdir}/definition/${job}|cut -f 2`
thisjob=`cat ${jobstatusdir}/definition/${job}|cut -f 3`
snaptime=`cat ${jobstatusdir}/definition/${job}|cut -f 4`
vault=`cat ${jobstatusdir}/definition/${job}|cut -f 5`

if [ "$thisjob" -eq "$glacier_start_sequence" ]; then

    # This is the first job 

    # TODO: Check if this is a failed or pending job.
    # If it is a failed job make sure the previous job is cleaned up before starting again.

    mv ${jobstatusdir}/pending/${job} ${jobstatusdir}/running/${job}

    # Create the named pipe
    pipe="/tmp/zfs.glacier-backup_pipe_${job}"
    mkfifo $pipe

    # Start the zfs send

    csfile="/tmp/zfs.glacier-backup_cksum_${job}"
    send_result=999
    result_file="/tmp/zfs.glacier-backup_send_result_${job}"
    zfs send -R ${snapname} | \
    mbuffer -q -s 128k -m 16M | \
    gzip | \
    mbuffer -q -s 128k -m 16M | \
    gpg -r "CTS Admin" --encrypt | \
    mbuffer -m 128M | \
    glacier-cmd upload ${vault} \
        --stdin \
        --description "${jobroot}-${snaptime}" \
        --name "${thisjob}-${jobroot}" \
        --partsize 128
    result=$?

    rm -f $pipe

else

    # This is an incremental job

    # TODO: Check if this is a failed or pending job.
    # If it is a failed job make sure the previous job is cleaned up before starting again.

    mv ${jobstatusdir}/pending/${job} ${jobstatusdir}/running/${job}

    # Collect the previous job's snapshot name

    previousjob=$(( $thisjob - 1 ))
    previoussnapname=`cat ${jobstatusdir}/definition/${previousjob}|cut -f 2`

    # Create the named pipe
    pipe="/tmp/zfs.glacier-backup_pipe_${job}"
    mkfifo $pipe

    # Start the zfs send

    csfile="/tmp/zfs.glacier-backup_cksum_${job}"
    send_result=999
    result_file="/tmp/zfs.glacier-backup_send_result_${job}"
    zfs send -I ${previoussnapname} ${jobsnapname} | \
    mbuffer -q -s 128k -m 16M | \
    gzip | \
    mbuffer -q -s 128k -m 16M | \
    gpg -r "CTS Admin" --encrypt | \
    mbuffer -m 128M | \
    glacier-cmd upload ${vault} \
        --stdin \
        --description "${jobroot}-${snaptime}" \
        --name "${thisjob}-${jobroot}" \
        --partsize 128
    result=$?

    rm -f $pipe
    
fi

# Handle job failures or success

if [ "$result" -ne "0" ]; then

    # Job failed

    # Collect the archive ID

    # Delete the archive

    # Move the job to failed status
    mv ${jobstatusdir}/running/${job} ${jobstatusdir}/failed/${job}

    # Email results

else

    # Move the job to archiving status
    mv ${jobstatusdir}/running/${job} ${jobstatusdir}/archiving/${job}

    # Email results

fi
