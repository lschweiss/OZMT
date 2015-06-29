#! /bin/bash 

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
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
    echo "  [-t] trial mode.  Only output what would happen"
    echo "  [-p] Turn on --progress and --verbose for rsync."
    echo "  [-a] Turn on verbose and attach output to logs."
    echo "  [-s n] Split in to n rsync jobs. Incompatitble with CNS root folders."
    echo "  [-z n] scan n folders deep for split jobs"
    echo "  [-e options] remote shell program.  Passed directly as -e 'options' to rsync"
    echo "      [-i] SSH is incoming, defaults to outgoing"
    echo "  [-n name] job name.  Defaults to source folder."
    echo "  [-r] dry Run."
    echo
    exit 1
}

# Minimum number of arguments needed by this program
MIN_ARGS=2

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

xflag=
dflag=
Dflag=
tflag=
cflag=
kflag=
yflag=
sflag=
iflag=
rflag=
pflag=
aflag=
eflag=
lflag=
zflag=
nflag=
zval=1

progress=""

while getopts apkirtDc:x:d:s:e:z:l:n: opt; do
    case $opt in
        x)  # Exclude File Specified
            xflag=1
            xval="$OPTARG";;
        d)  # Date Specified
            dflag=1
            dval="$OPTARG";;
        c)  # CNS Exclude File Specified
            cflag=1
            cval="$OPTARG";;
        k)  # Use checksum comparison
            kflag=1;;
        a)  # Turn on verbose and attachements
            DEBUG=true
            aflag=1;;
        p)  # Turn on progress and verbose
            pflag=1;;
	D)  # Don't delete on the target
	    Dflag=1;;
        t)  # Trial mode
            debug "Using trial mode"
            tflag=1;;
        r)  # Dry Run
            debug "Doing a dry run of rsync"
            rflag=1;;
        s)  # Split rsync jobs
            sflag=1
            sval="$OPTARG"
            debug "Splitting into $sval jobs";;
        z)  # Scan depth for split jobs
            zflag=1
            zval="$OPTARG";;
        n)  # Job name
            nflag=1
            nval="$OPTARG";;
        e)  # Use remote shell
            eflag=1
            eval="$OPTARG";;
        i)  # Incoming via SSH (Source folder is via ssh)
            iflag=1;;
        l)  # Dereference symlinks
            lflag=1;;
        ?)  # Show program usage and exit
            show_usage
            exit 1;;
        :)  # Mandatory arguments not specified
            echo "Option -$OPTARG requires an argument."
            exit 1;;
    esac
done

# Exclude file parameter
if [ ! -z "$xflag" ]; then
    #echo "Option -x $xval specified"
    debug "Attempting to use given Exclude File"
    if [ -f $xval ]; then
        exclude_file="--exclude-from=${xval}"
        debug "Using Exclude File: $xval"
    else
        debug "Exclude file $xval not found!"
        exit 1
    fi
fi
# Date parameter
if [ ! -z "$dflag" ]; then
    #echo "Option -d $dval specified"
    debug "Attempting to use given snapshot date"
    this_date=$dval
    # Assume we are running interactively if a date is specified
    #pflag=1
else
    # Default to today's date
    debug "Defaulting to today's date"
    this_date=`${DATE} +%F`
fi
debug "Using Date: $this_date"

if [ ! -z "$pflag" ]; then
    progress="--verbose --progress"
fi

# Don't delete on target
if [ ! -z $Dflag ]; then
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
    if [ "$iflag" == "1" ]; then
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
    if [ ! -z "$eflag" ]; then
        debug "Assuming remote target folder $2 exists.  Cannot check from here."
        target_folder=$2
    else
        error "${jobname} Target folder $2 does not exist!"
        exit 1
    fi
fi

if [ "$rflag" == "1" ]; then
    extra_options="--dry-run"
else
    extra_options="$progress"
fi

if [ "$aflag" == "1" ]; then
    debug "Using verbose and attaching logs"
    extra_options="${extra_options} -v"
fi

if [ ! -z "$eflag" ]; then
    debug "Using remote shell: $eval"
    extra_options="${extra_options} -e ${eval}"
fi

if [ ! -z "$lflag" ]; then
    debug "Dereferencing symlinks"
    extra_options="${extra_options} --copy-links"
fi

if [ ! -z "$kflag" ]; then
    debug "Using checksum file comparison"
    extra_options="${extra_options} --checksum"
