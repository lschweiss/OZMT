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

pool="$1"
snaptype="$2"

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


echo $snaptypes | ${GREP} -q "\b${snaptype}\b"
result=$?
if [ $result -ne 0 ]; then
    warning "process-snaps-pool.sh: invalid snap type specified: $snaptype"
    exit 1
fi

# collect jobs

now=`${DATE} +%F_%H:%M%z | ${SED} 's/+/_/g'` # + is not a valid character for a snapshot name
stamp="${snaptype}_${now}"

mkdir -p ${TMP}/snapshots

command_max=$(( $(getconf ARG_MAX) - 1024 ))

rm -f ${TMP}/snapshots/${snaptype}_${pool}.* 2>/dev/null

folders=`zfs_cache get -H -o name -s local,received -r ${zfs_snapshot_property}:${snaptype} $pool 3>/dev/null`

debug "Pool: $pool Folders: $folders"

# sort folders
for folder in $folders; do
    snap_this_folder='false'
 
    # Make sure we should snap this folder
    replication=`zfs_cache get -H -o value $zfs_replication_property ${folder} 3>/dev/null`
    if [ "$replication" == "on" ]; then
        #debug "Replication: on"
        replication_dataset=`zfs_cache get -H -o value $zfs_replication_dataset_property ${folder} 3>/dev/null`
        if [ "replication_dataset" == '-' ]; then
            replication_dataset=`zfs_cache get -H -o value $zfs_dataset_property ${folder} 3>/dev/null`
        fi
        replication_folder_point=`zfs_cache get -H -o source $zfs_replication_dataset_property ${folder} 3>/dev/null`
        # This could be a child folder, handle appropriately
        if [[ "$replication_folder_point" == "local" || "$replication_folder_point" == "received" ]]; then
            replication_folder="${folder#*/}"
        else
            # This is a child folder.  Find the parent folder that is the replication point.
            replication_pool_folder=`echo "$replication_folder_point" | ${AWK} -F " " '{print $3}'`
            replication_folder="${replication_pool_folder#*/}"
        fi
        # Get the known source
        replication_source=`cat /${pool}/zfs_tools/var/replication/source/${replication_dataset}`
        if [ "$replication_source" == "${pool}:${replication_folder}" ]; then
            snap_this_folder='true'
        fi
    else
        #debug "Replication: off"
        snap_this_folder='true'
    fi

    if [ "$snap_this_folder" == 'false' ]; then
        debug "Skipping snapshot for ${folder} Replication dataset: $replication_dataset Replication source: $replication_source
               Replication folder: ${replication_folder} Replication folder point: $replication_folder_point"
        # Skip this job
        continue
    fi

    keepcount=`zfs_cache get -H -o value ${zfs_snapshot_property}:${snaptype} ${folder} 3>/dev/null`
    
    if [ "${keepcount:0:1}" == "r" ]; then
        # This is a recursive job.  Enumerate all children folders instead of using two snapshot commands
        zfs list -o name -H -r ${folder} | $SED "s,$,@$stamp," >> ${TMP}/snapshots/${snaptype}_${pool}.standard
    else
        echo ${folder}@${stamp} >> ${TMP}/snapshots/${snaptype}_${pool}.standard
    fi

done

if [ -f ${TMP}/snapshots/${snaptype}_${pool}.standard ]; then
    x=1
    # Assemble snapshot command(s)
    echo -n "zfs snapshot " > ${TMP}/snapshots/${snaptype}_${pool}.command.${x}

    while IFS='' read -r line || [[ -n "$line" ]]; do
        if [ $( $STAT --printf="%s" ${TMP}/snapshots/${snaptype}_${pool}.command.${x} ) -lt $command_max ]; then
            echo -n "$line " >> ${TMP}/snapshots/${snaptype}_${pool}.command.${x}
        else
            echo "&" >> ${TMP}/snapshots/${snaptype}_${pool}.command.${x}
            x=$(( x + 1 ))
            echo -n "zfs snapshot " > ${TMP}/snapshots/${snaptype}_${pool}.command.${x}
            echo $line >> ${TMP}/snapshots/${snaptype}_${pool}.command.${x}
        fi
    done < "${TMP}/snapshots/${snaptype}_${pool}.standard"
    echo "2>>${TMP}/snapshots/snapshot_${x}_$$.error.txt" >> ${TMP}/snapshots/${snaptype}_${pool}.command.${x}

    unset IFS

    # Execute snapshots
    debug "Executing $x snapshot commands for snap policy $snaptype on ${pool}"
    
    start_time="$SECONDS"
    y=1
    while [ $y -le $x ]; do
        cp ${TMP}/snapshots/${snaptype}_${pool}.command.${y} ${TMP}/snapshots/snapshot_${y}_$$.error.txt
        source ${TMP}/snapshots/${snaptype}_${pool}.command.${y}
        result=$?
        if [ $result -ne 0 ]; then
            error "Failed snapshot(s) for $pool." ${TMP}/snapshots/snapshot_${y}_$$.error.txt
        fi
        rm ${TMP}/snapshots/snapshot_${y}_$$.error.txt
        y=$(( y + 1 ))
    done

    notice "Completed ${snaptype} snapshots with $x commands on ${pool} in $(( $SECONDS - $start_time )) seconds."


fi

