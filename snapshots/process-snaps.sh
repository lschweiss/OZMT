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

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

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


echo $snaptypes | ${GREP} -q "\b${snaptype}\b"
result=$?
if [ $result -ne 0 ]; then
    warning "process-snaps.sh: invalid snap type specified: $snaptype"
    exit 1
fi

# collect jobs

pools="$(pools)"

debug "Pools: $pools"

now=`${DATE} +%F_%H:%M%z`
stamp="${snaptype}_${now}"

MKDIR ${TMP}/snapshots

command_max=$(( $(getconf ARG_MAX) - 1024 ))

# Fork one job per pool
for pool in $pools; do

    launch ./process-snaps-pool.sh $pool $snaptype

done

