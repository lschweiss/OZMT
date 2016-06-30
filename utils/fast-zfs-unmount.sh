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

# Requires gnu parallel
# GNU Parallel - The Command-Line Power Tool
# http://www.gnu.org/software/parallel/

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

zfs_folders="$1"

unmount_zfs_folder="$2"

mkdir -p ${TMP}/parallel
if [ "$HOME" == "" ];then
    export HOME="${TMP}/parallel"
fi

#export DEBUG="true"

debug "fast-zfs-unmount $1 $2"

# Collect children from full list of folders

cat $zfs_folders | \
    ${GREP} "^${unmount_zfs_folder}/" | \
    ${GREP} -v "^${unmount_zfs_folder}$" | \
    ${SED} "s,^${unmount_zfs_folder}/,," | \
    ${CUT} -d '/' -f 1 | \
    ${SORT} -u | \
    ${SED} -e "s,^,${unmount_zfs_folder}/," > ${TMP}/fast_unmount_zfs.$$

if [ $(cat ${TMP}/fast_unmount_zfs.$$ | wc -l) -gt 0 ]; then
    debug "Launching unmount on $unmount_zfs_folder children.  ${TMP}/fast_unmount_zfs.$$"
    # cat ${TMP}/fast_unmount_zfs.$$
    $TOOLS_ROOT/bin/$os/parallel --will-cite --workdir ${TMP}/parallel -a ${TMP}/fast_unmount_zfs.$$ ./fast-zfs-unmount.sh $zfs_folders
    debug "Children finished unmounting on ${unmount_zfs_folder}.  ${TMP}/fast_unmount_zfs.$$"
fi

# Unmount the zfs folder
mounted=`zfs get -o value -H mounted $unmount_zfs_folder`

if [ "$mounted" == 'yes' ]; then
    mountpoint=`zfs get -H -o value mountpoint $unmount_zfs_folder`
    ${TIMEOUT} 30s umount -f $mountpoint 2>&1
    result=$?
else
    result=0
fi

if [ $result -ne 0 ]; then
    # Check if any processes have open files, if so kill them
    pids=`${LSOF} -t $mountpoint`
    for pid in $pids; do
        echo "Killing pid: $pid"
        kill -9 $pid
    done

    ${TIMEOUT} 10s umount -f $mountpoint 2>&1
    result=$?

    if [ $result -ne 0 ]; then
        warning "umount -f $mountpoint failed, ERR $result  Collecting truss." 
        cat ${TMP}/zfs_unmount_$$.txt
        truss umount -f $mountpoint 2>&1 | ${TOOLS_ROOT}/3rdparty/moreutils-0.57/ts > ${TMP}/zfs_unmount_$$.txt
        result=$?
        cat ${TMP}/zfs_unmount_$$.txt
        warning "Truss output of umount -f $unmount_zfs_folder Result: $result" ${TMP}/zfs_unmount_$$.txt
    fi
    
fi

rm ${TMP}/zfs_unmount_$$.txt 2> /dev/null
 
if [ $result -ne 0 ] ; then 
    warning "Could not unmount $unmount_zfs_folder"
else
    debug "Unmounted $unmount_zfs_folder"
fi

rm -f ${TMP}/fast_unmount_zfs.$$
