#! /bin/bash 

#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2015  Chip Schweiss

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


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

. ../zfs-tools-init.sh

# catch the PATH on Solaris
if [ -f $HOME/.profile ]; then
    . $HOME/.profile
fi

if [ "x$rsync_report" != "x" ]; then
    report_name="$rsync_report"
else
    report_name="$default_report_name"
fi

. ./functions.sh

#export PATH=/usr/gnu/bin:/usr/bin:/usr/sbin:/sbin:/usr/local/bin

return=0

# show program usage
show_usage() {
    echo
    echo "Usage: $0 [-x exclude_file] [-d date] {source_folder} {target_folder}"
    echo "  [-x exclude_file] Exclude File should contain one folder/file/pattern per line."
    echo "  [-d date] Date must be of the same format as in snapshot folder name"
    echo "  [-c cns_folder_exclude_file] Exclude file listing CNS folders to exclude from this job"
    echo "  [-k compare based on checKsum not metadata]"
    echo "  [-D] Don't delete on target"
    echo "  [-u] Update on targert"
    echo "  [-t] trial mode.  Only output what would happen"
    echo "  [-p] Turn on --progress and --verbose for rsync."
    echo "  [-a] Turn on verbose and attach output to logs."
    echo "  [-s n] Split in to n rsync jobs. Incompatitble with CNS root folders."
    echo "  [-z n] scan n folders deep for split jobs"
    echo "  [-e options] remote shell program.  Passed directly as -e 'options' to rsync"
    echo "      [-i] SSH is incoming, defaults to outgoing"
    echo "  [-n name] job name.  Defaults to source folder."
    echo "  [-r] dry Run."
    echo "  [-P path] Remote rsync path"
    echo
    exit 1
}

# Minimum number of arguments needed by this program
MIN_ARGS=2

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

exclude_file_flag=
date_flag=
dont_delete_flag=
update_flag=
trial_mode_flag=
cns_exclude_flag=
use_chksum_flag=
split_rsync_flag=
incoming_via_ssh_flag=
dry_run_flag=
progress_verbose_flag=
attach_verbose_output_flag=
remote_shell_flag=
dereference_symlinks_flag=
scan_depth_flag=
job_name_flag=
remote_rsync=
scan_depth=1

progress=""

while getopts apkirtDuc:x:d:s:e:z:l:n:P: opt; do
    case $opt in
        x)  # Exclude File Specified
            exclude_file_flag=1
            exclude_file="$OPTARG";;
        d)  # Date Specified
            date_flag=1
            sync_date="$OPTARG";;
        c)  # CNS Exclude File Specified
            cns_exclude_flag=1
            cns_exclude_file="$OPTARG";;
        k)  # Use checksum comparison
            use_chksum_flag=1;;
        a)  # Turn on verbose and attachements
            DEBUG=true
            attach_verbose_output_flag=1;;
        p)  # Turn on progress and verbose
            progress_verbose_flag=1;;
    	D)  # Don't delete on the target
	        dont_delete_flag=1;;
        u)  # Update sync
            update_flag=1;;
        t)  # Trial mode
            debug "Using trial mode"
            trial_mode_flag=1;;
        r)  # Dry Run
            debug "Doing a dry run of rsync"
            dry_run_flag=1;;
        P)  # Remote rsync path
            remote_rsync="$OPTARG"
            ;;
        s)  # Split rsync jobs
            split_rsync_flag=1
            split_rsync_job_count="$OPTARG"
            debug "Splitting into $split_rsync_job_count jobs";;
        z)  # Scan depth for split jobs
            scan_depth_flag=1
            scan_depth="$OPTARG";;
        n)  # Job name
            job_name_flag=1
            job_name_value="$OPTARG";;
        e)  # Use remote shell
            remote_shell_flag=1
            remote_shell_value="$OPTARG";;
        i)  # Incoming via SSH (Source folder is via ssh)
            incoming_via_ssh_flag=1;;
        l)  # Dereference symlinks
            dereference_symlinks_flag=1;;
        ?)  # Show program usage and exit
            show_usage
            exit 1;;
        :)  # Mandatory arguments not specified
            echo "Option -$OPTARG requires an argument."
            exit 1;;
    esac
