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

. /opt/ozmt/zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

now=`${DATE} +"%F %H:%M:%S%z"`

local_pools="zpool list -H -o name"

myTMP=${TMP}/disk-map
MKDIR $myTMP

locate_hbas () {
    # Only LSI / Avago / Broadcom HBAs are supported.   
    # Find SAS2 HBAs

    $SAS2IRCU list | \
    while IFS='' read -r line || [[ -n "$line" ]]; do
        index=`echo $line | ${AWK} -F ' ' '{print $1}'`
        echo $index
    done


}

