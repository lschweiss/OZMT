#! /bin/bash

# zfs-tools-init.sh
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

# Search all the historical places the config has been kept

##
#
# Only run init once
if [[ "$ozmt_init" != 'true' || "$FORCE_INIT" == 'true' ]]; then
#
##

if [ -f /etc/ozmt/config ]; then
    source /etc/ozmt/config
else
    # All other locations are depricated at the release of OZMT:
    if [ -f /etc/zfs-tools-config ]; then
        source /etc/zfs-tools-config
    fi
    
    if [ -f /etc/sysconfig/zfs-tools-config ]; then
        source /etc/sysconfig/zfs-tools-config
    else 
        if [ -f /etc/sysconfig/zfs-config ]; then 
            source /etc/sysconfig/zfs-config
        fi
    fi
    
    if [ -f /root/zfs-config.sh ]; then
        source /root/zfs-config.sh 
    else 
        if [ -f ./zfs-config.sh ]; then
            source ./zfs-config.sh 
        fi 
    fi 
    
    if [ ! -d /etc/ozmt ]; then
        mkdir -p /etc/ozmt
        if [ -f /root/zfs-config.sh ]; then
            mv /root/zfs-config.sh /etc/ozmt/config
            echo "# moved to /etc/ozmt/config" > /root/zfs-config.sh
        fi
    fi
fi

source $TOOLS_ROOT/utils/ozmt-full-init.sh

##
#
fi # Init only once
#
##