done

# Exclude file parameter
if [ ! -z "$exclude_file_flag" ]; then
    #echo "Option -x $exclude_file specified"
    debug "Attempting to use given Exclude File"
    if [ -f $exclude_file ]; then
        exclude_file_option="--exclude-from=${exclude_file}"
        debug "Using Exclude File: $exclude_file"
    else
        debug "Exclude file $exclude_file not found!"
        exit 1
    fi
fi
# Date parameter
if [ ! -z "$date_flag" ]; then
    #echo "Option -d $sync_date specified"
    debug "Attempting to use given snapshot date"
    this_date=$sync_date
    # Assume we are running interactively if a date is specified
    #progress_verbose_flag=1
else
    # Default to today's date
    debug "Defaulting to today's date"
    this_date=`${DATE} +%F`
fi
debug "Using Date: $this_date"

if [ ! -z "$progress_verbose_flag" ]; then
    progress="--verbose --progress"
fi

# Don't delete on target
if [ ! -z $dont_delete_flag ]; then
    debug "NOT deleting on the target"
    delete_on_target=''
else
    debug "DELETING on the target"
    delete_on_target='--delete'
fi

#Move to remaining arguments
shift $(($OPTIND - 1))
#echo "Remaining arguments are: $*"

# Source folder parameter
if [ -d $1 ]; then
    source_folder=$1
else
    # Check for source via SSH
    if [ "$incoming_via_ssh_flag" == "1" ]; then
        # Find hostname and remote source folder
        IFS=":" 
        read -r source_host remote_source_folder <<< "$1"
        unset IFS
        # check that it exists
        # TODO: fix this so it can correctly handle spaces in folder names
        ssh $source_host ls -1 "$remote_source_folder" > /dev/null
        if [ $? -ne 0 ]; then
            error "${jobname} Source folder $1 does not exist!"
            exit 1
        fi
    else
        error "${jobname} Source folder $1 does not exist!"
        exit 1
    fi
fi

# Target folder parameter
if [ -d $2 ]; then
    target_folder=$2
else
    if [ ! -z "$remote_shell_flag" ]; then
        debug "Assuming remote target folder $2 exists.  Cannot check from here."
        target_folder=$2
    else
        error "${jobname} Target folder $2 does not exist!"
        exit 1
    fi
fi

if [ "$dry_run_flag" == "1" ]; then
    extra_options="--dry-run"
else
    extra_options="$progress"
fi

if [ "$attach_verbose_output_flag" == "1" ]; then
    debug "Using verbose and attaching logs"
    extra_options="${extra_options} -v"
fi

if [ ! -z "$remote_shell_flag" ]; then
    debug "Using remote shell: $remote_shell_value"
    extra_options="${extra_options} -e ${remote_shell_value}"
fi

if [ ! -z "$dereference_symlinks_flag" ]; then
    debug "Dereferencing symlinks"
    extra_options="${extra_options} --copy-links"
fi

if [ ! -z "$use_chksum_flag" ]; then
    debug "Using checksum file comparison"
    extra_options="${extra_options} --checksum"
fi

if [ ! -x "$job_name_flag" ]; then
    debug "Setting job name to $job_name_value"
    jobname="$job_name_value"
else
    debug "Setting job name to $source_folder"
    jobname="$source_folder"
fi

if [ ! -z "$update_flag" ]; then
    debug "Updating on destination"
    extra_options="${extra_options} --update"
fi

if [ ! -z "$remote_rsync" ]; then
    extra_options="${extra_options} --rsync-path=$remote_rsync"
fi




####
#
# Split rsync function
#
###


