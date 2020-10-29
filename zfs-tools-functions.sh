#! /bin/bash

# zfs-tools-functions.sh
#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2015  Chip Schweiss

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

_DEBUG="on"
function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}


source $TOOLS_ROOT/ansi-color-0.6/color_functions.sh

source $TOOLS_ROOT/reporting/reporting_functions.sh

if [ -t 1 ]; then 
    source $TOOLS_ROOT/utils/dialog/setup-vars
fi

now() {
    ${DATE} +"%F %r %Z"
}

now_stamp () {
    ${DATE} +"%F_%H:%M:%S%z"
}

job_stamp () {
    ${DATE} +"%F %H:%M:%S%z"
}

pause () {
    if [ -t 1 ]; then
        local trash=
        # Used when testing new script functions
        echo -n "Press enter to continue..."
        read trash
    fi
}


check_key () {
    
    # confirm the key
    poolkey=`cat ${ec2_zfspool}_key.sha512`
    sha512=`echo $key|sha512sum|${CUT} -d " " -f 1`
    
    if [ "$poolkey" != "$sha512" ]; then
       echo "Invalid encryption key for ${ec2_zfspool}!"
       exit 1
    else
       echo "Key is valid."
    fi

}

pidtree() {
    declare -A CHILDS
    while read P PP;do
        CHILDS[$PP]+=" $P"
    done < <(ps -e -o pid= -o ppid=)

    walk() {
        echo $1
        for i in ${CHILDS[$1]};do
            walk $i
        done
    }

    for i in "$@";do
        walk $i
    done
}


####
#
# Conversions
#
####

tobytes () {
    local size="$1"
    local bytes="$1" # Return the input if we don't have anything to do
    local mathline=
    
    case $size in 
        *T*) # Terabytes notation
            mathline=`echo $size | \
                        ${SED} 's/TiB/*(1024^4)/' | \
                        ${SED} 's/TB/*(1000^4)/' | \
                        ${SED} 's/T/*(1024^4)/'`
            bytes=`echo "${mathline}" | $BC`
            ;;
        *G*) # Gigabyte notation
            mathline=`echo $size | \
                        ${SED} 's/GiB/*(1024^3)/' | \
                        ${SED} 's/GB/*(1000^3)/' | \
                        ${SED} 's/G/*(1024^3)/'`
            bytes=`echo "${mathline}" | $BC`
            ;;
        *M*) # Megabyte notation
            mathline=`echo $size | \
                        ${SED} 's/MiB/*(1024^3)/' | \
                        ${SED} 's/MB/*(1000^3)/' | \
                        ${SED} 's/M/*(1024^3)/'`
            bytes=`echo "${mathline}" | $BC`
            ;;
    esac

    echo $bytes

    
}

bytestohuman () {
    if [ "$2" != "" ]; then
        scale="$2"
    else
        scale=3
    fi

    if [ $1 -ge 1099511627776 ]; then
        echo -n "$(echo "scale=${scale};$1/1099511627776"|bc) TiB"
        return
    fi

    if [ $1 -ge 1073741824 ]; then
        echo -n "$(echo "scale=${scale};$1/1073741824"|bc) GiB"
        return
    fi

    if [ $1 -ge 1048576 ]; then
        echo -n "$(echo "scale=${scale};$1/1048576"|bc) MiB"
        return
    fi

    if [ $1 -ge 1024 ]; then
        echo -n "$(echo "scale=${scale};$1/1024"|bc) KiB"
        return
    fi

    echo "$1 bytes"

}

foldertojob () {
    ${SED} 's,/,%,g' <<< "${1}"
}

jobtofolder () {
    ${SED} 's,%,/,g' <<< "${1}"
}

####
#
# Tests
#
####



# Test an IP address for validity:
# Usage:
#      valid_ip IP_ADDRESS
#      if [[ $? -eq 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_ip IP_ADDRESS; then echo good; else echo bad; fi
#
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    unset IFS
    return $stat
}


