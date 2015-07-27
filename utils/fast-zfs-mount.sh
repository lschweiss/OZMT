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

# fast-zfs-mount.sh mounts zfs folders as fast as possible by calling all
# non-blocking 'zfs mount' commands in parallel

# Requires gnu parallel
# GNU Parallel - The Command-Line Power Tool
# http://www.gnu.org/software/parallel/

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

zfs_folders="$1"

mount_zfs_folder="$2"

debug "fast-zfs-mount $1 $2"

if [ "$DEBUG" == "true" ]; then
    VERBOSE='-v '
else
    VERBOSE=''
fi

mkdir -p ${TMP}/parallel
if [ "$HOME" == "" ];then
    export HOME="${TMP}/parallel"
fi

# Test if this folder is already mounted.  If not, mount it.
case $os in 
    'SunOS')
        /usr/sbin/mount | ${GREP} -q "on $mount_zfs_folder " 
        if [ $? -ne 0 ]; then
            debug "zfs mount ${VERBOSE}${mount_zfs_folder}"
            zfs mount ${VERBOSE}$mount_zfs_folder 2> ${TMP}/zfs_mount_$$
            if [ $? -ne 0 ]; then
                error "fast-zfs-mount.sh: failed to mount $mount_zfs_folder  Children mounts have been skipped." ${TMP}/zfs_mount_$$
                exit 1
            fi
            rm ${TMP}/zfs_mount_$$ 2> /dev/null
        fi
    ;;
    *)
        error "zfs-fast-mount.sh: Unsupported operation system $os"
        exit 1
    ;;
esac

# Export NFS

sharenfs=`zfs get -o value -H sharenfs $mount_zfs_folder`

if [ "$sharenfs" != "off" ]; then
    zfs share $mount_zfs_folder
    if [ $? -ne 0 ]; then
        error "fast-zfs-mount.sh: failed to nfs export $mount_zfs_folder  Children mounts have been skipped." ${TMP}/zfs_mount_$$
        exit 1
    fi
fi
    

# Collect children from full list of folders
cat $zfs_folders | \
    ${GREP} "^${mount_zfs_folder}/" | \
    ${GREP} -v "^${mount_zfs_folder}$" | \
    ${SED} "s,^${mount_zfs_folder}/,," | \
    ${CUT} -d '/' -f 1 | \
    ${SORT} -u | \
    ${SED} -e "s,^,${mount_zfs_folder}/," > ${TMP}/fast_mount_zfs.$$

if [ $(cat ${TMP}/fast_mount_zfs.$$ | wc -l) -gt 0 ]; then
    debug "Launching mount on $mount_zfs_folder children.  ${TMP}/fast_mount_zfs.$$"
    # cat ${TMP}/fast_mount_zfs.$$
    $TOOLS_ROOT/bin/$os/parallel --will-cite --workdir ${TMP}/parallel -a ${TMP}/fast_mount_zfs.$$ ./fast-zfs-mount.sh $zfs_folders
    result=$?
    debug "Children finished mounting on ${mount_zfs_folder}.  ${TMP}/fast_mount_zfs.$$"
fi

rm -f ${TMP}/fast_mount_zfs.$$

exit $result