split_rsync () {

    local rsync_result=-1
    local try=0
    local basedir=

    if [ "$incoming_via_ssh_flag" == "1" ]; then
        basedir="${source_host}:${snapdir}/${snap}"
    else
        basedir="${snapdir}/${snap}"
    fi

    # Function used to run a parallel rsync job
    debug "${RSYNC} -arS ${delete_on_target} --relative \
            --stats $extra_options --exclude=.history --exclude=.snapshot \
            --files-from=${1} $basedir/ $target_folder"
    if [ "$trial_mode_flag" != 1 ]; then
        while [ $rsync_result -ne 0 ]; do
            ${RSYNC} -arS ${delete_on_target} --relative  \
                --stats $extra_options --exclude=.history --exclude=.snapshot \
                --files-from=${1} $basedir/ $target_folder &> ${1}.log 
    	    rsync_result=$? 

            if [ $rsync_result -eq 23 ]; then
                # Check if rsync failed to delete empty directories
                remove_empty_dirs ${1}.log $target_folder
            fi
            
            try=$(( try + 1 ))
            if [ $rsync_result -ne 0 ]; then
                warning "${source_folder} Job failed with error code $rsync_result" ${1}.log
                if [ $try -eq 3 ]; then
                    error "${jobname} Job for $1 failed 3 times. Giving up. " ${1}.log
                    break;
                else
                    notice "${jobname} Job for $1 failed.  Will try up to 3 times."
                    sleep 15m
                fi
            fi

            if [ "$attach_verbose_output_flag" == "1" ]; then
                cat ${1}.log
                notice "${jobname} split job ${1} logs attached" ${1}.log
            fi

        done

        # clean up temp files
        rm -f ${1} &>/dev/null
        
    fi

    touch ${1}.complete
}

####
#
# Remove files/directories on destination that fall below the scan depth 
# that have been deleted on the source side.
#
####

# When using split rsync jobs --delete only works on files and folder
# that are are deeper than the scan depth.
#
# This routine collects all files and folders on the destination side 
# checkes each of them if they exist on the source side.  If they don't
# exist on the source side they are deleted from the destination.