# Given a hostname or IP address determine if it local to this host
# Usage:
#     islocal hostname
#   OR
#     islocal fqdn
#   OR
#     islocal xxx.xxx.xxx.xxx
#
# Checks /etc/hosts followed by dig for matches.
# Returns 0 if local, 1 if not
islocal () {

    local host="$1"
    local ip=

    # Is this a raw IP address?

    if valid_ip $host; then
        ip="$host"
    else
        # See if it's in /etc/hosts
        getent hosts $host | ${AWK} -F " " '{print $1}' > ${TMP}/islocal_host_$$
        if [ $? -eq 0 ]; then
            ip=`cat ${TMP}/islocal_host_$$`
            rm ${TMP}/islocal_host_$$ 2>/dev/null
        else
            # Try DNS
            dig +short $host > ${TMP}/islocal_host_$$
            if [ $? -eq 0 ]; then
                ip=`cat ${TMP}/islocal_host_$$`
                rm ${TMP}/islocal_host_$$ 2>/dev/null
            else
                #echo "$host is not valid.  It is not an raw IP, in /etc/host or DNS resolvable."
                rm ${TMP}/islocal_host_$$ 2>/dev/null
                return 1
            fi
        fi
    fi
    # See if we own it.
    debug "Checking if IP $ip is local.."
    # TODO: Support FreeBSD & OSX

    case $os in
        'SunOS')
            ifconfig -a | ${GREP} -q -F "inet $ip"
            if [ $? -eq 0 ]; then
                # echo "yes."
                return 0
            else
                # echo "no."
                return 1
            fi
            ;;
        'Linux')
            ifconfig -a | ${GREP} -q -F "inet addr:$ip"
            if [ $? -eq 0 ]; then
                # echo "yes."
                return 0
            else
                # echo "no."
                return 1
            fi
            ;;
    esac

}

# Given a pid file and bin path determine if a process is running
# Usage:
#     is_running {pid_file} {bin_path}
#
# Returns 0 if running, 1 if not running, 2 if there is an error checking
isrunning () {

    local pidfile="$1"
    local binpath="$2"
    local pid=

    if [ -f $pidfile ]; then
        pid=`cat $pidfile`
        case $os in
            SunOS)
                if [[ -f /proc/${pid}/path/a.out && "$binpath" == `${LS} -l /proc/${pid}/path/a.out| ${AWK} '{print $11}'` ]]; then
                    debug "isrunning: $binpath is running on pid $pid"
                    return 0
                else
                    debug "isrunning: $binpath is NOT running on pid $pid"
                    return 1
                fi
                ;;
            *)
                error "Unsupported operating system for is running: $os"
                return 2
                ;;
        esac
        return 2
    else
        debug "isrunning: no pid file: $pidfile"
        return 1
    fi

}


####
#
# Deal with broken SunSSHd server on Illumos
#
# Note: shortly after writing this function it was found that the bug is related to 
# MaxStartups being set to 10 in /etc/ssh/sshd_config
# This is supposed to only restrict unauthenticated connections. However is also
# restricting authenticated connections.   A simple workaround is to increse this to 
# 20 or more.
#
####

ssh_wrap () {

    local result=255
    local tries=0

    rm -f ${TMP}/ssh_wrap_$$

    while [[ $tries -lt 20 && $result -eq 255 ]]; do

        "$@" 2> ${TMP}/ssh_wrap_$$
        result=$?

        if [ $result -ne 255 ]; then
            if [ -f ${TMP}/ssh_wrap_$$ ]; then
                >&2 cat ${TMP}/ssh_wrap_$$
            fi
        else
            sleep 20
        fi

        tries=$(( tries + 1 ))

    done

    if [ "$DEBUG" != 'true' ]; then
        rm -f ${TMP}/ssh_wrap_$$
    else
        echo "Tries: $tries"
    fi

    return $result

}

####
#
# mkdir function that will set all created directory group ownership to ozmt
#
####

MKDIR () {

    local folder="$1"
    local mkdirout=
    local new_folder=
    local new_folders=
    local mytmp="${TMP}/new_folders_$$_$RANDOM"

    mkdir -p ${TMP}
    chmod 2770 ${TMP} 2>/dev/null
    chgrp ozmt ${TMP} 2>/dev/null

    # Not all versions of GNU mkdir use the same characters around the directory names.
    # This solution seems to be fairly universal.
    mkdir --parents --verbose $folder | $AWK '{print $4}' | $SED 's/^.//' | $SED 's/.$//' > $mytmp
    if [ -f $mytmp ]; then
        new_folders=`cat $mytmp`
        for new_folder in $new_folders; do
            chmod 2770 $new_folder 2>/dev/null
            chgrp ozmt $new_folder 2>/dev/null
        done    
        rm -f $mytmp
    fi

}

####
#
# is_mounted returns true if the pool and zfs_tools is mounted
#
###

is_mounted () {

    local this_pool="$1"
    
    if [ "$(zfs get -o value -H mounted $this_pool)" == "yes" ]; then
        if [ "$(zfs get -o value -H mounted ${this_pool}/zfs_tools)" == "yes" ]; then
            return 0
        else
            warning "${this_pool}/zfs_tools is not mounted"
        fi
    else
        warning "${this_pool} is not mounted"
    fi

    return 1
}
        


