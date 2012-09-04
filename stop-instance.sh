#! /bin/bash 

# stop-instance.sh

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

state=""
stopping=0

while [ "$state" != "stopped" ]; do
    case $state in
        'running')
            ec2-stop-instances ${instanceid} ;;
        'stopping')
            stopping=$(( stopping + 10 ))
            sleep 10
            if [ $stopping -gt 600 ]; then
                echo "Instance did not stop gracefully in 10 minutes.  Stopping forcefully."
                ec2-stop-instances -f ${instanceid}
                stopping=0
            fi ;;
        'pending')
            sleep 10 ;;
    esac

    instance_status=`ec2-describe-instances --show-empty-fields ${instanceid}|grep INSTANCE`
    state=`echo $instance_status|cut -d " " -f 6`

done



