# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2016  Chip Schweiss

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
. functions.sh


for pool in $(pools); do
    if [ -d /$pool/zfs_tools/etc/snapshots ]; then
        cd /$pool/zfs_tools/etc/snapshots
        jobs=`find . -type f`
        for job in $jobs; do
            file=$( basename $job )
            dir=$( dirname $job )
    
            zfs_folder="$( jobtofolder $file )"
    
            snaptype=$( basename $dir)
            count=`cat $job`
        
            echo "$zfs_folder: ${snaptype}|${count}"

            add_mod_snap_job $zfs_folder "${snaptype}/${count}"

        done
    fi
done