remove_missed_deletes () {

    local destination_ssh=
    local destination_basedir=
    local source_ssh=
    local source_basedir=
    local delete_count=0

    # Test sed
    # Requires sed version 4.2.2 or newer that supports -z/--null-data
    echo "Hello world" | ${SED} --null-data 's,Hello,Goodbye,g' > /dev/null
    if [ $? -ne 0 ]; then
        error "Removing missed deletes requires sed 4.2.2 or newer. Current version $(${SED} --version)"
        return 1
    fi

    if [ ! -z $dont_delete_flag ]; then
        debug "Skipping remove_missed_deletes, because we are not deleting on the target."
        return 0
    fi

    set -x

    # Setup source and destination details
    # TODO: Don't assume SSH this can be all local

    if [ "$incoming_via_ssh_flag" == "1" ]; then
        source_basedir="$remote_source_folder"
        source_ssh="ssh $source_host"
        destination_basedir="$target_folder"
        desination_ssh=''
    else
        source_basedir="$basedir"
        source_ssh=''
        IFS=":"
        read -r destination_host destination_basedir <<< "$target_folder"
        unset IFS 
        destination_ssh="ssh $destination_host"
    fi

    # TODO: Filter out exclusions

    find_command="find -maxdepth $scan_depth -regextype posix-egrep ! -regex '\.' ! -regex '\./\.snapshot/.*' ! -regex '\./\.zfs/.*' ! -regex '\./\.history.*' -print0"
    set +x

    # Collect lists
    debug "${jobname}: Collecting files/directories on the SOURCE below the scan depth of $scan_depth:"
    set -x

    exec_command="( pushd . >/dev/null ; cd $source_basedir ; $find_command ; popd > /dev/null )"

    if [ "$source_ssh" != "" ]; then
        $source_ssh "( cd $source_basedir ; $find_command )" | \
            ${SED} --null-data 's/^..//' | \
            ${SORT} --reverse --zero-terminated > ${TMP}/sync_folder_list_$$_post_delete_source
    else
        ( cd $source_basedir ; $find_command ) | \
            ${SED} --null-data 's/^..//' | \
            ${SORT} --reverse --zero-terminated > ${TMP}/sync_folder_list_$$_post_delete_source
    fi
    set +x
    if [ "$DEBUG" == 'true' ]; then
        cat ${TMP}/sync_folder_list_$$_post_delete_source | xargs -0 -I '{}' echo '{}'
    fi

    debug "${jobname}: Collecting files/directories on the DESTINATION below the scan depth of $scan_depth:"
    set -x
    if [ "$destination_ssh" != "" ]; then
        $destination_ssh "( cd $destination_basedir ; $find_command )" | \
            ${SED} --null-data 's/^..//' | \
            ${SORT} --reverse --zero-terminated > ${TMP}/sync_folder_list_$$_post_delete_destination
    else
        ( cd $destination_basedir ; $find_command ) | \
            ${SED} --null-data 's/^..//' | \
            ${SORT} --reverse --zero-terminated > ${TMP}/sync_folder_list_$$_post_delete_destination
    fi


    set +x
    if [ "$DEBUG" == 'true' ]; then
        cat ${TMP}/sync_folder_list_$$_post_delete_destination | xargs -0 -I '{}' echo '{}'
    fi

    # Compare lists
    cat ${TMP}/sync_folder_list_$$_post_delete_destination | \
    while read -r -d $'\0' x; do
        cat ${TMP}/sync_folder_list_$$_post_delete_source | ${GREP} --null -q -x "${x}"
        if [ $? -ne 0 ]; then
            delete_count=$(( delete_count + 1 ))
            if [ "$dry_run_flag" == '1' ]; then
                debug "File/folder $x is on destination, but not source.  Dry run. Not deleting"
            else
                debug "File/folder $x is on destination, but not source, deleting. $delete_count"
                echo $x >> ${TMP}/sync_folder_${jobname}_delete_list
                # TODO: Put delete delete code here
            fi
        fi 
    done

    notice "${jobname}: Deleted $delete_count files/directories below scan depth of $scan_depth"

    # TODO: Get count of destination and source lists --> sed -nz '$='
    # Compare difference with delete_count


}

####
#
# Remove empty folders on destination
#
####

# When using --delete option on rsync, if a source folder is deleted, rsync sometimes
# fails to delete the target because it doesn't empty the directory first.

# This function will parse the output log and remove directories on the target 

remove_empty_dirs () {

    local logfile="$1"
    local target="$2"

    # Can't do this when using a remote connection
    if [ -z "$remote_shell_flag" ]; then
        cat $logfile | ${GREP} -q "cannot delete non-empty directory: "
        has_empties=$?

        if [ $has_empties -eq 0 ]; then
            empties=`cat $logfile | \
                     ${GREP} "cannot delete non-empty directory: " | \
                     ${AWK} -F "cannot delete non-empty directory: " '{print $2}'`

            for empty in $empties; do
                warning "removing empty directory $target/$empty which rsync failed to remove"
                rm -rf \"$target/$empty\"
            done
        fi

    fi
    
}
    

####
#
# Output stats
#
####

