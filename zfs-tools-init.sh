#! /bin/bash

# zfs-tools-init.sh
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

. ./zfs-config.sh


volumes=`expr $vdevs \* $devices`

# Define device groups, crypt groups

alphabet='abcdefghijklmnopqrstuvwxyz'

first_index=`expr index "$alphabet" $dev_first_letter`

x=0

while [ $x -lt $vdevs ]; do
    # Bash uses 0 base indexing
    index=`expr $x + $first_index - 1`
    d=$(( $x + 1 ))
    dev_letter=${alphabet:${index}:1}
    y=1
    awsdev[$d]=""
    phydev[$d]=""
    devname[$d]=""
    cryptdev[$d]=""
    cryptname[$d]=""
    while [ $y -le $devices ]; do
        awsdev[$d]="${awsdev[$d]}/dev/sd${dev_letter}${y} "
        phydev[$d]="${phydev[$d]}/dev/xvd${dev_letter}${y} "
        devname[$d]="${devname[$d]}xvd${dev_letter}${y} "
        cryptdev[$d]="${cryptdev[$d]}/dev/mapper/crypt${dev_letter}${y} "
        cryptname[$d]="${cryptname[$d]}crypt${dev_letter}${y} "
        y=$(( $y + 1 ))
    done
    x=$(( $x + 1 ))
done

function now() {
    date +"%F %r %Z"
}

