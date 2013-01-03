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

source $TOOLS_ROOT/reporting/report_level

report_pending="/tmp/send_report_$$"


if [ -f "$TOOLS_ROOT/reporting/report_pending" ]; then

    # Move the report to a temporary file to avoid race conditions

    mv $TOOLS_ROOT/reporting/report_pending $report_pending

    if [[ "x$report_level" != "x" && "$report_level" -ge 4 ]]; then
        
        ./send_email.sh $report_pending high

    else 

        ./send_email.sh $report_pending

    fi

#    rm $report_pending

else

    echo "No report file found: $TOOLS_ROOT/reporting/report_pending" >&2

fi
    
