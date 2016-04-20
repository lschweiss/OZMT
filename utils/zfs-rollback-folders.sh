#! /bin/bash

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

# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

. ../zfs-tools-init.sh

show_usage () {
    echo
    echo "Usage: $0 {zfs_folder} {snapshot}"
    echo "  Recursively rolls back zfs_folder and all children to {snapshot} if it exists"
    echo ""
    exit 1
}



# Minimum number of arguments needed by this program
MIN_ARGS=2

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

zfs_folder="$1"
snapshot="$2"
fail='false'

mkdir -p "${TMP}/replication"

debug "Recursively rolling back ${zfs_folder}@${snapshot}"

# Collect folder list
target_folder_snaps=`zfs list -o name -H -t snapshot -r $zfs_folder | ${GREP} -F ${snapshot}`

if [ -t 1 ]; then
    echo "Snaps:"
    echo $target_folder_snaps
fi

# Rollback folders
for rollback_snap in $target_folder_snaps; do
    debug "zfs rollback -Rf $rollback_snap"
    # TODO: Under heavy load or when LOTS of snapshots are being created/destroyed this rollback can take
    #       a long time.   It would be best to slow down replication in response to the rollback taking too long
    #       It should also become unnessary of all replication copies are kept unmounted. <- Prefered, but more complex.
    timeout 20m zfs rollback -Rf $rollback_snap 2>${TMP}/replication/zfs_rollback_$$.txt
    result=$?
    if [ $result -ne 0 ]; then      
        error "Could not rollback to snapshot ${rollback_snap}. Error code $result" ${TMP}/replication/zfs_rollback_$$.txt
        fail='true'
    else
        rm ${TMP}/replication/zfs_rollback_$$.txt 2>/dev/null
    fi
done

if [ "$fail" == 'true' ]; then
    exit 1
fi


