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
    echo "  [-t] trial mode.  Only output what would happen"
    echo "  [-p] Turn on --progress and --verbose for rsync."
    echo "  [-s n] Split in to n rsync jobs. Incompatitble with CNS root folders."
    echo "  [-z n] scan n folders deep for split jobs"
    echo "  [-e options] remote shell program.  Passed directly as -e 'options' to rsync"
    echo "  [-r] dry Run."
    echo
    exit 1
}

_DEBUG="on"
function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

# Minimum number of arguments needed by this program
MIN_ARGS=2

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

xflag=
dflag=
tflag=
cflag=
kflag=
yflag=
sflag=
rflag=
pflag=
eflag=
lflag=
zflag=
zval=1

progress=""

while getopts pkrtc:x:d:s:e:z:l: opt; do
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
        p)  # Turn on progress and verbose
            pflag=1;;
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
        e)  # Use remote shell
            eflag=1
            eval="$OPTARG";;
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
    date=$dval
    # Assume we are running interactively if a date is specified
    #pflag=1
else
    # Default to today's date
    debug "Defaulting to today's date"
    date=`date +%F`
fi
debug "Using Date: $date"

if [ ! -z "$pflag" ]; then
    progress="--verbose --progress"
fi

#Move to remaining arguments
shift $(($OPTIND - 1))
#echo "Remaining arguments are: $*"

# Source folder parameter
if [ -d $1 ]; then
    source_folder=$1
else
    error "Source folder $1 does not exist!"
    exit 1
fi

# Target folder parameter
if [ -d $2 ]; then
    target_folder=$2
else
    if [ ! -z "$eflag" ]; then
        debug "Assuming remote target folder $2 exists.  Cannot check from here."
        target_folder=$2
    else
        error "Target folder $2 does not exist!"
        exit 1
    fi
fi

if [ "$rflag" == "1" ]; then
    extra_options="--dry-run"
else
    extra_options="$progress"
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

####
#
# Conversions
#
####

tobytes () {
    awk '{ ex = index("KMG", substr($1, length($1)))
           val = substr($1, 0, length($1))
           prod = val * 10^(ex * 3)
           sum += prod
         }   
         END {print sum}'
}

bytestohuman () {
    if [ $1 -gt 1099511627776 ]; then
        echo -n $(echo "scale=3;$1/1099511627776"|bc)TiB
        return 
    fi

    if [ $1 -gt 1073741824 ]; then
        echo -n $(echo "scale=3;$1/1073741824"|bc)GiB
        return
    fi

    if [ $1 -gt 1048576 ]; then
        echo -n $(echo "scale=3;$1/1048576"|bc)MiB
        return
    fi

    if [ $1 -gt 1024 ]; then
        echo -n $(echo "scale=3;$1/1024"|bc)KiB
        return
    fi

    echo "$1 bytes"
        
}



####
#
# Split rsync function
#
###


split_rsync () {

    local rsync_result=-1
    local try=0

    # Function used to run a parallel rsync job
    debug "time rsync -arS --delete --relative \
            --stats $extra_options --exclude=.history --exclude=.snapshot \
            --files-from=${1} $basedir/ $target_folder"
    if [ "$tflag" != 1 ]; then
        while [ $rsync_result -ne 0 ]; do
            /usr/bin/time -v -o ${1}.time rsync -arS --delete --relative  \
                --stats $extra_options --exclude=.history --exclude=.snapshot \
                --files-from=${1} $basedir/ $target_folder &> ${1}.log 
	    rsync_result=$? 
            
            # cat ${1}.log | sed "s,^,${1}: ," 
            # cat ${1}.time | sed "s,^,${1}: ,"
            try=$(( try + 1 ))
            if [ $rsync_result -ne 0 ]; then
                notice "${source_folder} Job failed with error code $rsync_result"
                if [ $try -eq 3 ]; then
                    error "${source_folder} Job for $1 failed 3 times. Giving up.  List saved as in /tmp/failed_$$ "
                    cat $1 >> /tmp/failed_$$
                    break;
                else
                    notice "${source_folder} Job for $1 failed.  Will try up to 3 times."
                fi
            fi

        done
    fi

    touch ${1}.complete
}

####
#
# Output stats
#
####

