#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2017  Chip Schweiss

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

if [ "x$replication_logfile" != "x" ]; then
    logfile="$replication_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$replication_report" != "x" ]; then
    report_name="$replication_report"
else
    report_name="replication"
fi

pools="$(pools)"

for pool in $pools;do
    replication_folders=`zfs_cache get -r -H -o name -s local,received $zfs_replication_property $pool 3>/dev/null`
    for replication_folder in $replication_folders; do
        dataset=`zfs_cache get -H -o value -s local,received $zfs_dataset_property $replication_folder 3>/dev/null`
        target_file="/$pool/zfs_tools/var/replication/targets/$dataset"
        if [ -f "$target_file" ]; then
            targets=`cat "$target_file"`
            target_count=`cat "$target_file" | $WC -l`
            x=0 
            while [ $x -lt $target_count ]; do
                x=$(( x + 1 ))
                line=`cat $target_file | head -n $x | tail -1`
                notice "Setting $zfs_replication_property:endpoint:$x to $line on $replication_folder"
                zfs set $zfs_replication_property:endpoint:$x="$line" $replication_folder
            done
            notice "Setting $zfs_replication_property:endpoints to $target_count"
            zfs set $zfs_replication_property:endpoints=$target_count $replication_folder
        else
            warning "No targets set for $dataset"
        fi
    done
done
                
            
