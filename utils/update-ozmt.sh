#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2017  Chip Schweiss

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

logging_level="0"

report_name="$default_report_name"


set +m

IFS=':'
for host in $zfs_replication_host_list; do
    #debug "Collecting pools on host $host"
    { ( unset IFS;timeout 20s $SSH $host cd /opt/ozmt; hg pull -u; ./setup-ozmt-links.sh 2>/dev/null ) & } 2>/dev/null
    IFS=":"
done
wait

set -m


