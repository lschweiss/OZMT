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

export_pool="$1"

zpool list $export_pool 1> /dev/null 2> /dev/null

if [ $? -ne 0 ]; then
    warning "Pool $export_pool does not appear to be imported.  Nothing to do."
    exit 1
fi


##
# exportfs each NFS export
##

exportfs | ${GREP} "@${export_pool}" | ${AWK} -F " " '{print $2}' | ${SORT} > ${TMP}/zpool_export_nfs_exports.$$

$TOOLS_ROOT/bin/$os/parallel --will-cite -a ${TMP}/zpool_export_nfs_exports.$$ echo # exportfs -u

if [ $? -eq 0 ]; then
    echo "Success"
#    rm -f ${TMP}/zpool_export_nfs_exports.$$
else
    warning "Some NFS exports failed to unmount"
fi



##
# Unmount zfs folders
##

echo "${GREP} ${AWK} ${GREP}"


/usr/sbin/zfs list -o mounted,name -r ${export_pool} | ${GREP} "   yes" | \
    ${AWK} -F " " '{print $2}' | \
    ${GREP} -v "^${export_pool}$" > ${TMP}/zpool_export_zfs.$$

cat ${TMP}/zpool_export_zfs.$$ | cut -d '/' -f 2 | ${AWK} '!a[$0]++' > ${TMP}/zpool_export_zfs_roots.$$

$TOOLS_ROOT/bin/$os/parallel --will-cite -a ${TMP}/zpool_export_zfs_roots.$$ ./fast-zfs-unmount.sh ${TMP}/zpool_export_zfs.$$ 

if [ $? -eq 0 ]; then
    # zfs unmount -f ${export_pool}
    echo "Success"
    #    rm -f ${TMP}/zpool_export_zfs.$$ ${TMP}/zpool_export_zfs_roots.$$
else
    warning "Some ZFS folders failed to unmount"
fi
