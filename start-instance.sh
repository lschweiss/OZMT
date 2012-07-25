#! /bin/bash

# start-instance.sh

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

. ./zfs-config.sh

if [ "$crypt" == "true" ]; then
    echo -n "Enter encryption key: "
    read -s key
    echo
    # Confirm the key
    check_key
fi

state=""

while [ "$state" != "running" ]; do
    case $state in
        'stopped') 
            ec2-start-instances ${instanceid} ;;
        'stopping')
            sleep 10 ;;
        'running')
            exit 0 ;;
        'pending')
            sleep 10 ;;
    esac

    instance_status=`ec2-describe-instances --show-empty-fields ${instanceid}|grep INSTANCE`
    state=`echo $instance_status|cut -f 6`

done

instance_ip=`echo $instance_status|cut -f 17`

# wait for DNS to update

resolved_dns=`host $instance_dns|cut -d " " -f 4`

while [ "$resolved_dns" != "$instance_ip" ]; do
    sleep 30
    resolved_dns=`host $instance_dns|cut -d " " -f 4`
done


if [ "$crypt" == "true" ]; then
    echo $key | ./setup-crypto.sh
fi



