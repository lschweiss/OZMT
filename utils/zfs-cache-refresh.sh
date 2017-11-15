#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2015  Chip Schweiss

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

. ../zfs-tools-init.sh


#
# Refresh the zfs_cache command's cache on each pool.   Meant to be a background process.
#

pools="$(pools)"


# Build a list of cache directories and mark the caches stale
cache_dirs=
for pool in $pools; do
    cache_dir="/$pool/zfs_tools/var/cache/zfs_cache"
    if [ ! -d $cache_dir ]; then
        continue
    fi
    cache_dirs="/$pool/zfs_tools/var/cache/zfs_cache $cache_dirs"
    touch /$pool/zfs_tools/var/cache/zfs_cache/.cache_stale
done

remote_caches=`ls -1A /var/zfs_tools/cache/zfs_cache | $GREP -v lock`
for remote_cache in $remote_caches; do
    touch /var/zfs_tools/cache/zfs_cache/${remote_cache}/.cache_stale
done


update_cache () {
    local cache_dir="$1"
    local remote="$2"

    debug "Updating cache: $cache_dir"
    
    wait_for_lock "$cache_dir"

    next_cache=`ls -1tA $cache_dir | ${SED} -n -e '/\.cache_stale/,$p' | ${GREP} -v '\.cache_stale' | ${HEAD} -1`
    cache_file="$cache_dir/$next_cache"
    while [ "$next_cache" != "" ]; do
        debug "$next_cache is out of date"
        zfs_command=`head -1 "$cache_file"`
        $remote $zfs_command > ${TMP}/cache_update_$$ 2>/dev/null
        if [ $? -ne 0 ]; then
            # Cache command is no longer valid.  Remove the cache file."
            debug "ZFS command \"$zfs_command\" is not valid.  Removing cache."
            rm -f "$cache_file"
        else
            debug "Updating cache file for \"$zfs_command\""
            echo "$zfs_command" > "$cache_file"
            cat ${TMP}/cache_update_$$ >> "$cache_file"
        fi

        rm -f ${TMP}/cache_update_$$

        next_cache=`ls -1tA $cache_dir | ${SED} -n -e '/\.cache_stale/,$p' | ${GREP} -v '\.cache_stale' | ${HEAD} -1`
        cache_file="$cache_dir/$next_cache"

    done

    release_lock "$cache_dir"

}

# Update all the existing caches

for cache_dir in $cache_dirs; do
    update_cache "$cache_dir" ''
done

for remote_cache in $remote_caches; do
    update_cache "/var/zfs_tools/cache/zfs_cache/${remote_cache}" "$SSH $remote_cache"
done

exit 0


# Old loop

for pool in $pools; do

    debug "Updating cache on pool $pool"

    cache_dir="/$pool/zfs_tools/var/cache/zfs_cache"

    if [ ! -d $cache_dir ]; then
        continue
    fi

    wait_for_lock "$cache_dir"

    next_cache=`ls -1tA $cache_dir | ${SED} -n -e '/\.cache_stale/,$p' | ${GREP} -v '\.cache_stale' | ${HEAD} -1`
    cache_file="$cache_dir/$next_cache"
    while [ "$next_cache" != "" ]; do
        debug "$next_cache is out of date"
        zfs_command=`head -1 "$cache_file"`
        $zfs_command > ${TMP}/cache_update_$$ 2>/dev/null
        if [ $? -ne 0 ]; then
            # Cache command is no longer valid.  Remove the cache file."
            debug "ZFS command \"$zfs_command\" is not valid.  Removing cache." 
            rm -f "$cache_file"
        else
            debug "Updating cache file for \"$zfs_command\""
            echo "$zfs_command" > "$cache_file"
            cat ${TMP}/cache_update_$$ >> "$cache_file"
        fi
        
        rm -f ${TMP}/cache_update_$$

        next_cache=`ls -1tA $cache_dir | ${SED} -n -e '/\.cache_stale/,$p' | ${GREP} -v '\.cache_stale' | ${HEAD} -1`
        cache_file="$cache_dir/$next_cache"

    done

    release_lock "$cache_dir"

done
    
        
    
