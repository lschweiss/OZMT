#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2018  Chip Schweiss

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


#
# Execute custom cron jobs for pools or datasets
# 
# Pool level cron jobs are stored in:
#
# /${pool}/etc/cron/{type}.d
#
#
# Datset level cron jobs are stored in:
# 
# /${dataset}/.cron/${type}.d
#
#
# The jobs in each type are executable files.   They are executed as:
#
# ${job_file} ${type}


type="$1"

if [ "$type" == '' ]; then
    error "Must specify cron type on command line"
    exit 1
fi

pools="$(pools)"


for pool in $pools; do
    debug "Checking pool $pool for $type cron jobs"
    crondir="/${pool}/zfs_tools/etc/cron/${type}.d"
    if [ -d $crondir ]; then
        crons=`ls -1 $crondir`
        for cron in $cron; do
            notice "Running $type cron job $cron for $pool"
            ${crondir}/${cron} &
        done
    fi
done

folders=`local_datasets all folder`

for folder in $folders; do
    debug "Checking $folder for $type cron jobs"
    mountpoint=`zfs get -o value -H mountpoint $folder`
    if [ -d "${mountpoint}/.ozmt-cron/${type}.d" ]; then
        dataset=`zfs get -o value -H $zfs_dataset_property $folder`
        crons=`ls -1 ${mountpoint}/.ozmt-cron/${type}.d`
        for cron in $crons; do
            notice "Running $type cron job $cron for $dataset"
            ${mountpoint}/.ozmt-cron/${type}.d/${cron} &
        done
    fi
done