####
#
# Pool and file system functions
#
####

pools () {
    local ex=
    local pool=
    local pools=
    # Returns all pools mounted on the system excluding the $skip_pools

    zpool list -H -o name > ${TMP}/pools_$$
    # Strip explicitly declared "skip_pools"
    for ex in $skip_pools; do
        cat ${TMP}/pools_$$ | ${GREP} -v "^${ex}$" > ${TMP}/poolsx_$$
        rm ${TMP}/pools_$$
        mv ${TMP}/poolsx_$$ ${TMP}/pools_$$
    done
    # Strip pools without a zfs_tools directory
    pools=`cat ${TMP}/pools_$$`
    for pool in $pools; do
        if [ -d "/${pool}/zfs_tools" ]; then
            echo "$pool"
        fi
    done
    rm ${TMP}/pools_$$
}

rpool () {
    # Returns the active rpool

    mount|${GREP} -e "^/ on"| ${AWK} -F " on " '{print $2}'| ${AWK} -F "/" '{print $1}'

}

cluster_pools () {

    local ex=
    local host=

    set +m

    IFS=':'
    for host in $zfs_replication_host_list; do 
        #debug "Collecting pools on host $host"
        { ( unset IFS;timeout 20s $SSH $host zpool list -H -o name 2>/dev/null >>${TMP}/pools_$$_$host ) & } 2>/dev/null
        IFS=":"
    done
    wait 
    IFS=':'
    for host in $zfs_replication_host_list; do
        if [ -f ${TMP}/pools_$$_$host ]; then
            # Strip explicitly declared "skip_pools"
            IFS=" "
            for ex in $skip_pools; do
                cat ${TMP}/pools_$$_$host | ${GREP} -v "^${ex}$" > ${TMP}/poolsx_$$_$host
                rm ${TMP}/pools_$$_$host
                mv ${TMP}/poolsx_$$_$host ${TMP}/pools_$$_$host
            done
            cat ${TMP}/pools_$$_$host
            rm ${TMP}/pools_$$_$host
        fi
        IFS=':'
    done
    unset IFS
    
    set -m

}

replication_source () {

    # Returns the parent folder of a defined replication dataset given any child folder.

    # Can receive one or two parameters
    
    # 1: replication_source pool/zfs_folder
    # 2: replication_source pool zfs_folder

    if [ "$2" == "" ]; then
        local zfsfolder="${1}"
    else
        local zfsfolder="${1}/${2}"
    fi

    local replication=
    local replication_source_reported=
    local replication_source_full=
    local replication_source_pool=

    replication=`zfs get -H -o value $zfs_replication_property $zfsfolder 2>/dev/null`
    if [ "$replication" == "" ]; then
        # ZFS folder does not exist on this pool yet
        echo "ERROR"
        return 1
    fi
    if [ "$replication" == "on" ]; then
        # Make sure we are the source, not the target
        replication_source_reported=`zfs get -H -o source ${zfs_replication_property} ${zfsfolder}`
        if [ "$replication_source_reported" == "local" ]; then

            replication_source_full="$zfsfolder"
        else
            replication_source_full=`echo $replication_source_reported |  ${AWK} -F "inherited from " '{print $2}' `
        fi
        IFS="/"
        read -r junk replication_source <<< "$replication_source_full"
        unset IFS
        replication_source_pool=`cat /${pool}/zfs_tools/var/replication/source/$(foldertojob ${replication_source})`
        echo "$replication_source_pool"
        return 0
    else
        echo "NONE"
        return 0
    fi

}

local_datasets () {

    # Accepts one or two  parameters 
    # First paramerter:
    #    Either "source" or "target" or "all" to return only primary, only target datasets or all datasets
    # Second parameter:
    #   Set to 'folder' to return the folder name instead of the dataset name



    local dataset_type=
    local dataset=
    local datasets=
    local pool=
    local folder=
    local folders=

    case $1 in
        'source')
            dataset_type='source'
            ;;
        'target')
            dataset_type='target'
            ;;
        *)
            dataset_type='all'
            ;;
    esac

    folders=`zfs get -d2 -s local,received -o name -H ${zfs_dataset_property}`

    for folder in $folders; do        
        pool=`echo $folder| $AWK -F '/' '{print $1}'`
        dataset=`zfs get -d2 -s local,received -o value -H ${zfs_dataset_property} $folder`
        if [ "$dataset_type" == 'all' ]; then
            if [ "$2" == 'folder' ]; then
                echo "$folder"
            else 
                echo "$dataset"
            fi
            continue
        fi
        
        if [ -f /${pool}/zfs_tools/var/replication/source/$dataset ]; then
            cat "/${pool}/zfs_tools/var/replication/source/$dataset" | ${GREP} -q "$pool"
            if [ $? -eq 0 ]; then
                if [ "$dataset_type" == 'source' ]; then
                    if [ "$2" == 'folder' ]; then
                        echo "$folder"
                    else
                        echo "$dataset"
                    fi
                    continue
                fi
            else
                if [ "$dataset_type" == 'target' ]; then
                    if [ "$2" == 'folder' ]; then
                        echo "$folder"
                    else
                        echo "$dataset"
                    fi
                    continue
                fi
            fi                   
        fi        
    done

}

