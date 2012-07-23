#! /bin/bash

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

#x=1
#while [ $x -le $vdevs ]; do
#    echo "${awsdev[$x]}"
#    echo "${phydev[$x]}"
#    echo "${devname[$x]}"
#    echo "${cryptdev[$x]}"
#    echo "${cryptname[$x]}"
#    x=$(( $x + 1 ))
#done

    
#perl -e "for\$i(\"f\"..\"j\"){for\$j(1..8){print\"/dev/sd\$i\$j\\n\"}}"