fi

if [ ! -x "$nflag" ]; then
    debug "Setting job name to $nval"
    jobname="$nval"
else
    debug "Setting job name to $source_folder"
    jobnaem="$source_folder"
fi



####
#
# Split rsync function
#
###


split_rsync () {

    local rsync_result=-1
    local try=0

    if [ "$iflag" == "1" ]; then
        local basedir="${source_host}:${snapdir}/${snap}"
    else
        local basedir="${snapdir}/${snap}"
    fi

    # Function used to run a parallel rsync job
    debug "${RSYNC} -arS ${delete_on_target} --relative \
            --stats $extra_options --exclude=.history --exclude=.snapshot \
            --files-from=${1} $basedir/ $target_folder"
    if [ "$tflag" != 1 ]; then
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

            if [ "$aflag" == "1" ]; then
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
    if [ -z "$eflag" ]; then
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
                this_num_files=`cat ${TMP}/$log | ${SED} 's/,//g' | ${GREP} "Number of files:" | ${AWK} -F ": " '{print $2}'`
                if echo "$this_num_files"|grep -q "reg"; then
                    this_num_files=`echo "$this_num_files"|awk -F " " '{print $1}'`
                fi
                this_num_files_trans=`cat ${TMP}/$log | ${SED} 's/,//g' | ${GREP} "Number of files transferred:" | ${AWK} -F ": " '{print $2}'`
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



if [[ "$iflag" == "1" || -d "${source_folder}/.snapshot" || -d "${source_folder}/.zfs/snapshot" ]]; then
    if [ "$iflag" == "1" ]; then
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
    
    if [ "$sflag" != "1" ]; then
        if [ "$iflag" == "1" ]; then
            basedir="${source_host}:${snapdir}/${snap}"
        else
            basedir="${snapdir}/${snap}"
        fi
        # Run rsync
        debug "rsync -aS ${delete_on_target} --stats $extra_options --exclude=.snapshot $exclude_file $basedir/ $target_folder"
        if [ "$tflag" != "1" ]; then
            echo "rsync -aS ${delete_on_target} --stats $extra_options --exclude=.snapshot $exclude_file \
                $basedir/ $target_folder" > ${TMP}/sync_snap_folder_$$.log
            ${RSYNC} -aS ${delete_on_target} --stats $extra_options --exclude=.snapshot $exclude_file \
                $basedir/ $target_folder &>> ${TMP}/sync_snap_folder_$$.log
            rsync_result=$?

            if [ $rsync_result -eq 23 ]; then
                # Check if rsync failed to delete empty directories
                remove_empty_dirs ${TMP}/sync_snap_folder_$$.log $target_folder
            fi

            if [ $rsync_result -ne 0 ]; then
                error "${basedir} Job failed with error code $rsync_result" ${TMP}/sync_snap_folder_$$.log
            fi
            if [ "$aflag" == "1" ]; then
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
    
        notice "${jobname}: Splitting into $sval rsync job(s), scan depth $zval"

        basedir="${snapdir}/${snap}"

        # Collect lists
        debug "${jobname}: Collecting lists - Directories:"
        if [ "$iflag" == "1" ]; then
            ssh $source_host find $basedir -mindepth $zval -maxdepth $zval -type d | \
                ${GREP} -x -v ".snapshot" | \
		${GREP} -x -v ".zfs" | \
		${GREP} -v ".history" | \
		${SED} "s,${basedir}/,," > \ 
		${TMP}/sync_folder_list_$$
        else
            find $basedir -mindepth $zval -maxdepth $zval -type d | \
                ${GREP} -x -v ".snapshot" | \
		${GREP} -x -v ".zfs" | \
		${GREP} -v ".history" | \
		${SED} "s,${basedir}/,," > \
		${TMP}/sync_folder_list_$$
        fi

        # Add files that may be at a depth less than or equal to the test above
        debug "${jobname}: Collecting lists - Files:"

        if [ "$iflag" == "1" ]; then
            ssh $source_host find $basedir -maxdepth $zval \! -type d | \
                ${SED} "s,${basedir}/,,"  >> ${TMP}/sync_folder_list_$$
        else
            find $basedir -maxdepth $zval \! -type d | \
                ${SED} "s,${basedir}/,,"  >> ${TMP}/sync_folder_list_$$
        fi

        # Strip the basedir from each line  sed "s,${basedir}/,," sed 's,$,/,' sed 's,^,+ ,'
#	debug "${jobname}: Collecting lists - Trimming base directory:"
#        cat ${TMP}/sync_folder_list_$$ | ${SED} "s,${basedir}/,," | ${SED} 's,$,/,' > ${TMP}/sync_folder_list_$$_trim

        # Remove exclusions

        if [ "$xflag" == "1" ]; then
            if [ -f "$xval" ]; then
                # Fix up excludes
                while read line; do
                    echo "${basedir}/$line" >> ${TMP}/sync_folder_list_$$_exclude_list
                    debug "${jobname}: Excluding $line"
                    cat ${TMP}/sync_folder_list_$$ | \
			${GREP} -v "^${line}" > \
                        ${TMP}/sync_folder_list_$$_exclude
                    mv ${TMP}/sync_folder_list_$$_exclude ${TMP}/sync_folder_list_$$
                done < $xval
                extra_options="$extra_options --exclude-from=${TMP}/sync_folder_list_$$_exclude_list"
            else
                warning "${jobname}: Exclusion file $xval not found"
            fi
        fi        
 
        # Randomize the list to better spread the load across jobs 

        cat ${TMP}/sync_folder_list_$$ | sort -R > ${TMP}/sync_folder_list_$$_rand
        
       
        
#        echo "Check the folder list: ${TMP}/sync_folder_list_$$"
#        read pause

        x=0
        lines=`cat ${TMP}/sync_folder_list_$$_rand|wc -l`
        remainder=$(( $lines % $sval ))
        if [ $remainder -eq 0 ]; then
            linesperjob=$(( $lines / $sval ))
        else
            linesperjob=$(( $lines / $sval + 1 ))
        fi

        while [ $x -lt $sval ]; do
            skip=$(( $x * $linesperjob ))
            cat ${TMP}/sync_folder_list_$$_rand | \
		tail -n +${skip} | \
		head -n ${linesperjob} > ${TMP}/sync_folder_list_$$_${x}
                # sed "s,^,/," > ${TMP}/sync_folder_list_$$_${x}
            split_rsync "${TMP}/sync_folder_list_$$_${x}" &
            if [ $sval -gt 5 ]; then
                # Stagger startup
                sleep 1
            fi
            x=$(( $x + 1 ))
        done

        # Wait for all jobs to complete
        complete=0
        while [ $complete -lt $sval ]; do
            complete=`ls -1 ${TMP}/sync_folder_list_$$_*.complete 2>/dev/null|wc -l`
            sleep 2
        done

        # output stats

        output_stats "sync_folder_list_$$_" "$source_folder"

    fi # [ "$sflag" != 1 ]

else
    # We will assume there is a .snapshot folder in each subdir of the CNS tree
    debug "${jobname}: ${source_folder}/.snapshot not found, assuming CNS root"
    subfolders=`ls -1 ${source_folder}`

    joblog="${TMP}/sync_folder_$$_"
    
    for folder in $subfolders; do
        if [ "$cflag" == "1" ]; then
            cat $cval | ${GREP} -q -x "$folder" 
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
                debug "rsync -aS ${delete_on_target} --stats $progress --exclude=.snapshot $exclude_file $basedir/ ${target_folder}/${folder}"
                if [ "$tflag" != "1" ]; then
                    ${RSYNC} -aS ${delete_on_target} --stats $progress --exclude=.snapshot $exclude_file \
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

    rm -f ${TMP}/sync_folder_list_$$ \
          ${TMP}/sync_folder_list_$$_rand \
          ${TMP}/sync_folder_$$_*.log \
          ${TMP}/sync_folder_$$_*.complete &>/dev/null

fi

# Capture snapshot
if [ -z "$eval" ]; then
    # We are not pushing to remote host assume zfs snapshot to be taken here
    # Find the zfs folder in case we are not mounted to the same path
        zfsfolder=`mount|${GREP} "$target_folder on"|${AWK} -F " " '{print $3}'`
    debug "zfs snapshot ${zfsfolder}@${snap_label}"
    if [ -f /usr/sbin/zfs ]; then
        zfs list $zfsfolder &>/dev/null
        if [ $? -eq 0 ]; then
            if [ "$tflag" != "1" ] && [ "$rflag" != "1" ]; then
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
