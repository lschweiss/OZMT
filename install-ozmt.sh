#! /bin/bash

#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2016  Chip Schweiss

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

TOOLS_ROOT=`pwd`

if [ -f /etc/ozmt/config ]; then
    echo "OZMT already configured.  Aborting." 
    exit 1
fi

mkdir -p /etc/ozmt

cat ${TOOLS_ROOT}/install/config.template | sed "s,#TOOLS_ROOT#,${TOOLS_ROOT},g" > /etc/ozmt/config

cat ${TOOLS_ROOT}/install/crontab.root >> /var/spool/cron/crontabs/root

./setup-ozmt-links.sh 

for pool in $(zpool list -H -o name); do
    if [ "$pool" != 'rpool' ]; then
        zfs create ${pool}/zfs_tools
    fi
done
