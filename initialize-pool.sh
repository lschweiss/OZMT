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
. ./zfs-tools-init.sh

pool="$1"

zpool list ${pool}

if [ $? -ne 0 ]; then 
    echo "Please specify a pool to initialize."
    echo " $0 {pool}"
    exit 1
fi

echo "Initializing pool: $pool"

zfs list ${pool}/zfs_tools 2> /dev/null

if [[ $? -eq 0 || -d /$pool/zfs_tools ]]; then
    echo "zfs_tools folder already exists on pool $pool"
    echo "nothing to do"
    exit 1
fi


###
#
# Setup the zfs_tools folder
#
###


zfs create -o compression=on ${pool}/zfs_tools 

mkdir -p /${pool}/zfs_tools/etc/pool-filesystems

cp $TOOLS_ROOT/filesystem_template /${pool}/zfs_tools/etc/filesystem_template

# Create stub folder definitions

folders=`zfs list -r -H -o name ${pool}`

for full_folder in $folders; do
    if [ "$full_folder" == "$pool" ]; then
        # Skip the root folder
        continue
    fi
    # Trim the pool name
    IFS='/'
    read -r junk folder <<< "$full_folder"
    defname=$(foldertojob $folder)
    echo "Adding folder definition stub for $folder"
    cp $TOOLS_ROOT/filesystem_template /${pool}/zfs_tools/etc/pool-filesystems/${defname}
done

echo "Initialization complete for pool $pool"
echo "Make sure you edit each defintion in /${pool}/zfs_tools/etc/pool-filesystems to match your existing folders configuration."

exit 0