dataset_source () {

    # For next gen replication only.  Relies on zfs property configured replication.

    # Can receive a {dataset} name or {pool} {zfs_folder}
    # If a dataset name is provided, function may be slow while finding the dataset in the cluster

    local dataset_name=
    local pool_folder=
    local pool=
    local folder=
    local dataset_list="${TMP}/datasets_source_$$"
    local replication=
    local replication_source=
    local endpoints=
    local endpoint=
    local endpoint_source=
    local endpoint_pool=
    local endpoint_folder=
    local endpoint_timestamp=
    local newest=0
    local count=

    set +m

    if [ "$2" == '' ]; then
        dataset_name="$1"
        # Find the dataset
        pools="$(cluster_pools)"
        for pool in $pools; do
            if [[ "$pool" == "rpool"* ]]; then
                continue
            fi
            if [[ "$pool" == "dump"* ]]; then
                continue
            fi
            #debug "Checking pool $pool"
            ping -c 1 $pool 1>/dev/null 2> /dev/null 
            if [ $? -eq 0 ]; then
                { (  timeout 20s $SSH $pool zfs get -d2 -t filesystem -s local,received -o value,name \
                    -H ${zfs_dataset_property} $pool 2>/dev/null 3>/dev/null | \
                    ${GREP} "^${dataset_name}\s" > ${dataset_list}_${pool} ) & } 2>/dev/null
            else
                warning "Pool $pool cannot be reached"
            fi
        done
        wait
        for pool in $pools; do
            if [ -f ${dataset_list}_${pool} ]; then
                cat ${dataset_list}_${pool} | ${GREP} -q "^${dataset_name}\s"
                if [ $? -eq 0 ]; then
                    # Dataset found
                    debug "Found dataset $dataset_name"
                    pool_folder=`cat ${dataset_list}_${pool} | ${HEAD} -1 | ${CUT} -f 2`
                    pool=`echo $pool_folder | ${CUT} -d '/' -f 1`
                    folder=`echo $pool_folder | ${CUT} -d '/' -f 2`
                    rm ${dataset_list}_${pool}
                    break                   
                fi
                rm ${dataset_list}_${pool}
            fi
        done
        if [ -z "$pool_folder" ]; then
            debug "Dataset $dataset_name not found!"
            set -m
            return 1
        fi
    else
        pool=`echo $1 | ${AWK} -F '/' '{print $1}'`
        folder=`echo $1 | ${AWK} -F '/' '{print $2}'`
        pool_folder="${pool}/${folder}"
        dataset_name=`$SSH $pool zfs get -s local,received -o value -H ${zfs_dataset_property} $pool_folder 2>/dev/null 3>/dev/null`
    fi

    debug "Found dataset at $pool_folder"

    # Collect replication information
    replication=`$SSH $pool zfs get -s local,received -o value -H ${zfs_replication_property} ${pool_folder} 2>/dev/null 3>/dev/null`
    
    if [ "$replication" == 'on' ]; then
        debug "Replication is on.  Checking for actual source"

        # Get the source, strip the timestamp
        replication_source=`$SSH ${pool} cat /${pool}/zfs_tools/var/replication/source/${dataset_name} 2>/dev/null`
        debug "Tentative replication source: $replication_source"
        #replication_source=`zfs get -s local,received -o value -H ${zfs_replication_property}:source ${pool_folder} | \
        #    ${CUT} -d '|' -f 1`
      
        
        # Check all the endpoints to make sure the source is in agreement
        endpoints=`$SSH $pool zfs get -s local,received -o value -H ${zfs_replication_property}:endpoints ${pool_folder} 2>/dev/null 3>/dev/null`
        
        if [[ $endpoints =~ ^-?[0-9]+$ ]]; then
            count=1
            while [ $count -le $endpoints ]; do
                endpoint=`$SSH $pool zfs get -s local,received -o value \
                    -H ${zfs_replication_property}:endpoint:${count} ${pool_folder} 2>/dev/null 3>/dev/null`
                endpoint_pool=`echo $endpoint | ${CUT} -d ':' -f 1`
                endpoint_folder=`echo $endpoint | ${CUT} -d ':' -f 2` 
                debug "Checking source on ${endpoint_pool}/${endpoint_folder}"
                endpoint_source=`$SSH ${endpoint_pool} cat /${endpoint_pool}/zfs_tools/var/replication/source/${dataset_name} 2>/dev/null`
                    #$endpoint_pool zfs get -s local,received -o value \
                    #-H ${zfs_replication_property}:source ${endpoint_pool}/${endpoint_folder}`
                if [ "$endpoint_source" != "$replication_source" ]; then
                    error "Sources not in agreement between ${pool}/${folder} and ${endpoint_pool}/${endpoint_folder}"
                    set -m
                    return 1
                fi
                
                count=$(( count + 1 ))
                #if [ "$endpoint_source[$count]" != '' ]; then
                #    endpoint_timestamp=`echo $endpoint_source[$count] | ${CUT} -d ':' -f 2`
                #    if [ $endpoint_timestamp -gt $newest ]; then
                #        replication_source=`echo $endpoint_source[$count] | ${CUT} -d ':' -f 1`
                #        newest="$endpoint_timestamp"
                #        debug "Newest so far ${endpoint_pool}/${endpoint_folder}"
                #    fi
                #fi                   
            done
            echo "$endpoint_source"
        else
            # No endpoints 
            error "No endpoints defined for $pool_folder however replication is on"
            echo "${pool}:${folder}"
            set -m
            return 1
        fi

    else
        echo "${pool}:${folder}"
        set -m
        return 0
    fi

    set -m
    

}

