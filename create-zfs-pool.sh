#! /bin/bash 

# create-zfs-pool.sh
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

. ./zfs-tools-init.sh

if [ "$crypt" == "true" ]; then
    echo -n "Enter encryption key: "
    read -s key
    echo
fi

echo $key|sha512sum|cut -d " " -f 1 > ./${zfspool}_key.sha512

x=1
raidzlist=""
while [ $x -le $vdevs ]; do
    raidzlist="${raidzlist} ${raidz}"
    y=1
    while [ $y -le $devices ]; do
        cryptname=`echo ${cryptname[$x]} | cut -d " " -f $y`
        cryptdev=`echo ${cryptdev[$x]} | cut -d " " -f $y`
        phydev=`echo ${phydev[$x]} | cut -d " " -f $y`
        if [ "$crypt" == "true" ]; then
            raidzlist="${raidzlist} ${cryptdev}"
            echo "Creating encrypted /dev/mapper device: $cryptname"
            echo $key | $remote cryptsetup --key-file - create $cryptname $phydev
            # TODO: Trap errors
        else
            raidzlist="${raidzlist} ${physdev}"
        fi
        y=$(( $y + 1 ))
    done
    x=$(( $x + 1 ))
done

    $remote zpool create -o ashift=12 -o autoexpand=on -o listsnaps=on $zfspool $raidzlist
