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

now=`date +%F_%H:%M:%S%z`

die () {

    error "backup_to_glacier: $1"
    exit 1

}

backupjobs=`ls -1 $TOOLS_ROOT/backup/jobs/glacier/active/`
jobstatusdir="$TOOLS_ROOT/backup/jobs/glacier/status"

if [ "x$glacier_logfile" != "x" ]; then
    logfile="$glacier_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$glacier_report" != "x" ]; then
    report_name="$glacier_report"
else
    report_name="$default_report_name"
fi


# Collect vaults

$glacier_cmd --output csv lsvault | awk -F '","' '{print $4}' > /tmp/glacier_vaults


cat /tmp/glacier_vaults |
while read vault
do
if [ "$vault" != "VaultName" ]; then
    temp="/tmp/${vault}_inventory_$$"
    $glacier_cmd --output csv inventory ${vault} &> $temp 
        result=$?
    if [ "$result" -ne "0" ]; then
        error "Could not request inventory for ${vault}" $temp
    else
        inventory_status=`cat $temp|head -1|awk -F '","' '{print $2}'|sed s'/..$//'`
        if [ "$inventory_status" == "Inventory retrieval in progress." ]; then
            debug "Inventory retrieval in progress for ${vault}"
        else
            cp $temp $jobstatusdir/inventory/${vault}
        fi
        rm $temp
    fi
fi

done

