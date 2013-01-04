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

jobfolder="$TOOLS_ROOT/snapshots/jobs"

snaptype="$1"

if [ "x$snapshot_logfile" != "x" ]; then
    logfile="$snapshot_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$snapshot_report" != "x" ]; then
    report_name="$snapshot_report"
else
    report_name="$default_report_name"
fi

# collect jobs

jobs=`ls -1 $jobfolder/$snaptype`

for job in $jobs; do
    zfsfolder=`echo $job|sed 's,%,/,g'`
    keepcount=`cat $jobfolder/$snaptype/$job`
    now=`date +%F_%H:%M%z`
    stamp="${snaptype}_${now}"
    if [ "${keepcount:0:1}" != "x" ]; then
        echo -n "Creating snapshot ${zfsfolder}@${stamp}..."
        zfs snapshot ${zfsfolder}@${stamp} ; result=$?
        if [ "$result" -ne "0" ]; then
            error "Failed to create snapshot ${zfsfolder}@${stamp}"
        else
            notice "Successfully created snapshot: ${zfsfolder}@${stamp}"
        fi
    fi
    echo
done


