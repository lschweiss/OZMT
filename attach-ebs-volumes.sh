#! /bin/bash

# attach-ebs-volumes.sh
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


# Re-attach ebs volumes to our instance

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ./zfs-tools-init.sh

# Create our starting point reference file
echo -n "Gathering information..."
ec2-describe-volumes --show-empty-fields > /tmp/ebs-volumes_$$
echo "Done."

volumeids=`cat /tmp/ebs-volumes_$$ | $grep "TAG" | $grep "${instance_hostname}_/dev/sd" | $cut -f 3`

for volumeid in $volumeids; do
    # Get the device attachment point
    awsdev=`cat /tmp/ebs-volumes_$$ | $grep "TAG" | $grep "$volumeid" | $cut -f 5 | $grep -o -E "sd[f-p][0-9]+"`
    awsdev="/dev/${awsdev}"
    
    echo "Attaching volume $volumeid to $awsdev on $instanceid" 
    ec2-attach-volume -v $volumeid -i $instanceid -d $awsdev &

done


