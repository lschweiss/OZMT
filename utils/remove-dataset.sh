#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2021  Chip Schweiss

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

. /opt/ozmt/zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

now=`${DATE} +"%F %H:%M:%S%z"`

local_pools="zpool list -H -o name"

# show function usage
show_usage() {
    echo
    echo "Usage: $0 -p {pool} -d {dataset_name}"
    echo
    echo
    echo "    [-m]   Metadata only"
    echo
}

vips=0
routes=0
interfaces=0

declare -A vip

while getopts p:d:m opt; do
    case $opt in
        p)  # Pool
            pool="$OPTARG"
            debug "pool: $pool"
            ;;
        d)  # Dataset name
            dataset="$OPTARG"
            debug "dataset name: $dataset"
            ;;
        m)  # Metadata only
            meta_only='true'
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


folder="$dataset"

if [ "$meta_only" != 'true' ]; then
    zfs list $pool/$folder 2>/dev/null 
    if [ $? -ne 0 ]; then
        notice "ZFS folder $pool/$folder does not exist.  Cannot delete."
    else
        echo
        echo "ZFS folder $pool/$folder exists."
        echo -n "Press enter to continue with removal..."
        read nothing
        zfs destroy -r $pool/$folder
    fi
fi

# Remove metadata

if [ -d /$pool/zfs_tools/var/replication/jobs/definitions/$dataset ]; then
    notice "Removing replication definition at: /$pool/zfs_tools/var/replication/jobs/definitions/$dataset"
    rm -rf /$pool/zfs_tools/var/replication/jobs/definitions/$dataset
fi

if [ -f /$pool/zfs_tools/var/replication/source/$dataset ]; then
    notice "Removing replication source at: /$pool/zfs_tools/var/replication/source/$dataset"
    rm -f /$pool/zfs_tools/var/replication/source/$dataset
fi

if [ -f /$pool/zfs_tools/var/replication/targets/$dataset ]; then
    notice "Removing replication targets at: /$pool/zfs_tools/var/replication/targets/$dataset"
    rm -f /$pool/zfs_tools/var/replication/targets/$dataset
fi

zfs set ${zfs_replication_property}='off' $pool/$folder 2>/dev/null
