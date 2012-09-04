#! /bin/bash

# create-zfs-volumes.sh
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


cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ./zfs-tools-init.sh

x=1
while [ $x -le $vdevs ]; do
    y=1
    while [ $y -le $devices ]; do
        physdev=`echo ${physdev[$x]} | cut -d " " -f $y`
        awsdev=`echo ${awsdev[$x]} | cut -d " " -f $y`
        echo "Creating volume ${awsdev}"
        volumeid=$(ec2-create-volume -z $zone --size $devsize | cut -f2)
        echo "$i: created  $volumeid"
        echo "Adding name tag: ${instance_hostname}_${awsdev}"
        ec2addtag $volumeid --tag Name="${instance_hostname}_${awsdev}" &
        echo "Attaching volume"
        ec2-attach-volume -d $awsdev -i $instanceid $volumeid &
        y=$(( $y + 1 ))
    done
    x=$(( $x + 1 ))
done



