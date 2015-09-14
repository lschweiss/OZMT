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

# fast-zpool-import.sh is drop in replacement for 'zpool import' and will drastically 
# decrease the time to import a zpool

# Any parameter passed before the pool name will be preserved and passed to zpool import.
# All imported NFS folders will be mounted in parallel followed by
# "zfs mount" being called in parallel from the root trough the children

# Requires gnu parallel
# GNU Parallel - The Command-Line Power Tool
# http://www.gnu.org/software/parallel/


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

. ../zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

export DEBUG="true"

# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -lt "$MIN_ARGS" ]; then
    echo "Must supply a pool name to import"
    exit 1
fi

# The last parameter must be the pool name

for last; do : ; done

import_pool="$last"

zpool import -N $@ 
result=$?

zpool list $import_pool 1> /dev/null 2> /dev/null
if [ $? -ne 0 ]; then
    warning "Pool \"$import_pool\" does not appear to be imported.  Aborting."
    exit 1
fi


# mount zfs folders
##

/usr/sbin/zfs list -o mounted,name -r ${import_pool} | ${GREP} "   no" | \
    ${AWK} -F " " '{print $2}' | \
    ${GREP} -v "^${import_pool}$" > ${TMP}/zpool_import_zfs.$$

./fast-zfs-mount.sh ${TMP}/zpool_import_zfs.$$ ${import_pool}
result=$?
if [ $result -eq 0 ]; then
    rm -f ${TMP}/zpool_import_zfs.$$ ${TMP}/zpool_import_zfs_roots.$$ ${TMP}/zpool_import_zfs_root_folders.$$
else
    warning "Some ZFS folders failed to mount"
    exit $result
fi

exit 0
