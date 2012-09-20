#! /bin/bash 


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

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

. $TOOLS_ROOT/snapshots/functions.sh

# export PATH=/usr/gnu/bin:/usr/bin:/usr/sbin:/sbin:/usr/local/bin

return=0

# show program usage
show_usage() {
    echo
    echo "Usage: $0 -d {days} -c {count} -z {zfs_folder} [-p snap_prefix}]"
    echo "  [-d days] Maximum age in days of snapshots to keep"
    echo "  [-c count] Maximun count of snapshots to keep"
    echo "  [-t] trial mode.  Show what would happen."
    echo
    exit 1
}

# Minimum number of arguments needed by this program
MIN_ARGS=2

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

dflag=
cflag=
tflag=
zflag=
pflag=

days=0
count=0


while getopts tz:p:d:c: opt; do
    case $opt in
        d)  # Days Specified
            dflag=1
            dval="$OPTARG";;
        c)  # Count Specified
            cflag=1
            cval="$OPTARG";;
        z)  # ZFS folder specified
            zflag=1
            zval="$OPTARG";;
        p)  # Prefix specified
            pflag=1
            pval="$OPTARG";;
        t)  # Trial mode
            echo "Using trial mode"
            tflag=1;;
        ?)  # Show program usage and exit
            show_usage
            exit 1;;
        :)  # Mandatory arguments not specified
            echo "Option -$OPTARG requires an argument."
            exit 1;;
    esac
done

# Date parameter
progress=""
if [ ! -z "$dflag" ]; then
    #echo "Option -d $dval specified"
    echo "Attempting to use given days"
    days=$dval
fi

# Count parameter
if [ ! -z "$cflag" ]; then
    count=$cval
fi

#Move to remaining arguments
shift $(($OPTIND - 1))
#echo "Remaining arguments are: $*"

if [ "$zflag" == "0" ]; then
    echo "ERROR: -z parameter must be specified"
    exit 1
fi


# Remote folder parameter
if [ -e "/$zval" ]; then
    zfs_folder="$zval"
else
    echo "ERROR: ZFS folder $zval does not exist!"
    exit 1
fi

snap_prefix="$pval"



if [ $days -ne 0 ]; then
    echo "Removing snapshots older than ${days} from ${zfs_folder} of snap type ${snap_prefix}..."
    snap_list=`zfs list -H -r -t snapshot | \
        /usr/gnu/bin/awk -F " " '{print $1}' | \
        grep "^${zfs_folder}@${snap_prefix}" | \
        sort`
    # Extract the date from each one and see if we should destroy it.
    for snap in $snap_list; do
    
            snap_date=`echo ${snap}|grep -o -e '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'`
            snap_seconds=`date --date $snap_date +%s`
            now_seconds=`date +%s`
            elapsed=$((${now_seconds}-${snap_seconds}))
            days_elapsed=$((elapsed/86400))
            if [ "$days_elapsed" -gt "$days" ]; then
                    # Time to delete the snapshot
                if [ "$tflag" == "1" ]; then
                    echo "zfs destroy ${snap}"
                else
                    echo "Destroying: ${snap}"
                    zfs destroy ${snap}; result=$?
                    if [ "$result" -ne "0" ]; then
                        echo "ERROR: Failed to remove ${snap}"
                    fi
                fi
            fi
    
    done
    
fi

if [ $count -ne 0 ]; then
    echo "Keeping the ${count} most recent snapshots from ${zfs_folder} of snap type ${snap_prefix}..."
    # Reverse the order of the snap list from the newest to the oldest
    # Strip off the count of snaps to keep
    delete_list=`zfs list -H -r -t snapshot | \
        /usr/gnu/bin/awk -F " " '{print $1}' | \
        grep "^${zfs_folder}@${snap_prefix}" | \
        sort -r | \
        tail -n +$(( $count + 1 ))`
    for snap in $delete_list; do
        if [ "$tflag" == "1" ]; then
            echo "zfs destroy ${snap}"
        else
            echo "Destroying: ${snap}"
            zfs destroy ${snap}; result=$?
            if [ "$result" -ne "0" ]; then
                echo "ERROR: Failed to remove ${snap}"
            fi
        fi
    done
fi
