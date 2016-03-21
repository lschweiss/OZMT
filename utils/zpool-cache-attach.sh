#! /bin/bash 

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2015  Chip Schweiss

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

# zpool-attach-cache.sh attaches cache devices to the pool listed in
# /{pool}/zfs_tools/etc/cache-disks 


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )


. ../zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -lt "$MIN_ARGS" ]; then
    echo "Must supply a pool name to attached cache disks"
    exit 1
fi


pool="$1"


zpool list $pool 1> /dev/null 2> /dev/null
if [ $? -ne 0 ]; then
    warning "zpool-attach-cache.sh: Pool \"$pool\" does not appear to be imported.  Aborting."
    exit 1
fi

##
# Collect cache disks
##

if [ -f /${pool}/zfs_tools/etc/cache-disks]; then
    disks=`cat /${pool}/zfs_tools/etc/cache-disks`
    
    ##
    # Add cache disks
    ##
    
    for disk in $disks; do
    
        debug "zpool-detach-cache.sh: Removing $disk from $pool"
        zpool add $pool cache $disk || warning "zpool-attach-cache.sh: Failed to add cache disk $disk to pool $pool"
    
    done

fi

exit 0