output_stats () {

    # Collect stats

    local x=0
    local num_files=0
    local num_files_trans=0
    local total_file_size=0
    local total_transfered_size=0

    local log_name="$1"

    local indent=`head -c ${#jobname} < /dev/zero | tr '\0' '\040'`

    logs=`ls -1 ${TMP}|${GREP} ${log_name}|${GREP} ".log"`

    for log in ${logs} ; do
        if [ -f ${TMP}/$log ]; then
            debug "Adding totals for ${TMP}/$log"
            if [ "$DEBUG" == 'true' ]; then
                cat ${TMP}/$log
            fi
            this_num_files=`cat ${TMP}/$log | ${SED} 's/,//g' | ${GREP} "Number of files:" | ${AWK} -F ": " '{print $2}'`
            if echo "$this_num_files"|grep -q "reg"; then
                this_num_files=`echo "$this_num_files"|awk -F " " '{print $1}'`
            fi
            this_num_files_trans=`cat ${TMP}/$log | ${SED} 's/,//g' | ${GREP} "files transferred:" | ${AWK} -F ": " '{print $2}'`
            this_total_file_size=`cat ${TMP}/$log | ${SED} 's/,//g' | ${GREP} "Total file size:" | ${AWK} -F " " '{print $4}'` 
            this_total_transfered_size=`cat ${TMP}/$log | ${SED} 's/,//g' |${GREP} "Total transferred file size:" | ${AWK} -F " " '{print $5}'`
            # Add to totals
            let "num_files = $num_files + $this_num_files"
            let "num_files_trans = $num_files_trans + $this_num_files_trans"
            let "total_file_size = $total_file_size + $this_total_file_size"
            let "total_transfered_size = $total_transfered_size + $this_total_transfered_size"  
            x=$(( $x + 1 ))
        fi
    done

    # Output totals

    notice "${jobname} ******* Rsync Totals *******"
    notice "    Number of jobs: $x"
    notice "    Number of files: $num_files"
    notice "    Number of files transfered: $num_files_trans"
    notice "    Total_file_size: $(bytestohuman $total_file_size)"
    notice "    Total Transfered size: $(bytestohuman $total_transfered_size)"
    
    # DEBUG set +x
        
} # output_stats





