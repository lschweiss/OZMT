#! /bin/bash

# zfs-tools-init.sh
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

if [ -f /etc/zfs-tools-config ]; then
    . /etc/zfs-tools-config
fi

if [ -f /etc/sysconfig/zfs-tools-config ]; then
    . /etc/sysconfig/zfs-tools-config
else 
    if [ -f /etc/sysconfig/zfs-config ]; then 
        . /etc/sysconfig/zfs-config
    fi
fi

if [ -f /root/zfs-config.sh ]; then
    . /root/zfs-config.sh 
else 
    if [ -f ./zfs-config.sh ]; then
        . ./zfs-config.sh 
    fi 
fi 

_DEBUG="on"
function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

. $TOOLS_ROOT/ansi-color-0.6/color_functions.sh

if [ "$ec2_backup" == "true" ]; then

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

fi

if [ "x$default_report_name" == "x" ]; then
    default_report_name="default"
fi

. $TOOLS_ROOT/reporting/reporting_functions.sh

now() {
    date +"%F %r %Z"
}

check_key () {

# confirm the key
poolkey=`cat ${ec2_zfspool}_key.sha512`
sha512=`echo $key|sha512sum|cut -d " " -f 1`

if [ "$poolkey" != "$sha512" ]; then
   echo "Invalid encryption key for ${ec2_zfspool}!"
   exit 1
else
   echo "Key is valid."
fi

}


####
#
# Conversions
#
####

tobytes () {
    awk '{ ex = index("KMG", substr($1, length($1)))
           val = substr($1, 0, length($1))
           prod = val * 10^(ex * 3)
           sum += prod
         }
         END {print sum}'
}

bytestohuman () {
    if [ $1 -gt 1099511627776 ]; then
        echo -n $(echo "scale=3;$1/1099511627776"|bc)TiB
        return
    fi

    if [ $1 -gt 1073741824 ]; then
        echo -n $(echo "scale=3;$1/1073741824"|bc)GiB
        return
    fi

    if [ $1 -gt 1048576 ]; then
        echo -n $(echo "scale=3;$1/1048576"|bc)MiB
        return
    fi

    if [ $1 -gt 1024 ]; then
        echo -n $(echo "scale=3;$1/1024"|bc)KiB
        return
    fi

    echo "$1 bytes"

}
