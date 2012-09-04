#! /bin/bash

# grow-zfs-pool.sh
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
. ./zfs-tools-init.sh

if [ "$crypt" == "true" ]; then
    echo -n "Enter encryption key: "
    read -s key
    echo
    # Confirm the key
    check_key
fi

function log() {
    if [ "$DEBUG" == "true" ]; then
        echo "$(now): ${1}" | tee -a ${2}
    else
        echo "$(now): ${1}" >> ${2}
    fi
}

grow-vdev () {
    # Working one EBS Volume at a time we replace it with a new larger one and wait for the zpool to resilver
    
    # One input parameters expected:
    # $1 - Number of the vdev we are working on
    # $2 - The device number in the vdev we are replacing
    # $3 - The file to touch when complete   
 
    local vdevnum="$1"
    local devnum="$2"
    local complete_file="$3"

    local date=`date +%F`
    local dev="xvd${1}"
    local phydev=`echo ${phydev[$vdevnum]} | cut -d " " -f $devnum`
    local awsdev=`echo ${awsdev[$vdevnum]} | cut -d " " -f $devnum`
    local devname=`echo ${devname[$vdevnum]} | cut -d " " -f $devnum`
    local cryptname=`echo ${cryptname[$vdevnum]} | cut -d " " -f $devnum`

    local zname=""

    local attached=1
    local volumeid=""
    local oldvolumeid=""
    local volumestat=""
    
    mkdir -p /var/log/zfs
    
    local logfile="/var/log/zfs/grow-vdev-${dev}_${date}"
    
    if [ "$crypt" == "true" ]; then
        zname="$cryptname"
    else
        zname="$devname"
    fi
    
    log "Creating new EBS volume for: ${phydev}" "$logfile"
    volumeid=$(ec2-create-volume -z $zone --size $devsize | cut -f2)
    log "Created volume: ${phydev}" "$logfile"

    # Tag the new volume with a Name
    ec2addtag $volumeid --tag Name="${instance_hostname}_${awsdev}" &

    # Remove the old device from our pool
    log "Removing ${zname} from the pool" "$logfile"
    $remote zpool offline $ec2_zfspool $zname

    if [ "$crypt" == "true" ]; then
        $remote cryptsetup remove $cryptname
    fi

    # Detach the old volume
    #   Find the volume name
    oldvolumeid=`cat /tmp/ebs-volumes | grep "TAG" | grep "${instance_hostname}_${awsdev}" | cut -f3`
    log "Detaching old EBS volume $oldvolumeid from ${awsdev}." "$logfile"
    ec2-detach-volume $oldvolumeid

    # Wait for status to be detached
    volumestat=""
    while [ "$volumestat" != "available" ]; do
        volumestat=`ec2-describe-volumes --show-empty-fields $oldvolumeid | cut -f 6`
    done

    # Destroy the old volume
    ec2-delete-volume $oldvolumeid &


    # Attach the new volume
    log "Attaching the new volume $volumeid to $awsdev" "$logfile"
    ec2-attach-volume -d $awsdev -i $instanceid $volumeid

    # Wait for volume to be attached

    attached=1
    log "Waiting for volume $volumeid to be attached." "$logfile"

    while [ "$attached" != "0" ]; do
        ec2-describe-volumes $volumeid | grep -q "attached"
        attached=$?
    done

    log "Volume $volumeid is attached" "$logfile"

    if [ "$crypt" == "true" ]; then
        echo $key | $remote cryptsetup --key-file - create $cryptname $phydev
    fi

    # Replace the vdev
    $remote zpool replace $ec2_zfspool $zname

    # Notify calling process we are done

    touch $complete_file
}

# Create our starting point reference file
echo -n "Gathering information..."
ec2-describe-volumes --show-empty-fields > /tmp/ebs-volumes
echo "Done."

# Remove any remaining completion files from a previous run
rm -f /tmp/grow_vdev_*

y=1
while [ $y -le $devices ]; do
    x=1
    while [ $x -le $vdevs ]; do
        grow-vdev $x $y /tmp/grow_vdev_$$_${x}_${y} &
        x=$(( $x + 1 ))
    done
    
        # Wait for all complete files to be created
        devices_replaced=0
        while [ $devices_replaced -ne $vdevs ]; do
            devices_replaced=`ls -1 /tmp/grow_vdev_$$_*_$y 2>/dev/null|wc -l`
            sleep 5
        done
    
        # Wait for resilver to complete
        resilver_complete=0
        echo "Waiting for resilver to complete."
        while [ "$resilver_complete" -eq "0" ]; do
            sleep 5
            $remote zpool status ${ec2_zfspool} | grep -q "action: Wait for the resilver to complete"
            resilver_complete=$?
            # TODO: Add check that "status: ONLINE"

        done
        echo "Resilver complete" 
    
    y=$(( $y + 1 ))
done

