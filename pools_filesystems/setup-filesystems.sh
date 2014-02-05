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

rm $TOOLS_ROOT/snapshots/jobs/*/*
rm -rf $TOOLS_ROOT/backup/jobs/*

. ./zfs_functions.sh

pools="$(pools)"

for pool in $pools; do

    if [ -f "/$pool/zfs_tools/etc/pool-filesystems" ] ; then
        notice "Setting up pool $pool"
        rm /${pool}/zfs_tools/etc/snapshots/jobs/*/*
        rm /${pool}/zfs_tools/etc/backup/jobs/*/*
        source /$pool/zfs_tools/etc/pool-filesystems
    else 
        warning "No file system configuration found for $pool"
    fi

done