if [[ "$incoming_via_ssh_flag" == "1" || -d "${source_folder}/.snapshot" || -d "${source_folder}/.zfs/snapshot" ]]; then
    if [ "$incoming_via_ssh_flag" == "1" ]; then
        ssh $source_host ls -1 "${remote_source_folder}/.snapshot" > /dev/null
        if [ $? -eq 0 ]; then
            debug "${jobname}: ${remote_source_folder}/.snapshot found."
            snapdir="${remote_source_folder}/.snapshot"
        fi
        ssh $source_host ls -1 "${remote_source_folder}/.zfs/snapshot" > /dev/null
        if [ $? -eq 0 ]; then
            debug "${jobname}: ${remote_source_folder}/.zfs/snapshot found."
            snapdir="${remote_source_folder}/.zfs/snapshot"
        fi
        snap=`locate_snap "$snapdir" "$this_date" "daily" "$source_host"`
        # Check the return status of 'locate_snap'
        if [ $? -eq 0 ] ; then
            debug "Snapshot folder located: $snap"
            snap_label="snap-daily_${snap}"
        else
            # If snapshot was not located, output the error message and exit
            error "${jobname} Could locate snapshot: $snap"
            exit 1
        fi
    else
        if [ -d "${source_folder}/.snapshot" ]; then
            debug "${jobname}: ${source_folder}/.snapshot found."
            snapdir="${source_folder}/.snapshot"
        fi
        if [ -d "${source_folder}/.zfs/snapshot" ]; then
            debug "${jobname}: ${source_folder}/.zfs/snapshot found."
            snapdir="${source_folder}/.zfs/snapshot"
        fi
        # Below syntax captures output of 'locate_snap' function
        snap=`locate_snap "$snapdir" "$this_date" "daily"`
        # Check the return status of 'locate_snap'
        if [ $? -eq 0 ] ; then
            debug "Snapshot folder located: $snap"
            snap_label="snap-daily_${snap}"
        else
            # If snapshot was not located, output the error message and exit
            error "${jobname} Could locate snapshot: $snap"
            exit 1
        fi
    fi

    notice "${jobname} Starting rsync job(s)"


    joblog="${TMP}/sync_folder_$$.log"
    
    if [ "$split_rsync_flag" != "1" ]; then
        if [ "$incoming_via_ssh_flag" == "1" ]; then
            basedir="${source_host}:${snapdir}/${snap}"
        else
            basedir="${snapdir}/${snap}"
        fi
        # Run rsync
        debug "rsync -aS ${delete_on_target} --stats $extra_options --exclude=.snapshot $exclude_file_option $basedir/ $target_folder"
        if [ "$trial_mode_flag" != "1" ]; then
            echo "rsync -aS ${delete_on_target} --stats $extra_options --exclude=.snapshot $exclude_file_option \
                $basedir/ $target_folder" > ${TMP}/sync_snap_folder_$$.log
            ${RSYNC} -aS ${delete_on_target} --stats $extra_options --exclude=.snapshot $exclude_file_option \
                $basedir/ $target_folder &>> ${TMP}/sync_snap_folder_$$.log
            rsync_result=$?

            if [ $rsync_result -eq 23 ]; then
                # Check if rsync failed to delete empty directories
                remove_empty_dirs ${TMP}/sync_snap_folder_$$.log $target_folder
            fi

            if [ $rsync_result -ne 0 ]; then
                error "${basedir} Job failed with error code $rsync_result" ${TMP}/sync_snap_folder_$$.log
            fi
            if [ "$attach_verbose_output_flag" == "1" ]; then
                cat ${TMP}/sync_snap_folder_$$.log
                notice "$basedir complete logs attached." ${TMP}/sync_snap_folder_$$.log
            fi
            output_stats "sync_snap_folder_$$" 
        fi
    else
        ##
        #
        # Split rsync
        #
        ##
    
        notice "${jobname}: Splitting into $split_rsync_job_count rsync job(s), scan depth $scan_depth"

        basedir="${snapdir}/${snap}"

        # Collect lists
        if [ "$incoming_via_ssh_flag" == "1" ]; then
            debug "${jobname}: Collecting lists - Remote Directories:"
            ssh $source_host find $basedir -mindepth $scan_depth -maxdepth $scan_depth -type d | \
                ${SED} "s,${basedir}/,," | \
                ${GREP} -v "$.snapshot" | \
                ${GREP} -v "$.zfs" | \
                ${GREP} -v ".history" > \
                ${TMP}/sync_folder_list_$$
            if [ "$DEBUG" == 'true' ]; then
               cat ${TMP}/sync_folder_list_$$
            fi
        else
            debug "${jobname}: Collecting lists - Local Directories:"
            find $basedir -mindepth $scan_depth -maxdepth $scan_depth -type d | \
            ${SED} "s,${basedir}/,," | \
                ${GREP} -v "$.snapshot" | \
                ${GREP} -v "$.zfs" | \
                ${GREP} -v ".history" > \
                ${TMP}/sync_folder_list_$$ 2>${TMP}/sync_folder_list_$$_find_error
            if [ $(cat ${TMP}/sync_folder_list_$$_find_error|wc -l) -gt 0 ]; then
                error "${jobname}: Find error detected" ${TMP}/sync_folder_list_$$_find_error
            fi
            if [ "$DEBUG" == 'true' ]; then
                echo "find $basedir -mindepth $scan_depth -maxdepth $scan_depth -type d | ${SED} "s,${basedir}/,," |  ${GREP} -v "$.snapshot" | ${GREP} -v "$.zfs" |  ${GREP} -v ".history" > ${TMP}/sync_folder_list_$$ "
                cat ${TMP}/sync_folder_list_$$
            fi
        fi

        # Add files that may be at a depth less than or equal to the test above

        if [ "$incoming_via_ssh_flag" == "1" ]; then
            debug "${jobname}: Collecting lists - Remote Files:"
            ssh $source_host find $basedir -maxdepth $scan_depth \! -type d | \
                ${SED} "s,${basedir}/,,"  >> ${TMP}/sync_folder_list_$$
            if [ "$DEBUG" == 'true' ]; then
               cat ${TMP}/sync_folder_list_$$
            fi
        else
            debug "${jobname}: Collecting lists - Local Files:"
            rm -f ${TMP}/sync_folder_list_$$_find_error
            find $basedir -maxdepth $scan_depth \! -type d | \
                ${SED} "s,${basedir}/,,"  >> ${TMP}/sync_folder_list_$$ 2>${TMP}/sync_folder_list_$$_find_error
            if [ $(cat ${TMP}/sync_folder_list_$$_find_error|wc -l) -gt 0 ]; then
                error "${jobname}: Find error detected" ${TMP}/sync_folder_list_$$_find_error
            fi
            if [ "$DEBUG" == 'true' ]; then
               cat ${TMP}/sync_folder_list_$$
            fi
        fi



        # Remove exclusions

        if [ "$exclude_file_flag" == "1" ]; then
            if [ -f "$exclude_file" ]; then
                # Fix up excludes
                while read line; do
                    echo "${basedir}/$line" >> ${TMP}/sync_folder_list_$$_exclude_list
                    debug "${jobname}: Excluding $line"
                    cat ${TMP}/sync_folder_list_$$ | \
                        ${GREP} -v "^${line}" > \
                        ${TMP}/sync_folder_list_$$_exclude
                    mv ${TMP}/sync_folder_list_$$_exclude ${TMP}/sync_folder_list_$$
                done < $exclude_file
                extra_options="$extra_options --exclude-from=${TMP}/sync_folder_list_$$_exclude_list"
            else
                warning "${jobname}: Exclusion file $exclude_file not found"
            fi
        fi        
 
        # Randomize the list to better spread the load across jobs 

        cat ${TMP}/sync_folder_list_$$ | ${SORT} -R > ${TMP}/sync_folder_list_$$_rand
        
       
        
