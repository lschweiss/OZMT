#! /bin/bash

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

_DEBUG="on"
function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

if [ -t 1 ]; then
    background=''
else
    background='&'
fi

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

    rm -f "$temp_file"

    wait_for_lock "$status_file" 5

    # Copy all status lines execept the variable we are dealing with
    while read line; do
        echo "$line" | $grep -q "^local ${variable}="
        if [ $? -ne 0 ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$status_file"

    # Add our variable
    echo "local ${variable}=\"${value}\"" >> "$temp_file"

    # Replace the status file with the updated file
    mv "$temp_file" "$status_file"

    release_lock "$status_file"

    return 0


}

release_holds () {

    local holds="$1"
    local hold=

    for hold in $holds; do
        zfs release zfs_send $hold &> /dev/null || warning "Could not release hold on $hold"
    done

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
    local job_schedule="$3"
    local policy=
    local skip='true'
    local job_backup_snaptag=
    local job_mode=
    local jobstat=
    local now="$(now_stamp)"
    local source_begin_snap=
    local source_end_snap=
    local last_complete_snap=
    local last_increment_snap=
    local target_snapshots=
    local target_host=
    local target_folder=
    local num_snaps=
    local this_snap_num=
    local this_snap=
    local job_snap=
    local holds=
    local backup_source=
    local backup_children=
    local backup_options=
    local found_start=
    local job_running=


    if [ "$3" == "" ]; then
        error "Not enough arguments.  Requires 3, {jobfolder}, {job}, and {job_schedule}"
        return 1
    fi

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

    if [[ "$backup_schedules" != "" && "$job_schedule" != "resume" && "$job_schedule" != "" ]]; then
        for policy in $backup_schedules; do
            if [ "$policy" == "$job_schedule" ]; then 
                debug "This run time, $job_schedule, matches the backup schedule: ${backup_schedules} running backup job."
                skip='false'
            fi
        done
        if [ "$skip" == 'true' ]; then
            debug "This run time, $job_schedule, not in the backup schedule: $backup_schedules"
            return 0
        fi
    else
        skip='false'
    fi

    # We will want to lock on the job.status file
    init_lock "$jobstat"

    echo "$backup_target" | $grep -q ':/'
    if [ $? -eq 0 ]; then
        target_host=`echo $backup_target | $awk -F ":" '{print $1}'`
        target_folder=`echo $backup_target | $awk -F ":/" '{print $2}'`
        debug "Backing up $backup_source to $target_host folder $target_folder"
        timeout 5 ssh root@$target_host echo "Hello world" &> /dev/null
        if [ $? -ne 0 ]; then
            error "Can connect to target host via ssh root@${target_host}"
            return 1
        fi
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
        
    if [ "$job_sechedule" != "resume" ]; then
        source_end_snap="${backup_source}@${job_backup_snaptag}_${now}"
        if [ "$backup_children" == 'true' ]; then
            zfs snapshot -r ${source_end_snap}
            zfs hold -r ${job_backup_snaptag} ${source_end_snap}
        else
            zfs snapshot ${source_end_snap}
            zfs hold ${job_backup_snaptag} ${source_end_snap}
        fi
    fi

    # Make sure a previous instance of this job is not still running

    if [ "$job_running" != "" ]; then
        if [ -e /proc/$job_running ]; then
            ps awwx |$grep -v "grep" | $grep "$job_running " | $grep -q "backup-to-zfs.sh"
            if [ $? -eq 0 ]; then
                notice "Previous instance of this job: $job is still running.   Skipping this run."
                return 0
            fi
        fi
    fi
    
    update_job_status "$jobstat" "job_running" "$$"


    # Generate full list of snapshots
    zfs list -t snapshot -H -o name -s creation | $grep "^${backup_source}@" > $TMP/zfsjob.snaplist.$$
    
    num_snaps=`cat $TMP/zfsjob.snaplist.$$ | wc -l`

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

    echo "$backup_options" | $grep -q " -I \| -i "
    if [ $? -eq 0 ]; then
        incremental='true'
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
    
    found_start='false'

    this_snap_num=1

    while [ $this_snap_num -le $num_snaps ]; do

        # The normal convention is to use 'while read line; do blah;blah; done < file_to_read'
        # This doesn't work here because this loop is meant to be running multiple times in parallel 
        # each process would trample each others input pipe.   Instead we keep track of which line
        # we are processing and grab that line from the file.
    
        this_snap=`cat $TMP/zfsjob.snaplist.$$ | head -n $this_snap_num | tail -n 1`

        job_snap='false'

        holds=''

        # TODO: Each time we complete a backup job snapshot we need to delete older backup job snapshots on source and target

        debug "Processing ${this_snap}"

        # Determine if we skip this ${this_snap} or send it

        # Determine if this is a backup snap
        echo "${this_snap}" | $grep -q "@${job_backup_snaptag}_"
        if [ $? -eq 0 ]; then
            skip='false'
            job_snap='true'
            debug "This is a backup job snapshot"
        else
            skip='true'
        fi

        if [ "$incremental" == 'true' ]; then
            # Determine if the snap type gets skipped
            skip='false'
            for skip in $skiptypes; do 
                echo "${this_snap}" | $grep -q "@${skip}_"
                if [ $? -eq 0 ]; then
                    skip='true'
                fi
            done
        fi

        # Process the snapshot
        
        if [ "$skip" != 'true' ]; then
        
            if [ "$last_increment_snap" == "" ]; then
                # This must be the first pass so we start from the origin
                debug "Starting first pass zfs-send.sh for ${this_snap} to $target_folder"
                if [ "$job_snap" != 'true' ]; then
                    debug "Adding hold to snapshot: $this_snap"
                    zfs hold -t "zfs_send" $this_snap
                    holds="$this_snap $holds"
                fi
                ./zfs-send.sh $backup_options -s "$backup_source" -t "$target_folder" -l "${this_snap}"
                if [ $? -ne 0 ]; then
                    # Send failed
                    error "Failed to send first snapshot ${this_snap}.  Aborting."
                    update_job_status "$jobstat" "job_running" ""
                    release_holds "$holds"
                    return 1
                else
                    found_start='true'
                    debug "Sent ${this_snap} to $target_folder"
                    update_job_status "$jobstat" "last_increment_snap" "${this_snap}"
                    last_increment_snap="${this_snap}"
                    release_holds "$holds"
                fi
            else
                if [ "$found_start" == 'false' ]; then
                    if [ "${this_snap}" == "$last_increment_snap" ]; then
                        debug "Found last completed incremental snap ${this_snap}"
                        found_start='true'
                    fi
                else
                    # No more reason to skip
                    if [ "$job_snap" != 'true' ]; then
                        debug "Adding hold to snapshot: $this_snap" 
                        zfs hold -t "zfs_send" $this_snap
                        holds="$this_snap $holds"
                    fi
                    echo "$last_increment_snap" | $grep -q "@${job_backup_snaptag}_"
                    if [ $? -ne 0 ]; then
                        debug "Adding hold to snapshot: $last_increment_snap"
                        zfs hold -t "zfs_send" $last_increment_snap
                        holds="$last_increment_snap $holds"
                    fi
                    debug "Starting zfs-send.sh for $last_increment_snap to ${this_snap}"
                    ./zfs-send.sh $backup_options -s "$backup_source" -t "$target_folder" -f "$last_increment_snap" -l "${this_snap}"
                    if [ $? -ne 0 ]; then
                        # Send failed
                        error "Failed to send from $last_complete_snap to ${this_snap}.  Aborting."
                        update_job_status "$jobstat" "job_running" ""
                        release_holds "$holds"
                        return 1
                    else
                        debug "Sent from $last_increment_snap to ${this_snap} to $target_folder"
                        update_job_status "$jobstat" "last_increment_snap" "${this_snap}"                       
                        last_increment_snap="${this_snap}"
                        release_holds "$holds"
                    fi
                fi
            fi

            if [ "$job_snap" == 'true' ]; then
                update_job_status "$jobstat" "last_complete_snap" "${this_snap}"
                last_complete_snap="${this_snap}"
                ./delete-previous-snaps.sh -f "$backup_source" -n "$job_backup_snaptag" \
                    -t "$job_backup_snaptag" -l "$last_complete_snap" & #$background
                echo
                if [ "$target_host" == '' ]; then
                    ./delete-previous-snaps.sh -f "$target_folder" -n "$job_backup_snaptag" \
                        -t "$job_backup_snaptag" -l "$last_complete_snap" & #$background
                else
                    target_last_snap=`echo "$last_complete_snap" | $sed s,${backup_source},${target_folder},g`
                    ./delete-previous-snaps.sh -h "$target_host" -f "$target_folder" -n "$job_backup_snaptag" \
                        -t "$job_backup_snaptag" -l "$target_last_snap" & #$background
                fi
    
            fi
            
    
            if [ "$last_complete_snap" == "$source_end_snap" ]; then   
                break
            fi

        fi

        this_snap_num=$(( this_snap_num + 1 ))
       
    done 
   
    update_job_status "$jobstat" "job_running" ""
    
    rm $TMP/zfsjob.snaplist.$$

}

