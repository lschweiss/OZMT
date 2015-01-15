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

snaptype="$1"

if [ "x$snapshot_logfile" != "x" ]; then
    logfile="$snapshot_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$snapshot_report" != "x" ]; then
    report_name="$snapshot_report"
else
    report_name="$default_report_name"
fi

# Launch related backup jobs

$TOOLS_ROOT/backup/backup-to-zfs.sh $snaptype &


snap_job () {

    local snaptype="$1"
    shift 1
    local job="$1"

    local pool=
    local folder=
    local zfsfolder=`echo $job|${SED} 's,%,/,g'`
    IFS='/'
    read -r pool folder <<< "$zfsfolder"
    unset IFS
    local jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"
    local keepcount=`cat $jobfolder/$snaptype/$job`
    local replication=
    local replication_dataset=
    local replication_endpoints=
    local replication_source=
    local snap_this_folder='false'
    local now=
    local stamp=

    # Test the folder exists
    zfs get -H -o creation ${zfsfolder} 1>/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        # Nothing else to check, skip it.
        debug "No ZFS folder for snapshot job $jobfolder/$snaptype/$job"
        return 0
    fi

    # Make sure we should clean this folder
    replication=`zfs get -H -o $zfs_replication_property ${zfsfolder} 2>/dev/null`
    if [ "$replication" == "on" ]; then
        replication_dataset=`zfs get -H -o $zfs_replication_dataset_property ${zfsfolder} 2>/dev/null`
        replication_source=`cat /${pool}/zfs_tools/var/replication/source/${replication_dataset}`
        if [ "$replication_source" == "${pool}:${folder}" ]; then
            snap_this_folder='true'
        fi
    else
        snap_this_folder='true'
    fi

    if [ "$snap_this_folder" == 'false' ]; then
        # Skip this job
        return 0
    fi

    if [ "${keepcount:0:1}" == "x" ]; then
        keepcount="${keepcount:1}"
    fi

    now=`${DATE} +%F_%H:%M%z`
    stamp="${snaptype}_${now}"
    if [ "${keepcount:0:1}" != "x" ]; then
        zfs snapshot ${zfsfolder}@${stamp} 2> ${TMP}/process_snap_$$ ; result=$?
        if [ "$result" -ne "0" ]; then
            error "Failed to create snapshot ${zfsfolder}@${stamp}" ${TMP}/process_snap_$$
            rm ${TMP}/process_snap_$$
        else
            notice "Created snapshot: ${zfsfolder}@${stamp}"
        fi
    fi
    
}



# collect jobs

pools="$(pools)"

for pool in $pools; do
    jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"
    if [ -d $jobfolder/$snaptype ]; then
        jobs=`ls -1 $jobfolder/$snaptype`
        for job in $jobs; do
            snap_job "$snaptype" "$job" &
        done
    else 
        debug "process-snap: No snap type(s) $snaptype defined."
    fi
done