get_pid () {
    # Retrives the PID from a pid file
    # Checks every 1/2 second
    # Returns -1 if pid file is not generated in X seconds

    local pid_file="$1"
    local pid=
    local timeout="$2"
    local duration=0

    
    if [ "$timeout" == "" ]; then
        timeout=20
    else 
        timeout=$(( timeout * 2 ))
    fi

    while [ "$pid" == "" ]; do
        if [ -f $pid_file ]; then
            sleep 0.1
            pid=`cat "$pid_file"`
            echo $pid
            return 0
        else
            sleep 0.5
            duration=$(( duration + 1 ))
            if [ $duration -ge $timeout ]; then
                echo "-1"
                return 1
            fi
        fi
    done
}    


vip_folders () {

    # Returns all ZFS folders within a pool with a VIP attached to them

    local pool="$1"
    local folders=
    local folder=

    zpool list $pool 1>/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        return 1
    fi

    folders=`zfs_cache list -o name,${zfs_vip_property} -d2 -t filesystem -H $pool 3>/dev/null | ${GREP} -v -P '\t-' | ${CUT} -f 1`

    for folder in $folders; do
        if [ "$(zfs get -s local,received -o name -H ${zfs_vip_property} ${folder})" == "$folder" ]; then
            echo $folder
        fi
    done

}

        


