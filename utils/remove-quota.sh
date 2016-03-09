#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2016  Chip Schweiss

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
    echo "Usage: $0 {zfs_folder}"
    echo "  Recursively removes quota and refquota from a zfs folder"
    echo ""
    exit 1
}



# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

zfs_folder="$1"
fail='false'


debug "Recursively removing quota and refquota from ${zfs_folder}"

# Collect folder list
target_folders=`zfs list -o name -H -r $zfs_folder `

if [ -t 1 ]; then
    echo "Folders:"
    echo $target_folders
fi

# Reset quotas
for folder in $target_folders; do
    current_quota=`zfs get -o value -H -p quota $folder 2>/dev/null`
    if [ $current_quota -ne 0 ]; then
        debug "Resetting quota on $folder"
        zfs set quota=none $folder || fail='true'
    fi
    current_refquota=`zfs get -o value -H -p refquota $folder 2>/dev/null`
    if [ $current_refquota -ne 0 ]; then
        debug "Restting refquota on $folder"
        zfs set refquota=none $folder || fail='true'
    fi
done

if [ "$fail" == 'true' ]; then
    exit 1
fi


