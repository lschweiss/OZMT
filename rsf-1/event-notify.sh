#! /bin/bash

# event-notify.sh
#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2015  Chip Schweiss

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

date >> ~/rsf-event-notify
echo "$@" >> ~/rsf-event-notify
echo >> ~/rsf-event-notify

real_event_notifier="/opt/HAC/RSF-1/bin/real_event_notifier"

match()
{
    case "$1" in
        $2) return 0 ;;
    esac
    return 1
}

# Setup binary paths without calling zfs_tools_init.sh

# Skip disk heartbeats
match "$*" "*RSF_HEARTBEAT*type=disc*" && exit 0

# OZMT events that require action

if [ "$1" == "LOG_INFO" ]; then
    case "$2" in
        "RSF_NETIF_UP") 
            # vIP has been triggered to start on a pool
            cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
            . ../zfs-tools-init.sh
            vip=`echo $5| ${CUT} -d '=' -f 2`
            service=`cat /opt/HAC/RSF-1/etc/config | ${GREP} "^SERVICE" | ${GREP} "${vip}" | ${CUT} -d ' ' -f 2`
            echo "Activating VIPs and samba for $service"
            $TOOLS_ROOT/vip/vip-trigger.sh start $service
            $TOOLS_ROOT/samba/samba-service.sh start $service &
            ;;
        "RSF_NETIF_DOWN")
            # vIP has been triggered to stop on a pool
            cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
            . ../zfs-tools-init.sh
            vip=`echo $5| ${CUT} -d '=' -f 2`
            service=`cat /opt/HAC/RSF-1/etc/config | ${GREP} "^SERVICE" | ${GREP} "${vip}" | ${CUT} -d ' ' -f 2`
            echo "Deactivating VIPs and samba for $service"
            $TOOLS_ROOT/vip/vip-trigger.sh stop $service
            $TOOLS_ROOT/samba/samba-service.sh stop $service &
            ;;
    esac
fi


exec "$real_event_notifier" "$@"
~
