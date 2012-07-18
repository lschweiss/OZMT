#! /bin/bash -x

# Working one EBS Volume at a time we replace it with a new larger one and wait for the zpool to resilver
# This process could take hours even days as the pool gets bigger so plan accordingly.
# Using raidz1 means redundency is broken troughout this process make sure you have a successful scrub first.

# Four input parameters expected:
# $1 - The instance id
# $2 - The device letter
# $3 - Number of EBS volumes per vdev
# $4 - The new EBS size in GB

# TODO: Confirm all the inputs

instanceid=$1
date=`date +%F`
dev="xvd${2}"
ec2dev="/dev/sd${2}"
volumes=$3
devnum=1
devsize=$4
zpool="ctspool"

mkdir -p /var/log/zfs

logfile="/var/log/zfs/grow-vdev-${dev}_${date}"

function now() {
   date +"%F %r %Z"
}

function log() {
   if [ "$DEBUG" == "true" ]; then
      echo "$(now): ${1}" | tee -a ${logfile}
   else
      echo "$(now): ${1}" >> ${logfile}
   fi
}

while [ $devnum -le $volumes ]; do
   # Create our replacement volume
   device="/dev/${dev}${devnum}"	
	ec2device="${ec2dev}${devnum}"
   log "Creating new volume for: ${device}"
   volumeid=$(ec2-create-volume -z us-east-1d --size $devsize | cut -f2)
   log "Created volume: ${device}"

   # Remove the old device from our pool
   log "Removing ${device} from the pool" 
   zpool offline $zpool $device

   # Detach the old volume
   #   Find the volume name
	oldvolumeid=`cat /tmp/ebs-volumes | grep "TAG" | grep "ZoL-${ec2device}" | cut -f3`
	ec2-detach-volume $oldvolumeid
	
   # Attach the new volume
   log "Attaching the new volume $volumeid to $device"
   ec2-attach-volume -d $ec2device -i $instanceid $volumeid

   # Wait for volume to be attached
 
   attached=1
   log "Waiting for volume $volumeid to be attached."

   while [ "$attached" != "0" ]; do
	ec2-describe-volumes $volumeid | grep -q "attached"
	attached=$?
   done

   log "Volume $volumeid is attached"
 	  
   # Replace the vdev
	zpool replace $zpool ${dev}${devnum}

	# TODO: Wait until we are resilvered
	log "Waiting for resilver to complete..."

	resilver_complete=0
	
	while [ "$resilver_complete" == "0" ]; do
	    sleep 15
	    zpool status ${zpool} | grep -q "action: Wait for the resilver to complete"
	    resilver_complete=$?
	done
	
	#echo -n "Press enter when resilver is complete..."
	#read a
	

	# Sleep so the other process can detect we are resilvered
	sleep 1m

	# Destroy the old volume
	ec2-delete-volume $oldvolumeid

	# Tag the new volume with a Name
	ec2addtag $volumeid --tag Name="ZoL-${ec2device}"

	(( devnum += 1 ))

done


