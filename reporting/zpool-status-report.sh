#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2022  Chip Schweiss

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

logfile="$default_logfile"
report_name="$default_report_name"

status_report () {

    local pool="$1"
    local mycache="/var/zfs_tools/cache/zpool-status"
    local state=
    local alert=
    
    # Build the email report

    
   

    debug "Generating status report for pool ${pool}"

    MKDIR $mycache

    ozmt-zpool-status.sh ${pool} > ${mycache}/${pool}.now

    if [ ! -f ${mycache}/${pool}.previous ]; then
        debug "No previous pool status.  Setting."
        cp ${mycache}/${pool}.now ${mycache}/${pool}.previous
        return 0
    else
        diff -q ${mycache}/${pool}.now ${mycache}/${pool}.previous
        if [ $? -ne 0 ]; then
            debug "zpool status for $pool has changed.  Emailing report."
            state=`cat ${mycache}/${pool}.now | $GREP " state:" | $AWK -F ": " '{print $2}'`
            if [ "$state" != 'ONLINE' ]; then
                alert="ERROR"
            else
                alert="NOTICE"
            fi

            subject="${alert}: zpool status for $pool on $HOSTNAME, state: $state"
            ./send_email.sh -s "$subject" -f "${mycache}/${pool}.now" -r "$email_to"
            cp ${mycache}/${pool}.now ${mycache}/${pool}.previous
        else
            return 0
        fi
    fi        

}



pools="$(pools)"

for pool in ${pools}; do

    is_mounted $pool || continue
    status_report "${pool}"

done
