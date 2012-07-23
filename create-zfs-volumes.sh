#! /bin/bash

# Built specifically for the AWS backup server

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
        echo "Adding name tag: ${HOSTNAME}_${awsdev}"
        ec2addtag $volumeid --tag Name="${HOSTNAME}_${awsdev}"
        echo "Attaching volume"
        ec2-attach-volume -d $awsdev -i $instanceid $volumeid
        y=$(( $y + 1 ))
    done
    x=$(( $x + 1 ))
done



