#! /bin/bash

# zfs-tools-init.sh
#
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

_DEBUG="on"
function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}


source $TOOLS_ROOT/ansi-color-0.6/color_functions.sh

source $TOOLS_ROOT/reporting/reporting_functions.sh

now() {
    ${DATE} +"%F %r %Z"
}

now_stamp () {
    ${DATE} +"%F_%H:%M:%S%z"
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

####
#
# Pool and file system functions
#
####

pools () {
    # Returns all pools mounted on the system excluding the $skip_pools

    zpool list -H -o name > ${TMP}/pools_$$
    for ex in $skip_pools; do
        cat ${TMP}/pools_$$ | ${GREP} -v "^${ex}$" > ${TMP}/poolsx_$$
        rm ${TMP}/pools_$$
        mv ${TMP}/poolsx_$$ ${TMP}/pools_$$
    done
    cat ${TMP}/pools_$$
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

update_job_status () {

    # Takes 3 or 4 input parameters.
    # 1: Job status file
    # 2: Variable to update or add
    # 3: Content of the variable
    #    Set to #REMOVE# to remove the variable
    #    Use + or - to add or subtract to the current value.  
    #      (Will not allow negative values)
    # 4: specify 'local' if varable is prefixed with 'local' declarative (optional)

    local line=
    local temp_file="${TMP}/update_job_status_$$"

    # Minimum number of arguments needed by this function
    local MIN_ARGS=3

    if [ "$#" -lt "$MIN_ARGS" ]; then
        error "update_job_status called with too few arguments.  $*"
        exit 1
    fi

    local status_file="$1"
    local variable="$2"
    local value="$3"
    local declaration=
    local increment=
    local previous_value=

    rm -f "$temp_file" 2> /dev/null

    if [ "$4" == "local" ]; then
        declaration="local ${variable}"
    else
        declaration="${variable}"
    fi

    debug "Updating $variable in $status_file"

    if [[ "${value:0:1}" == "+" || "${value:0:1}" == "-" ]]; then
        increment="${value:0:1}"
        value="${value:1}"
        debug "Incrementing $variable by $increment $value"
    fi

    wait_for_lock "$status_file" 5

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

    release_lock "$status_file"

    rm $temp_file 2>/dev/null

    return 0

}

init_lock () {

    local lockfile="${1}.lock"
    local unlockfile="${1}.unlock"


    # Update from old unlock naming
    if [ -f "${lockfile}.unlock" ]; then
        rm "${lockfile}.unlock"
    fi

    # This has a very short race window between the two checks.   Not sure how to eliminate it.

    if [ ! -f "$lockfile" ]; then
        if [ ! -f "$unlockfile" ]; then
            touch "$unlockfile"
        fi
    fi

}

wait_for_lock() {

    #TODO: clean up the sleep times and time accounting

    local lockfile="${1}.lock"
    local unlockfile="${1}.unlock"

    local expire=
    local lockpid=
    local locked='false'

    if [ "$#" -eq "2" ]; then
        expire="$2"
    else
        expire="1800"
    fi

    debug "Aquiring lock file: $(basename $lockfile)"

    if [ -f "${lockfile}.unlock" ]; then
        mv "${lockfile}.unlock" "$unlockfile"
        debug "Renamed unlock file to new format: $unlockfile"
    fi

    local waittime=0

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
            if [ -e /proc/$lockpid ]; then
                ps awwx |${GREP} -v grep | ${GREP} -q "$lockpid "
                result=$?
                if [ "$result" -eq "0" ]; then
                    # Process id exists.  Sleep 1/2 second and try again.
                    sleep 0.5
                    (( waittime += 1 ))
                    if [ "$waittime" -ge "$expire" ]; then
                        error "Previous run of $0 (PID $lockpid) appears to be hung.  Giving up."
                        error "Please delete ${lockfile} and touch ${unlockfile}"
                        return 1
                    fi
                else
                    debug "Lock file exists, however the process is dead."
                    debug "Removing the lock file."
                    touch "$unlockfile"
                    #Reduce the odds of a race condition
                    sleep 0.2
                fi
            else
                debug "Lock file exists, however the process is dead."
                debug "Claiming previous lock file."
                touch "$unlockfile"
                #Reduce the odds of a race condition
                sleep 0.3
            fi
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
            debug "Lock released: $(basename $lockfile)"
        else
            error "release_lock called without lock ownership"
            return 1
        fi
    else
        error "release_lock called without lock being obtained first!"
        return 1
    fi
    
    return 0

}

# Launch a command in the background if NOT running on the console
launch () {
    if [[ -t 1 && "$BACKGROUND" != "true" ]]; then
        "$@"
    else
        "$@" &
        launch_pid=$!
    fi
}
