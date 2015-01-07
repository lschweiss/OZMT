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

jobfolder="$TOOLS_ROOT/snapshots/jobs"

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

# collect jobs

pools="$(pools)"

for pool in $pools; do

    jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"

    if [ -d $jobfolder/$snaptype ]; then
    
        jobs=`ls -1 $jobfolder/$snaptype`
        
        for job in $jobs; do
            zfsfolder=`echo $job|${SED} 's,%,/,g'`
            # Make sure we are not a replication target
            case $(replication_source $zfsfolder) in 
                'ERROR')
                    # zfsfolder does not exist
                    snap_this_folder='false'
                    ;;
                'NONE')
                    # No replication
                    snap_this_folder='true'
                    ;;
                "$pool")
                    # This is a source folder
                    snap_this_folder='true'
                    ;;
                *)
                    # This is a target folder
                    snap_this_folder='false'
                    ;;
            esac
            if [ "$snap_this_folder" == 'false' ]; then
                # We should not snapshot this folder
                continue
            fi

            keepcount=`cat $jobfolder/$snaptype/$job`
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
            echo
        done
    
    else 
        notice "process-snap: No snap type(s) $snaptype defined."
    fi

done