#        echo "Check the folder list: ${TMP}/sync_folder_list_$$"
#        read pause

        x=0
        lines=`cat ${TMP}/sync_folder_list_$$_rand|wc -l`
        remainder=$(( $lines % $split_rsync_job_count ))
        if [ $remainder -eq 0 ]; then
            linesperjob=$(( $lines / $split_rsync_job_count ))
        else
            linesperjob=$(( $lines / $split_rsync_job_count + 1 ))
        fi

        while [ $x -lt $split_rsync_job_count ]; do
            skip=$(( $x * $linesperjob ))
            cat ${TMP}/sync_folder_list_$$_rand | \
                tail -n +${skip} | \
                head -n ${linesperjob} > ${TMP}/sync_folder_list_$$_${x}
                # sed "s,^,/," > ${TMP}/sync_folder_list_$$_${x}
            split_rsync "${TMP}/sync_folder_list_$$_${x}" &
            if [ $split_rsync_job_count -gt 5 ]; then
                # Stagger startup
                sleep 1
            fi
            x=$(( $x + 1 ))
        done

        # Wait for all jobs to complete
        complete=0
        while [ $complete -lt $split_rsync_job_count ]; do
            complete=`ls -1 ${TMP}/sync_folder_list_$$_*.complete 2>/dev/null|wc -l`
            sleep 2
        done

        # Clean missed deletes
     
        remove_missed_deletes

        # output stats

        output_stats "sync_folder_list_$$_" "$source_folder"

    fi # [ "$split_rsync_flag" != 1 ]

