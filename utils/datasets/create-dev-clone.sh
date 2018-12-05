#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2017  Chip Schweiss

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

. /opt/ozmt/zfs-tools-init.sh

logfile="$default_logfile"

logging_level="0"

report_name="$default_report_name"

now=`${DATE} +"%F %H:%M:%S%z"`

pools="$(pools)"

myTMP="${TMP}/datasets"
MKDIR $myTMP

DEBUG='true'

paused='false'


# show function usage
show_usage() {
    echo
    echo "Usage: $0 -d {dataset_name} -n {instance_name} -s {snapname} [-i {dev_ip} ] [-q {quota}] [-p {pause_tag}] [-t]"
    echo
}

while getopts d:n:s:q:i:p:t opt; do
    case $opt in
        d)  # Dataset name
            clone_dataset="$OPTARG"
            debug "dataset name: $clone_dataset"
            ;;
        n)  # Dev name
            dev_name="$OPTARG"
            debug "instance_name: $dev_name"
            ;;
        s)  # Snapshot name / type
            snap_name="$OPTARG"
            debug "snap name: $snap_name"
            ;;
        q)  # Clone quota
            clone_quota="$OPTARG"
            debug "clone quota: $clone_quota"
            ;;
        i)  # IP address of instance
            dev_ip="$OPTARG"
            debug "Instance IP: $dev_ip"
            ;;
        p)  # Leave replication paused
            pause="$OPTARG"
            debug "Leave replication paused.  Using tag $OPTARG"
            ;;
        t)  # Test mode
            test='true'
            debug "Running in test mode"
            ;;
        ?)  # Show program usage and exit
            show_usage
            exit 0
            ;;
        :)  # Mandatory arguments not specified
            die "${job_name}: Option -$OPTARG requires an argument." 1
            ;;
    esac
done

declare -A o_source
declare -A o_paused

if [ "$pause" == '' ]; then
    pause="$$"
fi

die () {
    unset IFS
    if [ "$paused" == 'true' ]; then
        for ozmt_dataset in $ozmt_datasets; do
            this_source="${o_source[$ozmt_dataset]}"
            o_pool=`echo $this_source | $CUT -d ':' -f 1`
            debug "Releasing pause on $ozmt_dataset on pool $o_pool"
            $SSH $o_pool /opt/ozmt/replication/replication-state.sh -d $ozmt_dataset -s unpause -i $pause
        done
    fi

    rm -f ${myTMP}/dataset*_$$

    if [ $2 -ne 0 ]; then
        if [ "$1" != '' ]; then
            error "$1"
        fi
    else
        notice "$1"
    fi

    exit $2
}

find_snap () {

    local zfs_folder="$1"
    local snap="$2"
    local pool=`echo $zfs_folder | $CUT -d '/' -f 1`
    local folder=`echo $zfs_folder | $CUT -d '/' -f 2`
    
    $SSH $pool zfs list -t snapshot ${zfs_folder}@${snap} 1>/dev/null 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "$snap"
        return 0
    else
        $SSH $pool zfs list -H -o name -t snapshot -d 1 ${zfs_folder} | \
            $GREP "^${zfs_folder}@${snap}_" | $SORT -r | $HEAD -1 | $CUT -d '@' -f 2
        return $?
    fi
}

process_reparse () {

    local origin_path="$2"
    local clone_path="$3"
    local clone_dataset="$4"
    local link_path=
    local link_target=
    local link_name=
    local link_target_dataset=
    local target_link=
    local target_target=
    local o_pool=
    local this_source=
    local o_folder=

    local target_script="${myTMP}/dataset_reparse_run_$$"

    while IFS=$(echo -e '\t\n') read -r link_path link_target; do
        unset IFS

        link_name=`basename $link_path`
        # Strip origin
        link_path="${link_path:$(( ${#origin_path} + 1 ))}"
        link_target_dataset=`echo $link_target | $AWK -F '/' '{print $2}'`
        

        target_link="${clone_path}/${link_path}"
        target_target="zfs-${link_target_dataset}:/${link_target_dataset}/dev/${dev_name}/${clone_folder}/${link_path}"
        

        # Replace reparse point        
        echo "rm $target_link" >> $target_script
        echo "nfsref add ${target_link} ${target_target}" >> $target_script

        IFS=$(echo -e '\t\n')
    done < "$1"
    unset IFS

    this_source="${o_source["$ozmt_dataset"]}"
            o_pool=`echo $this_source | $CUT -d ':' -f 1`
            o_folder=`echo $this_source | $CUT -d ':' -f 2`
    
    # Execute reparse fix-up
    if [ -f ${target_script} ]; then
        #cat $target_script
        if [ "$test" != 'true' ]; then
            $SSH $o_pool "bash -s " < ${target_script}
        else
            echo "TEST MODE.  Would run:"
            echo "$o_pool "bash -s " < ${target_script}"
        fi
    fi
    
    rm -f $target_script
 
}

