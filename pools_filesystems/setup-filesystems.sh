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

rm $TOOLS_ROOT/snapshots/jobs/*/* 2> /dev/null

#rm -rf $TOOLS_ROOT/backup/jobs/*

. ./zfs_functions.sh

pools="$(pools)"

# TODO: Add checks to make sure we don't do this while jobs can be disturbed. (Job start times)

for pool in $pools; do

    if [ -f "/${pool}/zfs_tools/etc/pool-filesystems" ] ; then
        warning "Using depricated configuration. Creating new configuration in /${pool}/zfs_tools/etc/pool-filesystems.new"
        mkdir "/${pool}/zfs_tools/etc/pool-filesystems.new"
        gen_new_pool_config='true'
        notice "Setting up pool $pool"
        rm /${pool}/zfs_tools/etc/snapshots/jobs/*/* 2> /dev/null
        rm /${pool}/zfs_tools/etc/backup/jobs/*/* 2> /dev/null
        rm /${pool}/zfs_tools/etc/reports/jobs/*/* 2> /dev/null
        source /${pool}/zfs_tools/etc/pool-filesystems
    else 
        if [ -d "/${pool}/zfs_tools/etc/pool-filesystems" ]; then
            notice "Setting up pool $pool"
            failures=0
            # Determine which definitions have changed since last run 
            ls -1At --color=never /${pool}/zfs_tools/etc/pool-filesystems | \
                ${SED} '/\.last_setup_run/q' | \
                ${GREP} -v ".last_setup_run" | \
                sort | \
                tee ${TMP}/pool-filesystems.update

            folders=`cat ${TMP}/pool-filesystems.update`
            for folder in $folders; do
                rm /${pool}/zfs_tools/etc/{snapshots,backup,reports,replication}/jobs/*/${pool}%${folder} 2> /dev/null
                source /${pool}/zfs_tools/etc/pool-filesystems/${folder}
            done
            if [ $failures -eq 0 ]; then
                debug "All changes successful for pool $pool"
                touch /${pool}/zfs_tools/etc/pool-filesystems/.last_setup_run
            fi
        else
            warning "No file system configuration found for $pool"
        fi
    fi

done

