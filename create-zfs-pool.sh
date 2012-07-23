#! /bin/bash 

. ./zfs-tools-init.sh

# TODO: Automate the device name creation

if [ "$crypt" == "true" ]; then
    echo -n "Enter encryption key: "
    read -s key
    echo
fi

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
            echo $key | cryptsetup --key-file - create $cryptname $phydev
            # TODO: Trap errors
        else
            raidzlist="${raidzlist} ${physdev}"
        fi
        y=$(( $y + 1 ))
    done
    x=$(( $x + 1 ))
done

zpool create -o ashift=12 -o autoexpand=on -o listsnaps=on $zfspool $raidzlist
