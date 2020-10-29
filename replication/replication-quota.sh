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

now=`${DATE} +"%F %H:%M:%S%z"`

pools="$(pools)"

for pool in $pools; do
    is_mounted $pool || continue

    quotas=`zfs list -o name,quota -r -H -p $pool`
    IFS=$'\n'
    for quota in $quotas; do
        folder=`echo $quota | ${CUT} -f 1`
        bytes=`echo $quota | ${CUT} -f 2`
        echo "Setting ${zfs_quota_property} on $folder to $bytes"
        zfs set ${zfs_quota_property}="$bytes" $folder
    done

    refquotas=`zfs list -o name,refquota -r -H -p $pool`
    for refquota in $refquotas; do
        folder=`echo $refquota | ${CUT} -f 1`
        bytes=`echo $refquota | ${CUT} -f 2`
        echo "Setting ${zfs_refquota_property} on $folder to $bytes"
        zfs set ${zfs_refquota_property}="$bytes" $folder
    done
    unset IFS

done
