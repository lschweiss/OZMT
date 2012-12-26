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

now=`date +%F_%H:%M:%S%z`


die () {

    echo "$1" >&2
    exit 1

}


backupjobs=`ls -1 $TOOLS_ROOT/backup/jobs/glacier/`

jobstatusdir="$TOOLS_ROOT/backup/jobs/glacier_status"

# Keep track of the job number since each vault was created
mkdir -p $jobstatusdir/sequence
# Each job difinition is archived so failed jobs can be resubmitted
mkdir -p $jobstatusdir/definition
# Jobs that have been created but not yet run
mkdir -p $jobstatusdir/pending
# Jobs which are currently running
mkdir -p $jobstatusdir/running
# Jobs that failed and need to be rerun
mkdir -p $jobstatusdir/failed
# Jobs which have run but are waiting for confirmation the Glacier archive is complete
mkdir -p $jobstatusdir/archiving
# Jobs that have been confirmed to be archived and their predecessor snapshots deleted
mkdir -p $jobstatusdir/complete


# Create snapshots and initialize jobs
for job in $backupjobs; do

    source $TOOLS_ROOT/backup/jobs/glacier/${job}

    snapname="${source_folder}@glacier-backup_${now}"

    # Perform local snapshots

    zfs snapshot -r $snapname


    # Find sequence number

    if [ ! -f "${jobstatusdir}/sequence/${job}" ]; then
        # This is the first sync

        # Create the vault
        vault=`echo $job|sed s,%,.,g`
        glacier-cmd mkvault $vault
        # Initialized the job sequence
        # So that sorting works as expected and we don't anticipate ever have more than 1000 let 
        # alone 10000 jobs per vault, we will start at 1000.  If 
        echo "$glacier_start_sequence" > ${jobstatusdir}/sequence/${job}
        thisjob="$glacier_start_sequence"

    else 

        # This is an incremental job

        # Increment the sequence
        lastjob=`cat ${jobstatusdir}/sequence/${job}`
        thisjob=$(( $lastjob + 1 ))

        echo "$thisjob" > ${jobstatusdir}/sequence/${job}

    fi

    # Initialize the job      
    # Store the orginal job name, snapshot name, sequence number and the time of the snapshot
    echo -e "${job}\t${snapname}\t${thisjob}\t${now}" > ${jobstatusdir}/definition/${job}_${thisjob}
    cp ${jobstatusdir}/definition/${job}_${thisjob} ${jobstatusdir}/pending/${job}_${thisjob}

done

# Launch pending jobs

./launch-glacier-jobs.sh
    


