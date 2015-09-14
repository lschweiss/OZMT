#! /bin/bash

# disable-network.sh
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


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

. ../zfs-tools-init.sh


show_usage () {
    echo
    echo "Usage: $0 {interface}"
    echo "  {interface}   Name of the network interface to activate.  Must be a physical interface or defined in \$interface_definition"
    echo "                \$interface_definition currently set to: $interface_definition"
    echo ""
    exit 1
}


# Minimum number of arguments needed by this program
MIN_ARGS=1

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

if [ -f $os/interface-functions.sh ]; then
    source $os/interface-functions.sh
else
    error "disable-network.sh: unsupported OS: $os"
    exit 1
fi

interface="$1"
override_persistent="$2"

if [ "${interface_definition["$interface"]}" == '' ]; then
    if physical_if $interface; then
        deactivate_if $interface $override_persistent
    else
        error "disable-network.sh: Unknown interface $interface $override_persistent"
        exit 1
    fi
else
    deactivate_if $interface $override_persistent
fi


    
