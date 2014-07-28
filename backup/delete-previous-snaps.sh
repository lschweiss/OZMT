#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2014  Chip Schweiss

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

if [ "x$zfs_logfile" != "x" ]; then
    logfile="$zfs_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$zfs_report" != "x" ]; then
    report_name="$zfs_report"
else
    report_name="$default_report_name"
fi



die () {
    error "$1"
    if [ "$tmpdir" != "" ]; then
        rm -rf $tmpdir
    fi
}


# show function usage
show_usage() {
    echo
    echo "Usage: $0 -f {zfs_folder} -n {snapshot name}"
    echo "  [-h {host}]         Host to operate on.  Defaults to localhost."
    echo "  [-l {snapshot}]     Keep {snapshot} and stop processing."
    echo "  [-t {tag}]          Release the hold with the tag {tag}"
    echo "                        (Other tags may still prevent snapshot deletion)"
    echo "  [-r]                Operate recursively"
}

while getopts f:n:h:l:t:r opt; do
    case $opt in
        f) # ZFS folder
            folder="$OPTARG"
            ;;
        n) # Snapshot name
            snap_name="$OPTARG"
            ;;
        h) # Hostname
            host="$OPTARG"
            ;;
        l) # Last snap shot
            last_snap="$OPTARG"
            ;;
        t) # Hold tag to remove
            hold_tag="$OPTARG"
            ;;
        r) # Operate recursively
            recurse="-r"
            ;;
        
        ?)  # Show program usage and exit
            show_usage
            exit 0
            ;;
        :)  # Mandatory arguments not specified
            die "${job_name}: Option -$OPTARG requires an argument."
            ;;

    esac
done

if [ "$host" == '' ]; then
    host='localhost'
fi

if [ "$folder" == '' ]; then
    die "Require parameter -f {zfs_folder} missing"
fi

if [ "$snap_name" == '' ]; then
    die "Require parameter -n {snapshot name} missing"
fi



snap_file="$TMP/delete_previous_snaps_$$"

# Generate full list of snapshots
if [ "$host" == 'localhost' ]; then
    zfs list -t snapshot -H -o name -s creation | ${GREP} "^${folder}@" > $snap_file
else
    ${SSH} root@$host zfs list -t snapshot -H -o name -s creation | ${GREP} "^${folder}@" > $snap_file
fi

# Parse shapshot list

cat $snap_file

num_snaps=`cat $snap_file | wc -l`

this_snap_num=1

while [ $this_snap_num -le $num_snaps ]; do

    this_snap=`cat $snap_file | head -n $this_snap_num | tail -n 1`
    
    debug "Checking $this_snap"

    if [ "$this_snap" == "$last_snap" ]; then
        debug "Finished.  Reached snapshot $last_snap"
        rm $snap_file
        exit 0
    fi

    # Determine if this is a backup snap
    echo "${this_snap}" | ${GREP} -q "@${snap_name}_"
    if [ $? -eq 0 ]; then
        debug "Deleting snapshot $this_snap"
        if [ "$host" == 'localhost' ]; then
            if [ "$hold_tag" != '' ]; then
                zfs release $recurse "$hold_tag" "$this_snap"
            fi
            zfs destroy $recurse "$this_snap" 2> $TMP/zfs_destroy_snap_$$
            if [ $? -ne 0 ]; then
                warning "Failed to destroy snapshot $this_snap" $TMP/zfs_destroy_snap_$$
            fi
        else
            if [ "$hold_tag" != '' ]; then
                ${SSH} root@$host zfs release $recurse "$hold_tag" "$this_snap" 2> /dev/null
            fi
            ${SSH} root@$host zfs destroy $recurse "$this_snap" 2> $TMP/zfs_destroy_snap_$$
            if [ $? -ne 0 ]; then
                cat $TMP/zfs_destroy_snap_$$
                warning "Failed to destroy snapshot $this_snap on host $host" $TMP/zfs_destroy_snap_$$
            fi
        fi
    fi

    this_snap_num=$(( this_snap_num + 1 ))

done

debug "Finished.  Processed all snaps for $folder"
rm $snap_file
exit 0
