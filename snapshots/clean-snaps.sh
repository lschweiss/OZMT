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

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

jobfolder="$TOOLS_ROOT/snapshots/jobs"

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


clean_job () {

    local snaptype="$1"
    shift 1
    local job="$1"

    local pool=
    local folder=
    local zfsfolder=`echo $job|${SED} 's,%,/,g'`
    local folder_props=
    IFS='/'
    read -r pool folder <<< "$zfsfolder"
    unset IFS
    local jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"
    local keepcount=`cat $jobfolder/$snaptype/$job`
    local replication=
    local replication_dataset=
    local replication_endpoints=
    local replication_source=
    local clean_this_folder='false'
    local recursive='false'
    local snap_folders=
    local snap_folder=

    folder_props=`cat /${pool}/zfs_tools/var/spool/snapshot/${pool}_replication_properties | ${GREP} "^${zfsfolder}\s"`

    # Make sure we should clean this folder
    #replication=`zfs get -H -o value $zfs_replication_property ${zfsfolder} 2>/dev/null`
    replication=`echo $folder_props | ${CUT} -d ' ' -f 2`
    if [ "$replication" == "on" ]; then
        debug "Replication is ON for $zfsfolder"
        #replication_dataset=`zfs get -H -o value $zfs_replication_dataset_property ${zfsfolder} 2>/dev/null`
        replication_dataset=`echo $folder_props | ${CUT} -d ' ' -f 3`
        replication_source=`cat /${pool}/zfs_tools/var/replication/source/${replication_dataset}`
        debug "Replication source: $replication_source"
        if [[ "${pool}:${folder}" == "$replication_source"* ]]; then
            clean_this_folder='true'
        else
            #replication_endpoints=`zfs get -H -o value $zfs_replication_endpoints_property ${zfsfolder} 2>/dev/null`
            replication_endpoints=`echo $folder_props | ${CUT} -d ' ' -f 4`
            if [ $replication_endpoints -gt 2 ]; then
                clean_this_folder='true'
            fi
        fi
    else
        clean_this_folder='true'
    fi

    if [ "$clean_this_folder" == 'false' ]; then
        # Skip this job
        return 0
    fi

    if [ "${keepcount:0:1}" == "x" ]; then
        keepcount="${keepcount:1}"
    fi
    
    if [ "${keepcount:0:1}" == "r" ]; then
        keepcount="${keepcount:1}"
        recursive='true'
    fi

    if [[ "$keepcount" != "" && $keepcount -ne 0 ]]; then
        # Remove snapshots
        if [ "$recursive" == 'true' ]; then
            debug "Recursively cleaning $zfsfolder for $snaptype snapshots"
            #snap_folders=`zfs list -H -o name -r -t filesystem $zfsfolder`
            snap_folders=`echo $folder_props | ${CUT} -d ' ' -f 1`
            debug "Folder list: $snap_folders"
            for snap_folder in $snap_folders; do
                launch ${TOOLS_ROOT}/snapshots/remove-old-snapshots.sh -c $keepcount -z $snap_folder -p $snaptype
            done
        else
            launch ${TOOLS_ROOT}/snapshots/remove-old-snapshots.sh -c $keepcount -z $zfsfolder -p $snaptype
        fi
    else
        debug "clean-snapshots: Keeping all $snaptype snapshots for $zfsfolder"
    fi


}

# collect jobs

pools="$(pools)"

for pool in $pools; do

    jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"

    if [ -d $jobfolder ]; then
        mkdir -p /${pool}/zfs_tools/var/spool/snapshot
        # Collect snapshot data
        zfs list -H -o name -r -t snapshot ${pool} > /${pool}/zfs_tools/var/spool/snapshot/${pool}_snapshots
        zfs_cache list -H -r -o name,$zfs_replication_property,$zfs_replication_dataset_property,$zfs_replication_endpoints_property ${pool} > \
            /${pool}/zfs_tools/var/spool/snapshot/${pool}_replication_properties 3>/dev/null

        for snaptype in $snaptypes; do
            debug "Checking snaptype: $snaptype"
            if [ -d "$jobfolder/$snaptype" ]; then
                # collect jobs
                jobs=`ls -1 $jobfolder/$snaptype| ${SORT}`
                debug "$snaptype jobs: $jobs"
                for job in $jobs; do
                    launch clean_job "$snaptype" "$job" 
                done
            fi
        done
    fi

done
