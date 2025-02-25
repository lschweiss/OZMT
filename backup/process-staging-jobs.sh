#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012  Chip Schweiss

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

if [ -e /var/run/process-staging-jobs ]; then
    pid=`cat /var/run/process-staging-jobs`
    if [ -e /proc/$pid ]; then
        echo "Previous instance of process-staging-jobs.sh already running." >&2
        echo "Aborting. " >&2
        exit 1
    fi
fi

echo $$ > /var/run/process-staging-jobs
    

stagingjobsfolder="$TOOLS_ROOT/backup/jobs/staging"

stagingjobs=`ls -1 $stagingjobsfolder`

for job in $stagingjobs; do

    # load the job specific variables
    source $stagingjobsfolder/$job

    if [ "$crypt" == "true" ]; then
        copymode="crypt"
    else
        copymode="zfs"
    fi

    $TOOLS_ROOT/backup/copy-snapshots.sh -i -c $copymode -l latest -z "$source_folder" -t "$target_folder"
    echo

done

rm /var/run/process-staging-jobs
