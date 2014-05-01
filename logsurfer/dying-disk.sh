#! /bin/bash

# dying-disk.sh

# With the help of logsurfer this script will interpret forwarded 
# messages and offline disks from thier pool before they cause problems.

# It requires that disk maps be up-to-date in /{pool}/zfs_tools/etc/maps

# To work with logsurfer, logsurfer must use the PIPE action to lauch this script.

#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012, 2013  Chip Schweiss

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


loglines=0

# Collect log lines from standard input.  
while read logline; do
    loglines=$(( loglines + ))
    logline[$logline]="$logline"
    debug "received: $logline"
    # Look for mpt_sas ID
    echo $logline | grep -q -e 'mpt_sas[0-9]*'
    if [ $? -eq 0 ]; then
        sas_id=`echo $logline | grep -o -e 'mpt_sas[0-9]*' | grep -o -e '[0-9]*'`
    fi

    # Loof for Target ID
    echo $logline |grep -q -e '[T|t]arget [0-9]*'
    if [ $? -eq 0 ]; then
        target_id=`echo $logline | grep -o -e '[T|t]arget [0-9]*' | grep -o -e '[0-9]*'`
    fi
done


if [ "$sas_id" == "" ]; then
    warning "dying-disk.sh called, however could not find a mpt_sas ID"
    do_nothing='true'
fi

if [ "$target_id" == "" ]; then
    warning "dying-disk.sh called, however could not find a target ID"
    do_nothing='true'
fi

if [ "$do_nothing" == 'true' ]; then
    exit 0
fi

# Find this disk in the map




