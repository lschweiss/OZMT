#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2015  Chip Schweiss

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

locate_snap () {
    EXPECTED_ARGS=2
    if [ "$#" -lt "$EXPECTED_ARGS" ]; then
        echo "Usage: `basename $0` {snapshot_dir} {date} [preferred_tag]"
        echo "  {date} must be of the same format as in snapshot folder name"
        echo "  [preferred_tag] will be a text match"
        return 1
    fi

    snap=""
    path=$1
    date=$2
    preferred_tag=$3

    if [ -d $path ]; then
        if [ "$#" -eq "3" ]; then
            snap=`ls -1 $path|${GREP} $date|${GREP} $preferred_tag`
        fi
        if [ "$snap" == "" ]; then
            snap=`ls -1 $path|${GREP} $date`
        fi
    else
        error "locate_snap: Directory $path not found."
        return 1
    fi

    if [ "${snap}" == "" ]; then
        error "locate_snap: Snapshot for $date on path $path not found."
        return 1
    fi

    echo $snap
    return 0
}
