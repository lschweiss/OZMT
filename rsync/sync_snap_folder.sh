#! /bin/bash 

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

. $HOME/.profile

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
    echo "  [-t] trial mode.  Only output what would happen"
    echo "  [-p] Turn on --progress and --verbose for rsync."
    echo "  [-s n] Split in to n rsync jobs. Incompatitble with CNS root folders."
    echo "  [-z n] scan n folders deep for split jobs"
    echo "  [-e options] remote shell program.  Passed directly as -e 'options' to rsync"
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
tflag=
cflag=
sflag=
rflag=
pflag=
eflag=
lflag=
zflag=
zval=1

progress=""

while getopts prtc:x:d:s:e:z:l: opt; do
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
        p)  # Turn on progress and verbose
            pflag=1;;
        t)  # Trial mode
            echo "Using trial mode"
            tflag=1;;
        r)  # Dry Run
            echo "Doing a dry run of rsync"
            rflag=1;;
        s)  # Split rsync jobs
            sflag=1
            sval="$OPTARG"
            echo "Splitting into $sval jobs";;
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
    echo "Attempting to use given Exclude File"
    if [ -f $xval ]; then
        exclude_file="--exclude-from=${xval}"
        echo "Using Exclude File: $xval"
    else
        echo "Exclude file $xval not found!"
        exit 1
    fi
fi
# Date parameter
if [ ! -z "$dflag" ]; then
    #echo "Option -d $dval specified"
    echo "Attempting to use given snapshot date"
    date=$dval
    # Assume we are running interactively if a date is specified
    #pflag=1
else
    # Default to today's date
    echo "Defaulting to today's date"
    date=`date +%F`
fi
echo "Using Date: $date"

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
    echo "Source folder $1 does not exist!"
    exit 1
fi

# Target folder parameter
if [ -d $2 ]; then
    target_folder=$2
else
    if [ ! -z "$eflag" ]; then
        echo "Assuming remote target folder $2 exists.  Cannot check from here."
        target_folder=$2
    else
        echo "Target folder $2 does not exist!"
        exit 1
    fi
fi

split_rsync () {
    # Function used to run a parallel rsync job
    echo "time rsync -aS --delete --relative -r -h \
            --stats $extra_options --exclude=.history --exclude=.snapshot \
            --files-from=${1} $basedir/ $target_folder"
    if [ "$tflag" != 1 ]; then
        /usr/bin/time -p rsync -aS --delete --relative -r -h \
            --stats $extra_options --exclude=.history --exclude=.snapshot \
            --files-from=${1} $basedir/ $target_folder 2> ${1}.time | tee ${1}.log | sed "s,^,${1}: ," 
        cat ${1}.time | sed "s,^,${1}: ,"
    fi

    touch ${1}.complete
}

if [ "$rflag" == "1" ]; then
    extra_options="--verbose --progress --dry-run"
else
    extra_options="$progress"
fi

if [ ! -z "$eflag" ]; then
    echo "Using remote shell: $eval"
    extra_options="${extra_options} -e ${eval}"
fi

if [ ! -z "$lflag" ]; then
    echo "Dereferencing symlinks"
    extra_options="${extra_options} --copy-links"
fi

