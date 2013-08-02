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

report_name="default"


if [ -d "$TOOLS_ROOT/reporting/reports_pending" ]; then

    reports=`ls -1 $TOOLS_ROOT/reporting/reports_pending`

    for report in $reports; do

        report_path="$TOOLS_ROOT/reporting/reports_pending/$report"

        if [ -f $report_path/report_pending ]; then
            report_pending="/tmp/send_report_$report_$$"

            # Move the report to a temporary file to avoid race conditions
            mv $report_path/report_pending $report_pending

            if [ -f $report_path/report_attachments ]; then
                mv $report_path/report_attachments ${report_pending}_attachments
            fi
        
            source $report_path/report_level
        
            rm $report_path/report_level
    
            email_subject="${default_report_title} $report report"
        
            debug "send_report: Sending $report"
        
            if [[ "x$report_level" != "x" && "$report_level" -ge 3 ]]; then
                email_subject="ERROR: $email_subject"
                ./send_email.sh $report_pending "$email_subject" high
            else 
                ./send_email.sh $report_pending "$email_subject"
            fi
    
            if [ "$debug_level" -eq "0" ]; then
                debug "send_report: report file left at $report_pending"
            else
                rm -f $report_pending
            fi
    
            if [ -f ${report_pending}_attachments ]; then
                attachments=`cat ${report_pending}_attachments`
                for attach in $attachments; do
                    rm -f $attach
                done
                rm -f ${report_pending}_attachments
            fi

        else
            debug "No report present for $report"
        fi

    done
    

else

    warning "No report files found: $TOOLS_ROOT/reporting/reports_pending" 

fi
    
