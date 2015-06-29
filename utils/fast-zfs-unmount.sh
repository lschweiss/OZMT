#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2015  Chip Schweiss

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

logfile="$default_logfile"

report_name="$default_report_name"

zfs_folders="$1"

unmount_zfs_folder="$2"

debug "ZFS unmount $1 $2"

# Collect children
cat $zfs_folders | ${GREP} "^${unmount_zfs_folder}" | ${GREP} -v "^${unmount_zfs_folder}$" > ${TMP}/fast_unmount_zfs.$$

echo "testing ${TMP}/fast_unmount_zfs.$$"

if [ $(cat ${TMP}/fast_unmount_zfs.$$ | wc -l) -gt 0 ]; then
    $TOOLS_ROOT/bin/$os/parallel --will-cite -a ${TMP}/fast_unmount_zfs.$$ ./fast-zfs-unmount.sh $zfs_folders
fi

echo "zfs unmount -f $unmount_zfs_folder"
if [ $? -ne 0 ] ; then 
    warning "Could not unmount $unmount_zfs_folder"
else
    debug "Unmounted $unmount_zfs_folder"
fi
