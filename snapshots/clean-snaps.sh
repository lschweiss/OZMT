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

# collect jobs

pools="$(pools)"

for pool in $pools; do

    jobfolder="/${pool}/zfs_tools/etc/snapshots/jobs"


    for snaptype in $snaptypes; do

        if [ -d "$jobfolder/$snaptype" ]; then
    
            # collect jobs
            jobs=`ls -1 $jobfolder/$snaptype`
            
            for job in $jobs; do
                zfsfolder=`echo $job|${SED} 's,%,/,g'`
                #Make sure we are not a replication target
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
                    # We should not delete snapshot this folder
                    continue
                fi

                keepcount=`cat $jobfolder/$snaptype/$job`
                if [ "${keepcount:0:1}" == "x" ]; then
                    keepcount="${keepcount:1}"
                fi
                if [ "$keepcount" -ne "0" ]; then
                    
                    # Remove snapshots
                    ${TOOLS_ROOT}/snapshots/remove-old-snapshots.sh -c $keepcount -z $zfsfolder -p $snaptype
                else
                    debug "clean-snapshots: Keeping all $snaptype snapshots for $zfsfolder"
                fi
            done

        fi
    
    done


done