####
####
##
## Main processing loop
##
####
####

# If lauched from the console, operate on inputs of {pool} {folder} {job_schedule}

if [ -t 1 ]; then

    MIN_ARGS=3

    if [ "$#" -lt "$MIN_ARGS" ]; then
        echo "Running on console requires 3 inputs:"
        echo " backup-to-zfs.sh {pool} {folder} {job_schedule}"
        exit 1
    fi

    pool="$1"
    jobfolder="/${pool}/zfs_tools/etc/backup/jobs/zfs"
    statfolder="/${pool}/zfs_tools/etc/backup/stat/zfs"
    job=`echo "${pool}/$2" | $sed s,/,%,g`

    zfsjob "$jobfolder" "$job" "$3"

else  
    
    pools="$(pools)"
    
    for pool in $pools; do
    
        jobfolder="/${pool}/zfs_tools/etc/backup/jobs/zfs"
        statfolder="/${pool}/zfs_tools/etc/backup/stat/zfs"
    
        if [ -d "${jobfolder}" ]; then
    
            backupjobs=`ls -1 ${jobfolder}/`
    
            for job in $backupjobs; do
                notice "Launching zfs backup job $job"
                zfsjob "$jobfolder" "$job" "$1" $background
            done
        fi
        
    
    done # for pool    

fi
