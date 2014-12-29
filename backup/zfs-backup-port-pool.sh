#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2014  Chip Schweiss

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
. ../zfs-tools-init.sh


# Set defaults

if [ "$connection_port_pool" == "" ]; then
    connection_port_pool=/var/zfs_tools/db/port_pool
fi

if [ "$connection_port_start" == "" ]; then
    connection_port_start=5000
fi

if [ "$connection_port_end" == "" ]; then
    connection_port_end=5200
fi


# Initialized the connection pool

if [ ! -d $connection_port_pool ]; then
    # Assuming this the first time running, initialize our pool
    debug "Connection port pool does not exist.  Creating."
    mkdir -p ${connection_port_pool}/available
    mkdir -p ${connection_port_pool}/inuse

    echo "$connection_port_start" > ${connection_port_pool}/start
    echo "$connection_port_end" > ${connection_port_pool}/end

    current=$connection_port_start
    while [ $current -le $connection_port_end ]; do
        debug "Adding port $current to available pool"
        touch ${connection_port_pool}/available/$current
        current=$(( current + 1 ))
    done
else
    # confirm all 'inuse' ports are alive.   If not return them to the available pool
    ports=`ls -1 ${connection_port_pool}/inuse`
    for port in $ports; do
        
        IFS=";" 
        read -r pid command < "${connection_port_pool}/inuse/${port}" 

        if [[ "$command" == "" || "$(ps -o comm -p $pid |tail -n +2)" != "$command" ]]; then
            # Port usage is dead return to the pool
            rm ${connection_port_pool}/inuse/${port}
            touch ${connection_port_pool}/available/${port}
        fi
    done
fi

# TODO: Detect changes in the conneciton pool size from when it was initialized.  
# Adjust the pool as necessary.
# If the pool shrinks, inuse ports outside the new definitions need to be discarded 
# when finished, not returned to the pool.


get_port () {

    # There is a possible race condition here.  Instead of dealing with a clunky locking mechanism
    # in bash we will grap a port by using the 'mv' command.  If that fails we assume we lost
    # the race and select another port.

    local port=
    while [ "$port" == "" ]; do
        port=`ls -1 ${connection_port_pool}/available| head -1`
        if [ "$port" == "" ]; then
            error "Connection port pool is empty.  Please expand the port pool."
            return 1
        fi
        mv ${connection_port_pool}/available/${port} ${connection_port_pool}/inuse/${port}
        if [ $? -eq 0 ]; then
            # Another process took our port first
            port=
        fi
    done

    echo $port

}


return_port () {

    local port="$1"
    if [ -f "${connection_port_pool}/inuse/${port}" ]; then
        if [[ $port -lt $connection_port_start || $port -gt $connection_port_end ]]; then
            # Port is outside current pool range.  Don't return it.
            rm "${connection_port_pool}/inuse/${port}"
        else
            rm "${connection_port_pool}/inuse/${port}"
            touch ${connection_port_pool}/available/${port}
        fi
        return 0
    else
        error "Failed returning port $port to pool.  The port was not in use."
        return 1
    fi     

}

####
####
##
## This script is meant to be included by local scripts or executed remotely to set up replication
##
####
####

if [ "$1" != "" ]; then
    $1
    exit $?
fi