# Locate dataset info
clone_pool=
debug "Finding dataset source for $clone_dataset"
dataset_source=`dataset_source $clone_dataset`
o_source["${clone_dataset}"]="$dataset_source"
if [ "$dataset_source" == '' ]; then
    error "Cannot locate source for $clone_dataset"
    die "Cannot locate source for $clone_dataset" 1
fi
debug "Found source at $dataset_source"
clone_pool=`echo $dataset_source | $CUT -d ':' -f 1`

# Check if clone already exists

$SSH ${clone_pool} zfs list ${clone_pool}/${clone_dataset}/dev/${dev_name}  1>/dev/null 2>/dev/null
if [ $? -eq 0 ]; then
    error "Clone already exists for $dev_name"
    die "Cannot locate source for $clone_dataset" 1
else
    debug "Safe to create ${clone_pool}/dev/${dev_name}"
fi

# TODO: Check if clones exist in all additional folders and datasets



##
# Create the clone(s)
##

# Collect folders
rm -f ${myTMP}/dataset_folders_$$
folders=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:folders ${clone_pool}/${clone_dataset}` 
if [ "$folders" != ' - ' ]; then
    NUM=1
    while [ $NUM -le $folders ]; do
        $SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:folder:${NUM} ${clone_pool}/${clone_dataset} 2>/dev/null  >>${myTMP}/dataset_folders_$$
        NUM=$(( NUM + 1 ))
    done
fi

debug "Cloning the following folders: $(cat ${myTMP}/dataset_folders_$$)"

snap=`find_snap "${clone_pool}/${clone_dataset}" "$snap_name"`
if [ "$snap" == '' ]; then
    error "Could not find snapshot: $snap_name"
    die "Cannot locate source for $clone_dataset" 1
else
    debug "Found snapshot $snap"
fi

rm -f ${myTMP}/dataset_datasets_$$
datasets=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:datasets ${clone_pool}/${clone_dataset}`
if [ "$datasets" != ' - ' ]; then
    NUM=1
    while [ $NUM -le $datasets ]; do
        $SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:dataset:${NUM} ${clone_pool}/${clone_dataset} 2>/dev/null >>${myTMP}/dataset_datasets_$$
        NUM=$(( NUM + 1 ))
    done
fi

ozmt_datasets=`cat ${myTMP}/dataset_datasets_$$ 2>/dev/null`


##
# Locate and pause all related datasets
##

source clone-functions.sh

##           
# Create clones
##

