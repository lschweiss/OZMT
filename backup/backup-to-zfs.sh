#! /bin/bash -x

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2014  Chip Schweiss

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


if [ "x$zfs_logfile" != "x" ]; then
    logfile="$zfs_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$zfs_report" != "x" ]; then
    report_name="$zfs_report"
else
    report_name="$default_report_name"
fi


debug () {
    echo "DEBUG: $1"
}

notice () {
    echo "NOTICE: $1"
}

update_job_status () {

    # TODO: Make this thread safe so jobs can be made multipart.

    # Takes three input parameters.
    # 1: Job status file
    # 2: Variable to update or add
    # 3: Content of the variable

    local line=
    local temp_file="$TMP/update_job_status_$$"

    # Minimum number of arguments needed by this function
    local MIN_ARGS=3

    if [ "$#" -lt "$MIN_ARGS" ]; then
        error "update_job_status called with too few arguments.  $*"
        exit 1
    fi

    local status_file="$1"
    local variable="$2"
    local value="$3"

    rm -f "$tempfile"

    # Copy all status lines execept the variable we are dealing with
    while read line; do
        echo "$line" | grep -q "^local ${variable}="
        if [ $? -ne 0 ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$status_file"

    # Add our variable
    echo "local ${variable}=\"${value}\"" >> "$temp_file"

    # Replace the status file with the updated file
    mv "$temp_file" "$status_file"

    return 0


}




##
#
# zfsjob is launched as a background process and functions on its own for each backup job
#
##


zfsjob () {

    # All variables used must be copied to a local variable because this function will be called
    # multiple times as a job fork.

    local jobfolder="$1"
    local job="$2"
    local resume_job="$3"
    local job_backup_snaptag=
    local job_mode=
    local now="$(now_stamp)"
    local source_begin_snap=
    local source_end_snap=
    local last_complete_snap=
    local target_snapshots=
    local target_host=
    local target_folder=
    local snap=
    local found_start=

    source ${jobfolder}/${job}

    jobstat="${statfolder}/${job}/job.status"

    # Determine if we've backed up before
    if [ -f "$jobstat" ]; then
        source "$jobstat"
    else
        # Create job accounting folder
        mkdir -p "${statfolder}/${job}"
        touch "$jobstat"
    fi
    
    echo "$backup_target" | grep -q ':/'
    if [ $? -eq 0 ]; then
        target_host=`echo $backup_target | awk -F ":" '{print $1}'`
        target_folder=`echo $backup_target | awk -F ":/" '{print $2}'`
        debug "Backing up $backup_source to $target_host folder $target_folder"
    else
        target_host=''
        target_folder="$backup_target"
        debug "Backing up $backup_source to folder $target_folder"
    fi

    # Create snapshot for this new increment
    if [ "$job_backup_snaptag" == "" ]; then
        if [ "$zfs_backup_snaptag" == "" ]; then
            job_backup_snaptag="zfs_tools_backup"
        else
            job_backup_snaptag="$zfs_backup_snaptag"
        fi
    fi
        
    if [ "$resume_job" != "resume" ]; then
        source_end_snap="${backup_source}@${job_backup_snaptag}_${now}"
        if [ "$backup_children" == 'true' ]; then
            zfs snapshot -r ${source_end_snap}
            zfs hold -r ${job_backup_snaptag} ${source_end_snap}
        else
            zfs snapshot ${source_end_snap}
            zfs hold ${job_backup_snaptag} ${source_end_snap}
        fi
    fi

    # Generate full list of snapshots
    zfs list -t snapshot -H -o name -s creation | $grep "^${backup_source}@" > $TMP/zfsjob.snaplist.$$
    
    cat $TMP/zfsjob.snaplist.$$

    if [ "$source_end_snap" == "" ]; then
        # Lookup last source snapshot for backup
        source_end_snap=`cat $TMP/zfsjob.snaplist.$$| $grep "^${backup_source}@${job_backup_snaptag}_" | tail -1`
    fi


    # Build zfs-send.sh options
    if [ "$backup_options" == "" ]; then
        backup_options="-d -p readonly=on"
    fi

    # Local or remote backup
    if [ "$target_host" != "" ]; then
        # Use bbcp and lz4 compression for remote backups
        # TODO: Add tuning for BBCP
        backup_options="-h $target_host -b 30 -z 1 $backup_options"
    else
        # Use mbuffer for local backups
        backup_options="-m $backup_options"
    fi

    if [ "$backup_children" == "true" ]; then
        backup_options="-r $backup_options"
    fi

    if [ "$last_complete_snap" != "" ]; then
        # Verify recorded last completed snapshot is on the destination
        debug "Need destination verification."



    fi

    if [ "$incremental" == 'true' ] && [ "$last_increment_snap" != "" ]; then
        # Verify recorded last completed incremental snapshot is the destination
        debug "Need destination verification."


    fi

    
    # Loop until completed snapshot is most current
    
    found_snap='false'

    while read snap; do

        # Determine if we skip this $snap or send it

        if [ "$incremental" == 'true' ]; then
            # Determine if the snap type gets skipped
            skip='false'
            for skip in $skiptypes; do 
                echo "$snap" | $grep -q "^@${skip}"
                if [ $? -eq 0 ]; then
                    skip='true'
                fi
            done
        else
            # Determine if this is a backup snap
            echo "$snap" | $grep -q "@${job_backup_snaptag}_"
            if [ $? -eq 0 ]; then
                skip='false'
            else
                skip='true'
            fi
        fi
        
        if [ "$skip" != 'true' ]; then
        
            if [ "$last_increment_snap" == "" ]; then
                # This must be the first pass so we start from the origin
                debug "Starting zfs-send.sh for $snap to $target_folder"
                ./zfs-send.sh $backup_options -s "$backup_source" -t "$target_folder" -l "$snap"
                if [ $? -ne 0 ]; then
                    # Send failed
                    error "Failed to send first snapshot $snap.  Aborting."
                    return 1
                else
                    debug "Sent $snap to $target_folder"
                    update_job_status "$jobstat" "last_increment_snap" "$snap"
                    last_increment_snap="$snap"
                fi
            else
                if [ "$found_snap" != 'false' ]; then
                    if [ "$snap" == "$last_increment_snap" ]; then
                        found_snap='true'
                    else
                        # No more reason to skip
                        debug "Starting zfs-send.sh for $last_complete_snap to $snap"
                        ./zfs-send.sh $backup_options -s "$backup_source" -t "$target_folder" -f "$last_increment_snap" -l "$snap"
                        if [ $? -ne 0 ]; then
                            # Send failed
                            error "Failed to send from $last_complete_snap to $snap.  Aborting."
                            return 1
                        else
                            debug "Sent $snap to $target_folder"
                            update_job_status "$jobstat" "last_increment_snap" "$snap"
                            last_complete_snap="$snap"
                        fi
                    fi
                fi
            fi
    
            if [ "$last_increment_snap" == "$source_end_snap" ]; then   
                update_job_status "$jobstat" "last_complete_snap" "$snap"
                break
            fi

        fi
    
       
    done < $TMP/zfsjob.snaplist.$$
   


    rm $TMP/zfsjob.snaplist.$$

}

####
####
##
## Main processing loop
##
####
####

pools="$(pools)"

for pool in $pools; do

    jobfolder="/${pool}/zfs_tools/etc/backup/jobs/zfs"
    statfolder="/${pool}/zfs_tools/etc/backup/stat/zfs"

    backupjobs=`ls -1 ${jobfolder}/`

    for job in $backupjobs; do
        notice "Launching zfs backup job $job"
        zfsjob "$jobfolder" "$job" &
    done
    

done # for pool    


