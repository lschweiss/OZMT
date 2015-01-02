#! /bin/bash 

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
. ../zfs-tools-init.sh

if [ "x$default_report_title" == "x" ]; then
    default_report_title="zfs_tools"
fi

report_name="$default_report_name"

index=1

if [ -d "$report_spool" ]; then

    for report_path in ${report_spool}/*/; do

        report=`echo "$report_path"|${AWK} -F "/" '{print $(NF-1)}'`

        if [ -f "${report_path}report_pending" ]; then
            report_pending="${TMP}/send_report_$report_$$_${index}"
            index=$(( index + 1 ))

            # Move the report to a temporary file to avoid race conditions
            mv "${report_path}report_pending" "$report_pending"

            if [ -f "${report_path}report_attachments" ]; then
                mv "${report_path}report_attachments" "${report_pending}_attachments"
            fi
        
            source "${report_path}report_level"
        
            rm "${report_path}report_level"
    
            email_subject="${email_prefix} $report report"
        
            debug "send_report: Sending $report"
        
            if [[ "x$report_level" != "x" && "$report_level" -ge 3 ]]; then
                email_subject="ERROR: $email_subject"
                ./send_email.sh -f "$report_pending" -s "$email_subject" -r "$email_to" -i "high"
            else 
                ./send_email.sh -f "$report_pending" -s "$email_subject" -r "$email_to"
            fi
    
            if [ "$debug_level" -eq "0" ]; then
                debug "send_report: report file left at $report_pending"
            else
                rm -f "$report_pending"
            fi
    
            if [ -f "${report_pending}_attachments" ]; then
                attachments=`cat "${report_pending}_attachments"`
                for attach in $attachments; do
                    rm -f "$attach"
                done
                rm -f "${report_pending}_attachments"
            fi

        else
            debug "No report present for $report"
        fi

    done
    

else

    echo "No report files found: $report_spool" 

fi
    
