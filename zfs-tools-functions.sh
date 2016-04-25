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

####
#
# Conversions
#
####

tobytes () {
    ${AWK} '{ ex = index("KMG", substr($1, length($1)))
           val = substr($1, 0, length($1))
           prod = val * 10^(ex * 3)
           sum += prod
         }
         END {print sum}'
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

replication_source () {

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

    folders=`zfs_cache list -o name,${zfs_dataset_property},${zfs_vip_property} -r -H $pool 3>/dev/null | ${GREP} -v -P '\t-' | ${CUT} -f 1`

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
            lockpid=`cat "$lockfile"`
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
        lockpid=`cat "$lockfile"`
        if [ $$ -eq $lockpid ]; then
            locked="false"
            mv "$lockfile" "$unlockfile"
            debug "Lock released: $lockfile"
        else
            set > ${TMP}/bad_lock_release_$$.txt
            error "release_lock called without lock ownership: $lockfile" ${TMP}/bad_lock_release_$$.txt
            return 1
        fi
    else
        set > ${TMP}/bad_lock_release_$$.txt
        error "release_lock called without lock being obtained first: $lockfile" ${TMP}/bad_lock_release_$$.txt
        return 1
    fi
    
    return 0

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
        mkdir -p "${cache_path}"
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
    else
        echo "zfs $*" > $cache_file
        zfs $* | tee -a $cache_file
        result=$?
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
        mkdir -p "${cache_path}"
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
        fi
    else
        echo "zfs $*" > $cache_file
        ssh $pool "zfs $*" | tee -a $cache_file
        result=$?
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

 
    