update_job_status () {

    local line=
    local temp_file="${TMP}/update_job_status_$$"
    local MIN_ARGS=
    local status_file="$1"
    local variable=
    local value=
    local declaration=
    local increment=
    local previous_value=
    local have_lock='false'
    local lock_pid=
    local keep_lock='false'

    # There is a race condition here.  When update_job_status is rewriting there is a moment
    # when the file does not exist, followed by it being unlocked.  Hopefully,
    # the this three check sequence can mitigate the race.
    if [ ! -e "$status_file" ]; then
        sleep 0.1
        if [ ! -e "${status_file}.lock" ]; then
            sleep 0.1
            if [ ! -e "${status_file}.unlock" ]; then
                error "update_job_status called on none-existant status file: $status_file"
                return 1
            fi
        fi
    fi


    shift 1

    # Takes 3 or 4 input parameters.  Can repeat 2 through 4 for operation on multiple variables at once.
    # 1: Job status file
    # 2: Variable to update or add
    # 3: Content of the variable
    #    Set to #REMOVE# to remove the variable
    #    Use + or - to add or subtract to the current value.  
    #      (Will not allow negative values)
    # 4: specify 'local' if varable is prefixed with 'local' declarative (optional)
    #
    # Can repeat 2 through 4 for operation on multiple variables at once.

    while [ "$1" != "" ]; do

        line=

        # Minimum number of arguments needed by this function
        MIN_ARGS=2

        if [ "$#" -lt "$MIN_ARGS" ]; then
            error "update_job_status called with too few arguments.  $*"
            if [ "$have_lock" == 'true' ]; then
                release_lock "$status_file" 
            fi
            exit 1
        fi

        variable="$1"
        value="$2"
        declaration=
        increment=
        previous_value=

        rm -f "$temp_file" 2> /dev/null

        if [ "$3" == "local" ]; then
            declaration="local ${variable}"
            shift 3
        else
            declaration="${variable}"
            shift 2
        fi

        if [ "$have_lock" == 'false' ]; then
            # Check if our calling process locked the file already
            if [ -f "${status_file}.lock" ]; then
                lock_pid=`cat ${status_file}.lock 2>/dev/null`
                if [ "$$" == "$lock_pid" ]; then
                    debug "update_job_status: Lock obtained by calling process"
                    have_lock='true'
                    keep_lock='true'
                else
                    wait_for_lock "$status_file"
                    if [ $? -ne 0 ]; then
                        error "Could not obtain lock: $lock"
                        return 1
                    fi                
                    have_lock='true'
                fi
            else
                wait_for_lock "$status_file"
                if [ $? -ne 0 ]; then
                    error "Could not obtain lock: $lock"
                        return 1
                fi
                have_lock='true'
            fi
        fi

        debug "Updating $variable in $status_file"

        if [[ "${value:0:1}" == "+" || "${value:0:1}" == "-" ]]; then
            increment="${value:0:1}"
            value="${value:1}"
            debug "Incrementing $variable by $increment $value"
        fi

        # Copy all status lines execept the variable we are dealing with
        if [ -f "$status_file" ]; then
            while read line; do
                echo "$line" | ${GREP} -q "^${declaration}="
                if [ $? -ne 0 ]; then
                    echo "$line" >> "$temp_file"
                else
                    if [ "$increment" != "" ]; then
                        previous_value=`echo "$line" | cut -d '=' -f 2 | $SED 's/"//g'`
                    fi
                fi
            done < "$status_file"
        else
            # File will be created
            touch "$status_file"
        fi

        # Add our variable
        if [ "$value" != "#REMOVE#" ]; then
            if [ "$increment" == "" ]; then
                debug "Setting ${declaration}=\"${value}\""
                echo "${declaration}=\"${value}\"" >> "$temp_file"
            else
                if [ "$previous_value" == "" ]; then
                    if [ "$increment" == "+" ]; then
                        debug "Setting ${declaration}=\"${value}\""
                        echo "${declaration}=\"${value}\"" >> "$temp_file"
                    else
                        debug "Setting ${declaration}=\"0\""
                        echo "${declaration}=\"0\"" >> "$temp_file"
                    fi
                else
                    case $increment in
                        '+')
                            value=$((previous_value + value))
                            ;;
                        '-')
                            value=$((previous_value - value))
                            ;;
                    esac
                    if [ $value -lt 0 ]; then
                        value=0
                    fi
                    debug "Setting ${declaration}=\"${value}\""
                    echo "${declaration}=\"${value}\"" >> "$temp_file"
                fi 
            fi
        fi

        # Replace the status file with the updated file
        mv "$temp_file" "$status_file"

        rm $temp_file 2>/dev/null

    done

    if [ "$keep_lock" == 'false' ]; then
        release_lock "$status_file"
    fi

    return 0

}

#init_lock () {
#
#    local lockfile="${1}.lock"
#    local unlockfile="${1}.unlock"
#
#
#    # Update from old unlock naming
#    if [ -f "${lockfile}.unlock" ]; then
#        rm "${lockfile}.unlock"
#    fi
#
#    # This has a very short race window between the two checks.   Not sure how to eliminate it.
#
#    if [ ! -f "$lockfile" ]; then
#        if [ ! -f "$unlockfile" ]; then
#            touch "$unlockfile"
#        fi
#    fi
#
#}

init_lock () {

    local file="$1"
    local lockfile="${1}.lock"
    local unlockfile="${1}.unlock"
    local files=

    files=`echo -E ${file}* 2>/dev/null`

    # Test the file to lock exists
    if [ ! -e "$file" ]; then
        error "Attempted to initialize a lock on a non-existant file ${file}."
        return 1
    fi

    # Test either lock or unlock file exists

    echo -E $files | ${GREP} -q -F "$unlockfile"
    if [ $? -ne 0 ]; then
        echo -E $files | ${GREP} -q -F "$lockfile"
        if [ $? -ne 0 ]; then
            touch "$unlockfile"
        fi
    fi

}