output_stats () {

        # Collect stats

        # DEBUG set -x
    
        local x=0
        local num_files=0
        local num_files_trans=0
        local total_file_size=0
        local total_transfered_size=0

        local log_name="$1"
        local log_prefix="$2"


        for log in ${log_name}*.log ; do
            this_num_files=`cat $log | grep "Number of files:" | awk -F ": " '{print $2}'`
            this_num_files_trans=`cat $log | grep "Number of files transferred:" | awk -F ": " '{print $2}'`
            this_total_file_size=`cat $log | grep "Total file size:" | awk -F " " '{print $4}'` 
            this_total_transfered_size=`cat $log | grep "Total transferred file size:" | awk -F " " '{print $5}'`
            # Add to totals
            let "num_files = $num_files + $this_num_files"
            let "num_files_trans = $num_files_trans + $this_num_files_trans"
            let "total_file_size = $total_file_size + $this_total_file_size"
            let "total_transfered_size = $total_transfered_size + $this_total_transfered_size"  
            x=$(( $x + 1 ))
        done

       
        # Output totals

        notice "${log_prefix} ****************************************"
        notice "${log_prefix} ** Rsync Totals                       **"
        notice "${log_prefix} ****************************************"
        notice "${log_prefix} Number of files: $num_files"
        notice "${log_prefix} Number of files transfered: $num_files_trans"
        notice "${log_prefix} Total_file_size: $(bytestohuman $total_file_size)"
        notice "${log_prefix} Total Transfered size: $(bytestohuman $total_transfered_size)"
        
        # DEBUG set +x
        
} # output_stats



if [ -d "${source_folder}/.snapshot" ]; then
    debug "${source_folder}/.snapshot found."
    snapdir="${source_folder}/.snapshot"
    # Below syntax captures output of 'locate_snap' function
    snap=`locate_snap "$snapdir" "$date"`
    # Check the return status of 'locate_snap'
    if [ $? -eq 0 ] ; then
        debug "Snapshot folder located: $snap"
        snap_label="snap-daily_${snap}"
    else
        # If snapshot was not located, output the error message and exit
        error $snap
        exit 1
    fi

    notice "${source_folder} Starting rsync job(s)"

    basedir="${snapdir}/${snap}"

    joblog="/tmp/sync_folder_$$.log"
    
    if [ "$sflag" != "1" ]; then
        # Run rsync
        debug "rsync -aS --delete --stats $extra_options --exclude=.snapshot $exclude_file $basedir/ $target_folder"
        if [ "$tflag" != "1" ]; then
            rsync -aS --delete --stats $extra_options --exclude=.snapshot $exclude_file \
                $basedir/ $target_folder &> /temp/sync_snap_folder_$$.log
            rsync_result=$?
            if [ $rsync_result -ne 0 ]; then
                error "${basedir} Job failed with error code $rsync_result"
            fi
            output_stats "/temp/sync_snap_folder_$$" "$source_folder"
        fi
    else
        # Split rsync

        # Collect lists
        debug "Collecting lists.  Part 1:"
        find $basedir -mindepth $zval -maxdepth $zval -type d | \
            grep -x -v ".snapshot"|grep -x -v ".zfs"|grep -v ".history" > /tmp/sync_folder_list_$$
        # Sript the basedir from each line  sed "s,${basedir}/,," sed 's,$,/,' sed 's,^,+ ,'
        cat /tmp/sync_folder_list_$$ | sed "s,${basedir}/,," | sed 's,$,/,' > /tmp/sync_folder_list_$$_trim
        # Add files that may be at a depth less than or equal to the test above
        debug "Collecting lists.  Part 2:"
        find $basedir -maxdepth $zval -type f | \
            sed "s,${basedir},,"  >> /tmp/sync_folder_list_$$_trim
            
        # Randomize the list to spread across jobs better

        cat /tmp/sync_folder_list_$$_trim | sort -R > /tmp/sync_folder_list_$$_rand
        
       
        # TODO: Remove excluded folders/files  Note: move the .histroy exclusion from above. 
        
