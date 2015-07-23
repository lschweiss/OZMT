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

# fast-zpool-export.sh is drop in replacement for 'zpool export' and will drastically 
# decrease the time to export a zpool

# Any parameter passed before the pool name will be preserved and passed to zpool export.
# All exported NFS folders will be un-exported in parallel followed by
# "zfs unmount" being call in parallel from children to parrent all the way to the root

# Requires gnu parallel
# Tange (2011): GNU Parallel - The Command-Line Power Tool
# http://www.gnu.org/software/parallel/


cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -lt "$MIN_ARGS" ]; then
    echo "Must supply a pool name to export"
    exit 1
fi

# The last parameter must be the pool name

for last; do : ; done

export_pool="$last"

zpool list $export_pool 1> /dev/null 2> /dev/null
if [ $? -ne 0 ]; then
    warning "Pool \"$export_pool\" does not appear to be imported.  Nothing to do."
    exit 1
fi


##
# exportfs each NFS export
##

debug "Parallel exporting NFS shares for pool $export_pool"

exportfs | ${GREP} "@${export_pool}" | ${AWK} -F " " '{print $2}' | ${SORT} > ${TMP}/zpool_export_nfs_exports.$$

$TOOLS_ROOT/bin/$os/parallel --will-cite -a ${TMP}/zpool_export_nfs_exports.$$ exportfs -u
if [ $? -eq 0 ]; then
    rm -f ${TMP}/zpool_export_nfs_exports.$$
else
    warning "Some NFS exports failed to unmount"
fi


##
# Unmount zfs folders
##

/usr/sbin/zfs list -o mounted,name -r ${export_pool} | ${GREP} "   yes" | \
    ${AWK} -F " " '{print $2}' | \
    ${GREP} -v "^${export_pool}$" > ${TMP}/zpool_export_zfs.$$

./fast-zfs-unmount.sh ${TMP}/zpool_export_zfs.$$ mirpool01
if [ $? -eq 0 ]; then
    #debug "zfs unmount -f ${export_pool}"
    rm -f ${TMP}/zpool_export_zfs.$$ ${TMP}/zpool_export_zfs_roots.$$ ${TMP}/zpool_export_zfs_root_folders.$$
else
    warning "Some ZFS folders failed to unmount"
fi

##
# Export the pool
##

zpool export $@
exit $?