wait_for_lock() {

    local lockfile="${1}.lock"
    local unlockfile="${1}.unlock"

    local expire=
    local lockpid=
    local locked='false'

    local deadcount=0

    if [ "$#" -eq "2" ]; then
        expire="$2"
    else
        expire="1800"
    fi

    debug "Aquiring lock file: $lockfile"

    # Check for lock file
    # There is a race condition here.  When update_job_status is rewriting there is a moment
    # when the file does not exist, followed by it being unlocked.  Hopefully,
    # the this three check sequence can mitigate the race.   
    if [ ! -e "$1" ]; then
        sleep 0.1
        if [ ! -e "$lockfile" ]; then
            sleep 0.1
            if [ ! -e "$unlockfile" ]; then
                error "Wait for lock called on non-existant file $1"
                return 1
            fi
        fi
    fi

    local starttime=$SECONDS

    # This attempts to eliminate race conditions.  However, in the case where a lock
    # exists and the process is dead, two scripts could create a race when removing
    # the lock.  By putting a sleep after removing the lock by creating the unlock
    # file, the script that cycles first will successfully mv the unlockfile to the lock file.

    while [ "$locked" == "false" ]; do
        if [ -e "$unlockfile" ]; then
            sleep 0.1
            rm "$unlockfile" 2> /dev/null && echo $$ > "$lockfile" && locked="true"
            if [ "$locked" == "false" ]; then
                debug "Another process got the lock first.  Still waiting."
            fi
        else
            lockpid=`cat "$lockfile" 2>/dev/null`
            # check if it is running
            # TODO: Make this work on things beside Illumos
            if [ -e /proc/$lockpid ]; then
                # TODO: This assumes the pid is the process that called for the lock.  This is only
                # likely on a system that has rapid reuse of PIDs.

                # TODO: Don't use ps, it can be to heavy when the system is load stressed.
                #ps awwx |${GREP} -v grep | ${GREP} -q "$lockpid "
                #result=$?
                #if [ "$result" -eq "0" ]; then
                    # Process id exists.  Sleep 1/2 second and try again.
                #    sleep 0.5
                    if [ $(( $SECONDS - $starttime )) -ge $expire ]; then
                        warning "Previous run of $0 (PID $lockpid) appears to be hung.  Giving up. To manually clear, delete ${lockfile} and touch ${unlockfile}"
                        return 1
                    fi
                #else
                #     error "Lock file exists, however the process is dead: $lockfile"
                #     return 1
                #     #debug "Removing the lock file."
                #     #touch "$unlockfile"
                #     #Reduce the odds of a race condition
                #     #sleep 0.2
                #fi
            else
                # Give the previous lock holder a chance to return the unlock file.
                deadcount=$(( deadcount + 1 ))
                if [ $deadcount -ge 3 ]; then
                    error "Lock file exists, however the process is dead: $lockfile"
                    return 1
                fi
                #debug "Claiming previous lock file."
                #touch "$unlockfile"
                #Reduce the odds of a race condition
                #sleep 0.3
            fi
            sleep 0.5
        fi
    done

    debug "Lock obtained: $lockfile"

}

release_lock() {

    local lockfile="${1}.lock"
    local unlockfile="${1}.unlock"

    local lockpid=

    if [ -e "$lockfile" ];then
        # Check the PID
        lockpid=`cat "$lockfile" 2>/dev/null`
        
        if [[ $lockpid != ''  && $$ -eq $lockpid ]]; then
            locked="false"
            mv "$lockfile" "$unlockfile"
            debug "Lock released: $lockfile"
        else
            error "release_lock called without lock ownership: $lockfile" 
            return 1
        fi
    else
        error "release_lock called without lock being obtained first: $lockfile"
        return 1
    fi
    
    return 0

}

release_locks () {
    if [ -f "$1" ]; then
        while IFS='' read -r line || [[ -n "$line" ]]; do
            release_lock "$line"
        done < "$1"
    else
        error "release_locks called without invalid file $1"
    fi
}


local_source () {

    # processes a data file line by line outputing 'local' at the begining of each line
    # so variables will be local to sourcing bash function

    # Usage:
    #
    # Add in a bash function:
    #
    # $(local_source {file_name})   

    # File must contain only lines defining variables.

    local line=

    if [ -f "$1" ]; then
        while IFS='' read -r line || [[ -n $line ]]; do
            echo $line | ${GREP} -q "^local"
            if [ $? -eq 0 ]; then
                echo $line
            else
                echo "local $line"
            fi
        done < "$1"
    fi

}

# Launch a command in the background if NOT running on the console
launch () {
    if [[ -t 1 && "$BACKGROUND" != "true" ]]; then
        debug "Launching as a forground process: $*"
        "$@"
        launch_pid=
    else
        debug "Launching as a background process: $*"
        "$@" &
        launch_pid=$!
    fi
}



# ZFS list/get with caching
# Requires first argument to be 'get' or 'list'
# Requires last argument to be pool/folder format

