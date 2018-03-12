#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2018  Chip Schweiss

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


usage_report () {

    local pool="$1"

    
    # Build the email report
   

    # Summary report
    zfs list -d2 -o name,used $pool > ${TMP}.usage_$pool
    # Detailed report
    echo >> ${TMP}.usage_$pool
    zfs list -o name,used,avail,refer,compressratio,logicalused,quota,refquota $pool >> ${TMP}.usage_$pool


    subject="ZFS usage report $pool"
    
    # Send the report 
    if [ "$to" != "" ]; then
        ./send_email.sh -s "$subject" -f "${TMP}.usage_$pool" -r "$email_to" $cc_list $email_bcc
    fi
    

}



pools="$(pools)"

for pool in $pools; do

    usage_report "$pool"

done
