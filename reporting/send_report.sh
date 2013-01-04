#! /bin/bash -x

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


if [ -d "$TOOLS_ROOT/reporting/reports_pending" ]; then

    reports=`ls -1 $TOOLS_ROOT/reporting/reports_pending`

    for report in $reports; do

        report_path="$TOOLS_ROOT/reporting/reports_pending/$report"
    
        # Move the report to a temporary file to avoid race conditions
    
        report_pending="/tmp/send_report_$report_$$"
    
        mv $report_path/report_pending $report_pending
    
        source $report_path/report_level
    
        rm $report_path/report_level

        email_subject="aws_zfs_tools $report report"
    
        notice "send_report: Sending $report"
    
        if [[ "x$report_level" != "x" && "$report_level" -ge 4 ]]; then

            email_subject="ERROR: $email_subject"
            
            ./send_email.sh $report_pending "$email_subject" high
    
        else 
    
            ./send_email.sh $report_pending "$email_subject"
    
        fi

    done
    
    if [ "$debug_level" -eq "0" ]; then
        debug "send_report: report file left at $report_pending"
    else
        rm $report_pending
    fi

else

    warning "No report files found: $TOOLS_ROOT/reporting/reports_pending" >&2

fi
    