# First line of the cache file stores the undoctored command.  It is used to rebuild the cache in the background.


zfs_cache () {
    local first="$1"
    local last="${!#}"
    local pool=`echo $last | ${CUT} -d '/' -f 1`
    local fixed_args=`echo "$*" | ${SED} -e 's/ /_/g' -e 's,/,%,g'`
    local cache_path=
    local cache_file=
    local use_cache='false'
    local zfs_command=
    local result=0

    cache_path="/${pool}/zfs_tools/var/cache/zfs_cache"
    if [ ! -d "${cache_path}" ]; then
        MKDIR "${cache_path}"
        init_lock "${cache_path}"
    fi

    cache_file="${cache_path}/zfs_${fixed_args}"
 
    if [ -f "${cache_file}" ]; then
        if [ -f "${cache_path}/.cache_stale" ]; then
            if [ "${cache_path}/.cache_stale" -ot "${cache_file}" ]; then
                # Cache has been updated since being declared stale.
                use_cache='true'
            else
                # Cache is stale, re-run the command
                debug "Cache is stale. Updating."
                use_cache='false'
            fi              
        else
            use_cache='true'
        fi
    fi

    if [ "$use_cache" == 'true' ]; then
        tail -n+2 $cache_file
        touch "${cache_file}.lastused"
    else
        if [ -f "${cache_path}.lock" ]; then
            # Cache is being refeshed, don't risk colision.
            zfs $*
            result=$?
            touch "${cache_file}.lastused"
        else
            echo "zfs $*" > $cache_file
            zfs $* | tee -a $cache_file
            result=$?
            touch "${cache_file}.lastused"
        fi
    fi

    # Allow capture of the cache file associated with this request
    echo "$cache_file" >&3 2>/dev/null

    return $result
}


# Remote version of zfs_cache, that stores cache locally.

# Requires first argument to be 'get' or 'list'
# Requires last argument to be pool/folder format

# Similar to replication requirement the command will be completed through ssh to the pool name
# Calling function must take care of cache cleaning

remote_zfs_cache () {
    local first="$1"
    local last="${!#}"
    local pool=`echo $last | ${CUT} -d '/' -f 1`
    local fixed_args=`echo "$*" | ${SED} -e 's/ /_/g' -e 's,/,%,g'`
    local cache_path=
    local cache_file=
    local use_cache='false'
    local zfs_command=
    local result=0

    cache_path="/var/zfs_tools/cache/zfs_cache/${pool}"
    
    if [ ! -d "${cache_path}" ]; then
        MKDIR "${cache_path}"
        init_lock "${cache_path}"
    fi

    cache_file="${cache_path}/zfs_${fixed_args}"

    if [ -f "${cache_file}" ]; then
        if [ -f "${cache_path}/.cache_stale" ]; then
            if [ "${cache_path}/.cache_stale" -ot "${cache_file}" ]; then
                # Cache has been updated since being declared stale.
                use_cache='true'
            else
                # Cache is stale, re-run the command
                debug "Cache is stale. Updating."
                use_cache='false'
            fi
        else
            use_cache='true'
        fi
    fi

    if [ "$use_cache" == 'true' ]; then
        zfs_command=`head -1 $cache_file`
        if [ "$zfs_command" != "zfs $*" ]; then
            # Return the cache and update cache file to include the command
            cat $cache_file
            debug "Updating cache to new format.  File: $cache_file "
            sed -i '1s,^,zfs $*\n,' $cache_file
        else
            debug "Using cache file"
            tail -n+2 $cache_file
            touch "${cache_file}.lastused"
        fi
    else
        echo "zfs $*" > $cache_file
        $SSH $pool "zfs $*" | tee -a $cache_file
        result=$?
        touch "${cache_file}.lastused"
    fi

    if [ $result -ne 0 ]; then
        # Command failed, don't save the cache
        rm -f $cache_file
        rm -f "${cache_file}.lastused"
    fi

    # Allow capture of the cache file associated with this request
    echo "$cache_file" >&3 2>/dev/null

    return $result
}

stop_cron () {
    # For operations such as import or exporting a pool we don't want our cron
    # jobs firing durring these operations

    case $os in
        'SunOS')
            svcadm disable svc:/system/cron:default
            return $?
            ;;
        'Linux')
            # TODO: Need to test if this a a systemd OS
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

start_cron () {
    # For operations such as import or exporting a pool we don't want our cron
    # jobs firing durring these operations

    case $os in
        'SunOS')
            svcadm enable svc:/system/cron:default
            return $?
            ;;
        'Linux')
            # TODO: Need to test if this a a systemd OS
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

 
    





