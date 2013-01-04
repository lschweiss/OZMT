#! /bin/bash

# rpool-backup.sh: Make a full backup of an rpool to a file

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


# TODO: Collect all pools associated with the rpool

# Generate a snapshot to backup from:

debug "Generating rpool@backup snapshot..."
zfs snapshot -r rpool@backup
zfs snapshot -r syspool@backup


# Copy the rpool to the backup folder
debug "Copying rpool snapshot to $rpool_backup_folder"
zfs send -Rv rpool@backup > ${rpool_backup_folder}/rpool.backup
zfs send -Rv syspool@backup > ${rpool_backup_folder}/syspool.backup

# remove the backup snapshot
debug "Destroying snapshot rpool@backup"
zfs destroy -r rpool@backup
zfs destroy -r syspool@backup
