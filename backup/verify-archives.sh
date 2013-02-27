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

die () {

    error "verify-archives: $1"
    exit 1

}

backupjobs=`ls -1 $TOOLS_ROOT/backup/jobs/glacier/active/`
jobstatusdir="$TOOLS_ROOT/backup/jobs/glacier/status"

if [ "x$glacier_logfile" != "x" ]; then
    logfile="$glacier_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$glacier_report" != "x" ]; then
    report_name="$glacier_report"
else
    report_name="$default_report_name"
fi

for job in $backupjobs; do

    source $TOOLS_ROOT/backup/jobs/glacier/active/${job}

    # Get the rotation number

    if [ ! -f "${jobstatusdir}/sequence/${job}_rotation" ]; then
        # No rotation number(s) exist for the job.  Assume starting rotation
        rotations="$glacier_start_rotation"
    else
        rotations=`cat ${jobstatusdir}/sequence/${job}_rotation`
    fi

    jobfixup=`echo $job_name|sed s,%,.,g`

    for rotation in $rotations; do

        vault="${glacier_vault}-${rotation}-${jobfixup}"

        # Find sequence number
        if [ ! -f "${jobstatusdir}/sequence/${job}_${rotation}" ]; then
            debug "No sequence defined for ${job}_${rotation}.  Skipping."
        else
            lastjob=`cat ${jobstatusdir}/sequence/${job}_${rotation}`
            
            # Step through sequences confirming if the archive job is in the latest inventory.
            # Delete any sequential snapshot that is no longer needed.
        
            jobnum="$glacier_start_sequence"
    
            while [ "$jobnum" -lt "$lastjob" ]; do

                # collect the job record

                # collect the inventory record

                # if inventory complete delete previous snapshot otherwise break 
                


                
                jobjum=$(( $jobnum + 1 ))
            done
        fi
    
    done # for rotation

done # for job



