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

    error "backup_to_glacier: $1"
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

# Keep track of the job number and rotation since each vault was created
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

    source $TOOLS_ROOT/backup/jobs/glacier/active/${job}

    # Get or initialize the rotation number

    if [ ! -f "${jobstatusdir}/sequence/${job}_rotation" ]; then
        # Initialize the rotation
        echo "$glacier_start_rotation" > "${jobstatusdir}/sequence/${job}_rotation"
        rotation="$glacier_start_rotation"
    else
        rotation=`cat ${jobstatusdir}/sequence/${job}_rotation`
    fi

    jobfixup=`echo $job_name|sed s,%,.,g`
    vault="${glacier_vault}-${rotation}-${jobfixup}"


    # Find sequence number

    if [ ! -f "${jobstatusdir}/sequence/${job}_${rotation}" ]; then
        # This is the first sync

        # Create the vault
        glacier-cmd mkvault $vault &> /tmp/glacier_mk_vault_$$ || warning "Could not create vault $vault" /tmp/glacier_mk_vault_$$ 
        debug "backup_to_glacier: Created new Glacier vault $vault"
        # Initialized the job sequence
        # So that sorting works as expected and we don't anticipate ever have more than 1000 let 
        # alone 10000 jobs per vault, we will start at 1000.   
        echo "$glacier_start_sequence" > ${jobstatusdir}/sequence/${job}_${rotation}
        thisjob="$glacier_start_sequence"
        lastjobsnapname=""

        notice "backup_to_glacier: new first job for ${source_folder}, job #${thisjob}"

    else 
        # This is an incremental job

        # Increment the sequence
        lastjob=`cat ${jobstatusdir}/sequence/${job}_${rotation}`
        thisjob=$(( $lastjob + 1 ))
  
        notice "backup_to_glacier: new incremental job #${thisjob} for ${source_folder}"

        # Update the sequence number
        echo "$thisjob" > ${jobstatusdir}/sequence/${job}_${rotation}

        # TODO: Check if we need to start a new rotation

        lastjobsnapname="${source_folder}@glacier-backup_${rotation}_${lastjob}"

    fi

    snapname="${source_folder}@glacier-backup_${rotation}_${thisjob}"


    # Perform the snapshot
    zfs snapshot -r $snapname || die "Could not create snapshot $snapname"
    debug "backup_to_glacier: created snapshot $snapname for job $job"

    # Initialize the job      
    # Store the orginal job name, snapshot name, sequence number and the time of the snapshot
    jobfile="${jobstatusdir}/definition/${job}_${rotation}_${thisjob}"
    echo "jobroot=\"${job}\"" > $jobfile
    echo "jobsnapname=\"${snapname}\"" >> $jobfile
    echo "lastjobsnapname=\"${lastjobsnapname}\"" >> $jobfile
    echo "thisjob=\"${thisjob}\"" >> $jobfile
    echo "snaptime=\"${now}\"" >> $jobfile
    echo "vault=\"${vault}\"" >> $jobfile

    cp ${jobfile} ${jobstatusdir}/pending/


done

# Launch pending jobs

#debug "backup_to_glacier: launching newly created glacier job(s)"

#./launch-glacier-jobs.sh
    


