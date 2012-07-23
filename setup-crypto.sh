#! /bin/bash

# install packages
# apt-get install cryptsetup

# Make sure the modules are loaded:
# echo aes-x86_64 >> /etc/modules
# echo dm_mod >> /etc/modules
# echo dm_crypt >> /etc/modules

. ./zfs-tools-init.sh

echo -n "Enter encryption key: "
read -s key

x=1
while [ $x -le $vdevs ]; do
    y=1
    while [ $y -le $devices ]; do
        cryptname=`echo ${cryptname[$x]} | cut -d " " -f $y`
        cryptdev=`echo ${cryptdev[$x]} | cut -d " " -f $y`
        phydev=`echo ${phydev[$x]} | cut -d " " -f $y`
            echo "Creating encrypted /dev/mapper device: $cryptname"
            echo $key | cryptsetup --key-file - create $cryptname $phydev
            # TODO: Trap errors
        y=$(( $y + 1 ))
    done
    x=$(( $x + 1 ))
done