#        echo "Check the folder list: /tmp/sync_folder_list_$$_trim"
#        read pause

        x=0
        lines=`cat /tmp/sync_folder_list_$$_rand|wc -l`
        remainder=$(( $lines % $sval ))
        if [ $remainder -eq 0 ]; then
            linesperjob=$(( $lines / $sval ))
        else
            linesperjob=$(( $lines / $sval + 1 ))
        fi

        while [ $x -lt $sval ]; do
            skip=$(( $x * $linesperjob ))
            cat /tmp/sync_folder_list_$$_rand | tail -n +${skip} | head -n ${linesperjob} > /tmp/sync_folder_list_$$_${x}
                # sed "s,^,/," > /tmp/sync_folder_list_$$_${x}
            split_rsync "/tmp/sync_folder_list_$$_${x}" &
            if [ $sval -gt 5 ]; then
                # Stagger startup
                sleep 1
            fi
            x=$(( $x + 1 ))
        done

        # Wait for all jobs to complete
        complete=0
        while [ $complete -lt $sval ]; do
            complete=`ls -1 /tmp/sync_folder_list_$$_*.complete 2>/dev/null|wc -l`
            sleep 2
        done

        # output stats

        output_stats "/tmp/sync_folder_list_$$_" "$source_folder"

        # clean up temp files

        if [ "$tflag" != "1" ]; then
            rm -f /tmp/sync_folder_list_$$_*
        fi

    fi # [ "$sflag" != 1 ]

else
    # We will assume there is a .snapshot folder in each subdir of the CNS tree
    notice "${source_folder}/.snapshot not found, assuming CNS root"
    subfolders=`ls -1 ${source_folder}`

    joblog="/tmp/sync_folder_$$_"
    
    for folder in $subfolders; do
        if [ "$cflag" == "1" ]; then
            cat $cval | grep -q -x "$folder" 
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
            snap=`locate_snap "$snapdir" "$date"`
            # Check the return status of 'locate_snap'
            if [ $? -eq 0 ] ; then
                debug "Snapshot folder located: ${snapdir}/${snap}"
                snap_label="snap-daily_${snap}"
                basedir="${snapdir}/${snap}"
                # Run rsync
                debug "rsync -aS --delete --stats $progress --exclude=.snapshot $exclude_file $basedir/ ${target_folder}/${folder}"
                if [ "$tflag" != "1" ]; then
                    rsync -aS --delete --stats $progress --exclude=.snapshot $exclude_file \
                        $basedir/ $target_folder/${folder} &> /temp/sync_snap_folder_$$_${folder}.log

                    rsync_result=$?
                    if [ $rsync_result -ne 0 ]; then
                        error "${basedir} Job failed with error code $rsync_result"
                    else
                        notice "${source_folder} Finished syncing CNS folder $folder"
                        if [ -d ${target_folder}/${folder}/.zfs/snapshot ]; then
                            # This is a ZFS folder also and needs a snapshot
                            debug "zfs snapshot ${target_folder:1}/${folder}@${snap_label}"
                            zfs snapshot ${target_folder:1}/${folder}@${snap_label}
                            return=$?
                            if [ $return -ne 0 ]; then
                                error "${source_folder} ZFS Snapshot failed for ${target_folder:1}/${folder}@${snap_label} Error level: $return"
                            else
                                debug "ZFS Snapshot succeed."
                            fi
                        fi
                    fi
                fi
            else
                # If snapshot was not located, output the error message 
                warning "Snapshot not located: $snap"
            fi
        
        fi
        notice "${source_folder} ===== Rsync complete for $basedir ====="
        
    done    

    # output stats

    output_stats "/temp/sync_snap_folder_$$_" "$source_folder"

fi

# Capture snapshot
if [ -z "$eval" ]; then
    #We are not pushing to remote host assume zfs snapshot to be taken here
    # Find the zfs folder in case we are not mounted to the same path
        zfsfolder=`mount|grep "$target_folder on"|awk -F " " '{print $3}'`
    debug "zfs snapshot ${zfsfolder}@${snap_label}"
    if [ "$tflag" != "1" ] && [ "$rflag" != "1" ]; then
        zfs snapshot ${zfsfolder}@${snap_label}
        return=$?
    fi
    
    if [ $return -ne 0 ]; then
        error "${source_folder} ZFS Snapshot failed for ${zfsfolder}@${snap_label} Error level: $return"
    else
        debug "ZFS Snapshot succeed."
    fi
fi

debug "=== Job Complete ==="
exit 0
