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

MKDIR ${TMP}/import
mkdir -p /var/ozmt/zfscache

#export DEBUG="true"

# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -lt "$MIN_ARGS" ]; then
    echo "Must supply a pool name to import"
    exit 1
fi

# The last parameter must be the pool name

for last; do : ; done

import_pool="$last"

[ -f /var/ozmt/zfscache/${import_pool}.save ] && cp /var/ozmt/zfscache/${import_pool}.save /var/ozmt/zfscache/${import_pool}

cachefile="-o cachefile=/var/ozmt/zfscache/$import_pool"

zpool list $import_pool 1> /dev/null 2> /dev/null
if [ $? -ne 0 ]; then
    # Error code 134 is a core dump cause by bad symlinks in /dev/rdsk
    # Repeatedly trying will get a successful run.
    result=134
    while [ $result -eq 134 ]; do
        zpool import -N $cachefile $@ 
        result=$?
        [ -f core ] && rm core
    done
else
    warning "Pool is already imported: $import_pool"
    exit 1
fi

zpool list $import_pool 1> /dev/null 2> /dev/null
if [ $? -ne 0 ]; then
    warning "Pool \"$import_pool\" does not appear to be imported.  Aborting."
    exit 1
fi

# Save the cachefile
cp /var/ozmt/zfscache/${import_pool} /var/ozmt/zfscache/${import_pool}.save

##
# mount zfs folders
##

# Mount zfs_tools first
zfs mount ${import_pool}
[ -d /${import_pool}/zfs_tools ] && rm -rf /${import_pool}/zfs_tools
zfs mount ${import_pool}/zfs_tools 1>/dev/null 2>/dev/null && rm -rf /${import_pool}/zfs_tools/var/spool/snapshot

# List unmounted folders
/usr/sbin/zfs list -o mounted,name -r ${import_pool} | ${GREP} "   no" | \
    ${AWK} -F " " '{print $2}' | \
    ${GREP} -v "^${import_pool}$" > ${TMP}/import/zpool_import_zfs.$$

./fast-zfs-mount.sh ${TMP}/import/zpool_import_zfs.$$ ${import_pool}
result=$?
if [ $result -eq 0 ]; then
    rm -f ${TMP}/import/zpool_import_zfs.$$ ${TMP}/import/zpool_import_zfs_roots.$$ ${TMP}/import/zpool_import_zfs_root_folders.$$
else
    warning "Some ZFS folders failed to mount"
    exit $result
fi


##
# Start vIPs
##

${TOOLS_ROOT}/vip/vip-trigger.sh start ${import_pool}

##
# Start Samba
##

export BACKGROUND='true'

${TOOLS_ROOT}/samba/samba-service.sh start ${import_pool}

exit 0