if [ -d "${source_folder}/.snapshot" ]; then
    echo "${source_folder}/.snapshot found."
    snapdir="${source_folder}/.snapshot"
    # Below syntax captures output of 'locate_snap' function
    snap=`locate_snap "$snapdir" "$date"`
    # Check the return status of 'locate_snap'
    if [ $? -eq 0 ] ; then
        echo "Snapshot folder located: $snap"
        snap_label="snap-daily_${snap}"
    else
        # If snapshot was not located, output the error message and exit
        echo $snap
        exit 1
    fi

    basedir="${snapdir}/${snap}"
    
    if [ "$sflag" != "1" ]; then
        # Run rsync
        echo "time rsync -aS -h --delete --stats $extra_options --exclude=.snapshot $exclude_file $basedir/ $target_folder"
        if [ "$tflag" != "1" ]; then
            /usr/bin/time rsync -aS -h --delete --stats $extra_options --exclude=.snapshot $exclude_file $basedir/ $target_folder
        fi
    else
        # Split rsync

        # Collect lists
        echo "Collecting lists.  Part 1:"
        /usr/bin/time find $basedir -mindepth $zval -maxdepth $zval -type d | \
            grep -x -v ".snapshot"|grep -x -v ".zfs"|grep -v ".history" > /tmp/sync_folder_list_$$
        # Sript the basedir from each line  sed "s,${basedir}/,," sed 's,$,/,' sed 's,^,+ ,'
        cat /tmp/sync_folder_list_$$ | sed "s,${basedir}/,," | sed 's,$,/,' > /tmp/sync_folder_list_$$_trim
        # Add files that may be at a depth less than or equal to the test above
        echo "Collecting lists.  Part 2:"
        /usr/bin/time find $basedir -maxdepth $zval -type f | \
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
                sleep 5
            fi
            x=$(( $x + 1 ))
        done

        # Wait for all jobs to complete
        complete=0
        while [ $complete -lt $sval ]; do
            complete=`ls -1 /tmp/sync_folder_list_$$_*.complete 2>/dev/null|wc -l`
            sleep 2
        done

        if [ "$tflag" != "1" ]; then
            rm -f /tmp/sync_folder_list_$$_*
        fi

    fi # [ "$sflag" != 1 ]

else
    # We will assume there is a .snapshot folder in each subdir of the CNS tree
    echo "${source_folder}/.snapshot not found, assuming CNS root"
    subfolders=`ls -1 ${source_folder}`
    
    for folder in $subfolders; do
    if [ "$cflag" == "1" ]; then
        cat $cval | grep -q -x "$folder" 
        if [ "$?" -eq "0" ]; then
            echo "Skiping CNS folder $folder"
            exclude_folder=0
        else
            echo "Syncing CNS folder $folder"
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
            echo "Snapshot folder located: ${snapdir}/${snap}"
            snap_label="snap-daily_${snap}"
            basedir="${snapdir}/${snap}"
            # Run rsync
            echo "time rsync -a -h --delete --stats $progress --exclude=.snapshot $exclude_file $basedir/ ${target_folder}/${folder}"
        if [ "$tflag" != "1" ]; then
            /usr/bin/time rsync -a -h --delete --stats $progress --exclude=.snapshot $exclude_file $basedir/ $target_folder/${folder}
            if [ -d ${target_folder}/${folder}/.zfs/snapshot ]; then
                # This is a ZFS folder also and needs a snapshot
                echo zfs snapshot ${target_folder:1}/${folder}@${snap_label}
                zfs snapshot ${target_folder:1}/${folder}@${snap_label}
                return=$?
                if [ $return -ne 0 ]; then
                    echo "ZFS Snapshot failed: $return"
                else
                    echo "ZFS Snapshot succeed."
                fi
            fi
        fi
        else
            # If snapshot was not located, output the error message 
            echo $snap
        fi
    
    fi
    echo "==========================================="
    echo
    done    

fi

# Capture snapshot
if [ -z "$eval" ]; then
    #We are not pushing to remote host assume zfs snapshot to be taken here
    # Find the zfs folder in case we are not mounted to the same path
        zfsfolder=`mount|grep "$target_folder on"|awk -F " " '{print $3}'`
    echo "zfs snapshot ${zfsfolder}@${snap_label}"
    if [ "$tflag" != "1" ] && [ "$rflag" != "1" ]; then
        zfs snapshot ${zfsfolder}@${snap_label}
        return=$?
    fi
    
    if [ $return -ne 0 ]; then
        echo "ZFS Snapshot failed: $return"
    else
        echo "ZFS Snapshot succeed."
    fi
fi

echo "==========================================="
exit 0
