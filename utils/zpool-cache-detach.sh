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

# zpool-detach-cache.sh detaches cache devices to the pool listed in
# /{pool}/zfs_tools/etc/cache-disks 


cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -lt "$MIN_ARGS" ]; then
    echo "Must supply a pool name to detached cache disks"
    exit 1
fi


pool="$1"

zpool list $pool 1> /dev/null 2> /dev/null
if [ $? -ne 0 ]; then
    warning "zpool-detach-cache.sh: Pool \"$pool\" does not appear to be imported.  Aborting."
    exit 1
fi

##
# Collect cache disks
##

disks=`cat /${pool}/zfs_tools/etc/cache-disks`

##
# Reduce maximum freed blocks per transaction group, so remove is non-blocking
##

echo zfs_free_max_blocks/w1388 | mdb -kw

##
# Add cache disks
##

for disk in $disks; do
    
    debug "zpool-detach-cache.sh: Removing $disk from $pool"
    zpool remove $pool $disk || warning "zpool-detach-cache.sh: Failed to remove cache disk $disk to pool $pool"

done

exit 0
