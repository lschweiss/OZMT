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


. $TOOLS_ROOT/ansi-color-0.6/color_functions.sh

. $TOOLS_ROOT/reporting/reporting_functions.sh

now() {
    date +"%F %r %Z"
}

now_stamp () {
    date +"%F_%H:%M:%S%z"
}

check_key () {
    
    # confirm the key
    poolkey=`cat ${ec2_zfspool}_key.sha512`
    sha512=`echo $key|sha512sum|cut -d " " -f 1`
    
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
    $awk '{ ex = index("KMG", substr($1, length($1)))
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

####
#
# Pool and file system functions
#
####

pools () {
    # Returns all pools mounted on the system excluding the rpool

    zpool list -H | cut -f 1  | $grep -v "$(rpool)"

}

rpool () {
    # Returns the active rpool

    mount|$grep -e "^/ on"| $awk -F " on " '{print $2}'| $awk -F "/" '{print $1}'

}

init_lock () {

    local lockfile="${1}.lock"
    local unlockfile="${lockfile}.unlock"

    # This has a very short race window between the two checks.   Not sure how to eliminate it.

    if [ ! -f "$lockfile" ]; then
        if [ ! -f "$unlockfile" ]; then
            touch "$unlockfile"
        fi
    fi

}

function wait_for_lock() {

    #TODO: clean up the sleep times and time accounting

    local lockfile="${1}.lock"
    local unlockfile="${lockfile}.unlock"

    local expire=
    local lockpid=
    local locked='false'

    if [ "$#" -eq "2" ]; then
        expire="$2"
    else
        expire="1800"
    fi

    debug "Aquiring lock file: $lockfile"

    local waittime=0

    # This attempts to eliminate race conditions.  However, in the case where a lock
    # exists and the process is dead, two scripts could create a race when removing
    # the lock.  By putting a sleep after removing the lock by creating the unlock
    # file, the script that cycles first will successfully mv the unlockfile to the lock file.

    while [ "$locked" == "false" ]; do
        if [ -e $unlockfile ]; then
            sleep 0.1
            rm $unlockfile 2> /dev/null && echo $$ > $lockfile && locked="true"
            if [ "$locked" == "false" ]; then
                debug "Another process got the lock first.  Still waiting."
            fi
        else
            lockpid=`cat $lockfile`
            # check if it is running
            if [ -e /proc/$lockpid ]; then
                ps awwx |$grep -v grep | $grep -q "$lockpid "
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
                    touch $unlockfile
                    #Reduce the odds of a race condition
                    sleep 0.2
                fi
            else
                debug "Lock file exists, however the process is dead."
                debug "Claiming previous lock file."
                touch $unlockfile
                #Reduce the odds of a race condition
                sleep 0.3
            fi
        fi
    done

    debug "Lock obtained: $lockfile"

}

function release_lock() {

    local lockfile="${1}.lock"
    local unlockfile="${lockfile}.unlock"

    local lockpid=

    if [ -e "$lockfile" ];then
        # Check the PID
        lockpid=`cat "$lockfile"`
        if [ $$ -eq $lockpid ]; then
            locked="false"
            mv $lockfile $unlockfile
            debug "Lock released: $lockfile"
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
