#! /bin/bash

# setup-swap.sh
#
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

# Built specifically for the AWS backup server
# This process could take hours even days as the pool gets bigger so plan accordingly.
# Using raidz1 means redundency is broken troughout this process make sure you have a successful scrub first.

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

parted -- /dev/xvdb unit MB mklabel msdos mkpart primary linux-swap 1 8192
parted -- /dev/xvdb unit MB mkpart primary ext4 8192 -0

mkfs.ext4 /dev/xvdb2

mkdir -p /data/instancestore

mount /dev/xvdb2 /data/instancestore

mkswap /dev/xvdb1
swapon /dev/xvdb1
