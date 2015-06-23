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

match "$*" "*RSF_HEARTBEAT*type=disc*" && exit 0
exec "$real_event_notifier" "$@"
~