else # No snaphot folder found on the source path assuming this a BlueArc CNS tree (depricated)
    # We will assume there is a .snapshot folder in each subdir of the CNS tree
    debug "${jobname}: ${source_folder}/.snapshot not found, assuming CNS root"
    subfolders=`ls -1 ${source_folder}`

    joblog="${TMP}/sync_folder_$$_"
    
    for folder in $subfolders; do
        if [ "$cns_exclude_flag" == "1" ]; then
            cat $cns_exclude_file | ${GREP} -q -x "$folder" 
            if [ "$?" -eq "0" ]; then
                notice "${source_folder} Skiping CNS folder $folder"
                exclude_folder=0
            else
                notice "${source_folder} Syncing CNS folder $folder"
                exclude_folder=1
            fi
        else
            # We are not excluding CNS folders
            exclude_folder=1
        fi
    
        if [ -d ${source_folder}/$folder ] && [ $exclude_folder -ne 0 ]; then
            snapdir="${source_folder}/${folder}/.snapshot"
            # Below syntax captures output of 'locate_snap' function
            snap=`locate_snap "$snapdir" "$this_date" "daily"`
            # Check the return status of 'locate_snap'
            if [ $? -eq 0 ] ; then
                debug "Snapshot folder located: ${snapdir}/${snap}"
                snap_label="snap-daily_${snap}"
                basedir="${snapdir}/${snap}"
                # Run rsync
                debug "rsync -aS ${delete_on_target} --stats $progress --exclude=.snapshot $exclude_file_option $basedir/ ${target_folder}/${folder}"
                if [ "$trial_mode_flag" != "1" ]; then
                    ${RSYNC} -aS ${delete_on_target} --stats $progress --exclude=.snapshot $exclude_file_option \
                        $basedir/ $target_folder/${folder} &> ${TMP}/sync_folder_$$_${folder}.log

                    rsync_result=$?
                    if [ $rsync_result -ne 0 ]; then
                        error "${basedir} Job failed with error code $rsync_result" ${TMP}/sync_folder_$$_${folder}.log
                    else
                        notice "${source_folder} Finished syncing CNS folder $folder"
                        if [ -d ${target_folder}/${folder}/.zfs/snapshot ]; then
                            # This is a ZFS folder also and needs a snapshot
                            debug "zfs snapshot ${target_folder:1}/${folder}@${snap_label}"
                            zfs snapshot ${target_folder:1}/${folder}@${snap_label}
                            return=$?
                            if [ $return -ne 0 ]; then
                                error "${jobname}: ZFS Snapshot failed for ${target_folder:1}/${folder}@${snap_label} Error level: $return"
                            else
                                debug "ZFS Snapshot succeed."
                            fi
                        fi
                    fi
                fi
            else
                # If snapshot was not located, output the error message 
                warning "${jobname}: Snapshot not located: $snap"
            fi

            notice "${jobname} ===== Rsync complete for $basedir ====="
        
        fi
        
    done 

    # output stats

    output_stats "sync_folder_$$_"

    # clean up

    if [ "$DEBUG" != 'true' ]; then
        rm -f ${TMP}/sync_folder_list_$$ \
              ${TMP}/sync_folder_list_$$_rand \
              ${TMP}/sync_folder_list_$$_post_delete* \
              ${TMP}/sync_folder_$$_*.log \
              ${TMP}/sync_folder_$$_*.complete &>/dev/null
    fi

fi

# Capture snapshot
if [ -z "$remote_shell_value" ]; then
    # We are not pushing to remote host assume zfs snapshot to be taken here
    # Find the zfs folder in case we are not mounted to the same path
        zfsfolder=`mount|${GREP} "$target_folder on"|${AWK} -F " " '{print $3}'`
    debug "zfs snapshot ${zfsfolder}@${snap_label}"
    if [ -f /usr/sbin/zfs ]; then
        zfs list $zfsfolder &>/dev/null
        if [ $? -eq 0 ]; then
            if [ "$trial_mode_flag" != "1" ] && [ "$dry_run_flag" != "1" ]; then
                zfs snapshot ${zfsfolder}@${snap_label}
                return=$?
            fi
       
        
            if [ $return -ne 0 ]; then
                error "${jobname} ZFS Snapshot failed for ${zfsfolder}@${snap_label} Error level: $return"
            else
                debug "${jobname}: ZFS Snapshot succeed."
            fi
        else 
            warning "${jobname}: ZFS folder $zfsfolder not mounted.  Cannot snapshot."
        fi
    else
        notice "${jobname}: Not on running on a ZFS server. Snapshot skipped."
    fi 
fi

debug "${jobname}: === Job Complete ==="
exit 0