if [ "$ozmt_datasets" != '' ]; then
    # Create stub clones
    for ozmt_dataset in $ozmt_datasets; do
        this_source="${o_source[$ozmt_dataset]}"
        o_pool=`echo $this_source | $CUT -d ':' -f 1`
        o_folder=`echo $this_source | $CUT -d ':' -f 2`
        # Clone it
        notice "Creating stub ${o_pool}/${o_folder}/dev/${dev_name} from ${o_pool}/${o_folder}@${snap}"
        if [ "$test" != 'true' ]; then
            $SSH $o_pool zfs clone ${o_pool}/${o_folder}@${snap} ${o_pool}/${o_folder}/dev/${dev_name}
            if [ "$clone_quota" != "" ]; then
                $SSH $o_pool zfs set quota=${clone_quota} ${o_pool}/${o_folder}/dev/${dev_name} || \
                    die "FAILED: $SSH $o_pool zfs set quota=${clone_quota} ${o_pool}/${o_folder}/dev/${dev_name}" 1
            fi
            if [ "$dev_ip" != "" ]; then
                $SSH $o_pool zfs set sharenfs="rw=@${dev_ip}/32,root=@${dev_ip}/32" ${o_pool}/${o_folder}/dev/${dev_name} || \
                    die "FAILED: $SSH $o_pool zfs set sharenfs="rw=@${dev_ip}/32,root=@${dev_ip}/32" ${o_pool}/${o_folder}/dev/${dev_name}" 1
            fi
            $SSH $o_pool zfs snapshot ${o_pool}/${o_folder}/dev/${dev_name}@clone || \
                die "FAILED: $SSH $o_pool zfs snapshot ${o_pool}/${o_folder}/dev/${dev_name}@clone" 1
        else
            echo "TEST MODE.  Would run:"
            echo "$SSH $o_pool zfs clone ${o_pool}/${o_folder}@${snap} ${o_pool}/${o_folder}/dev/${dev_name}"
            echo "$SSH $o_pool zfs snapshot ${o_pool}/${o_folder}/dev/${dev_name}@clone"
        fi
    done
fi


NUM=1
line=`$SED "${NUM}q;d" ${myTMP}/dataset_folders_$$`
while [ "$line" != '' ]; do 
    clone_folder=`echo $line | $CUT -d ' ' -f 1`
    this_datasets=`echo $line | $CUT -d ' ' -f 2`
    
    origin_path="/${clone_dataset}/${clone_folder}"
    debug "Cloning folder: $clone_folder origin: $origin_path datasets: $this_datasets"
    
    if [ "$this_datasets" != '' ]; then
        IFS=','
        for ozmt_dataset in $this_datasets; do
        unset IFS
            
            this_source="${o_source["$ozmt_dataset"]}"
            o_pool=`echo $this_source | $CUT -d ':' -f 1`
            o_folder=`echo $this_source | $CUT -d ':' -f 2`

            origin_path="/${ozmt_dataset}/${clone_folder}"
            debug "Origin: $origin_path"

            # Clone it
            notice "Creating ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder} from ${o_pool}/${o_folder}/${clone_folder}@${snap}"
            if [ "$test" != 'true' ]; then
                $SSH $o_pool zfs clone ${o_pool}/${o_folder}/${clone_folder}@${snap} ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder} || \
                    die "FAILED: $SSH $o_pool zfs clone ${o_pool}/${o_folder}/${clone_folder}@${snap} ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder}" 1
            else
                echo "TEST MODE.  Would run:"
                echo "$SSH $o_pool zfs clone ${o_pool}/${o_folder}/${clone_folder}@${snap} ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder}"
            fi

            # Fix up any reparse points
            $SSH $o_pool "$FIND ${origin_path} -maxdepth 3 -type l -exec ls -l {} \;" | \
                $GREP REPARSE | $AWK -F ' ' '{printf("%s\t%s\n",$9,$11)}' > \
                ${myTMP}/dataset_reparse_${ozmt_dataset}_$$ 



            debug "Found reparse points: $(wc -l ${myTMP}/dataset_reparse_${ozmt_dataset}_$$)"
            clone_path="/${o_folder}/dev/${dev_name}/${clone_folder}"

            process_reparse "${myTMP}/dataset_reparse_${ozmt_dataset}_$$" "$origin_path" "$clone_path" "$ozmt_dataset"

            # Snapshot the folder
            if [ "$test" != 'true' ]; then
                $SSH $o_pool zfs snapshot ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder}@clone || \
                    die "FAILED: $SSH $o_pool zfs snapshot ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder}@clone" 1
            else
                echo "TEST MODE.  Would run:"
                echo "$SSH $o_pool zfs snapshot ${o_pool}/${o_folder}/dev/${dev_name}/${clone_folder}@clone"
            fi
           
            IFS=','
        done
        
    fi
    NUM=$(( NUM + 1 ))
    line=`$SED "${NUM}q;d" ${myTMP}/dataset_folders_$$`
done


# Resume Replication

die "" 0



