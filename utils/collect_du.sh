#! /bin/bash


# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2014  Chip Schweiss

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
source ../zfs-tools-init.sh

now=`date +%F_%H:%M%z`

pool=$1
folder=$2
depth=$3

mkdir -p "/$pool/zfs_tools/logs"
logfile="/$pool/zfs_tools/logs/du_stat_${now}"

/usr/gnu/bin/du -h --max-depth=$depth $folder > $logfile 2> /dev/null
