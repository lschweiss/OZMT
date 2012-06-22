#! /bin/bash

# Built specifically for the CTS backup server

instanceid="i-1a501b63"

vdevs=5
devices=8
devsize=1

volumes=40 # vdevs X devices

devices=$(perl -e 'for$i("f".."j"){for$j(1..8){print"/dev/sd$i$j\n"}}')

devicearray=($devices)
volumeids=
i=1

while [ $i -le $volumes ]; do
  echo "Creating volume #${i}"
  volumeid=$(ec2-create-volume -z us-east-1d --size $devsize | cut -f2)
  echo "$i: created  $volumeid"
  device=${devicearray[$(($i-1))]}
  echo "Adding name tag: ZoL-${device}"
  ec2addtag $volumeid --tag Name="ZoL-${device}"
  echo "Attaching volume"
  ec2-attach-volume -d $device -i $instanceid $volumeid
  volumeids="$volumeids $volumeid"
  let i=i+1
done
echo "volumeids='$volumeids'"

