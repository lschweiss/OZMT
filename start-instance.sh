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

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ./zfs-tools-init.sh

if [ "$crypt" == "true" ]; then
    echo -n "Enter encryption key: "
    read -s key
    echo
    # Confirm the key
    check_key
fi


get_ec2_state () {
    instance_status=`ec2-describe-instances --show-empty-fields ${instanceid} 2>/dev/null |grep INSTANCE`
    state=`echo $instance_status|cut -d " " -f 6`
}

get_ec2_state

if [ "$state" == "running" ]; then
    echo "EC2 instance start, but the instance is already running." >&2
    exit 1
fi

while [ "$state" != "running" ]; do
    case $state in
        'stopped') 
            echo "Starting instance ${instanceid}"
            ec2-start-instances ${instanceid} 2>/dev/null ;;
        'stopping')
            sleep 10 ;;
        'pending')
            sleep 10 ;;
    esac

    get_ec2_state

done

instance_ip=`echo $instance_status|cut -d " " -f 17`

# wait for DNS to update

resolved_dns=`host $instance_dns|cut -d " " -f 4`

while [ "$resolved_dns" != "$instance_ip" ]; do
    sleep 30
    # Kill Name Service Cache Daemon
    nscd_pid=`ps -o fname,pid -e |grep nscd|awk -F " " '{print $2}'`
    if [ $nscd_pid -ne 0 ]; then
        kill -15 $nscd_pid
    fi
    resolved_dns=`host $instance_dns|cut -d " " -f 4`
done


if [ "$crypt" == "true" ]; then
    echo $key | ./setup-crypto.sh
fi

$remote mountall



