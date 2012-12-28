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

debug() {

    local message="DEBUG: $(now): $1"

    process_message "$message" 0 $email_debug 

}

notice() {

    local message="NOTICE: $(now): $1"

    process_message "$message" 1 $email_notice

}


warning() {

    local message="WARNING: $(now): $1"

    process_message "$message" 2 $email_warning high

}


error() {

    local message="ERROR: $(now): $1"

    process_message "$message" 3 $email_error high

}


process_message() {

    # Inputs:
    # $1 - The message.  Should be quoted.
    # $2 - Message level
    # $3 - Report level
    # $4 - Importance level (optional)

    if [[ "$debug_level" == "" || "$2" -ge "$debug_level" ]]; then
        # Determine if we are running on a terminal
        tty -s
        local terminal=$?        
        if [ "$terminal" -eq "0" ]; then
            # Set the color
            case "$2" in 
                '0') echo -n "$(color bd white)" ;;
                '1') echo -n "$(color bd blue)" ;;
                '2') echo -n "$(color bd yellow)" ;;
                '3') echo -n "$(color bd red)" ;;
            esac 
            # Display the message
            echo "$1$(color off)"
        fi
    fi

    if [ "x$3" == "xnow" ]; then
        # Send the email report now
        local message_file=/tmp/process_message_$$
        case "$2" in
            '0') echo "Subject: DEBUG: aws_zfs_tools $HOSTNAME" > $message_file ;;
            '1') echo "Subject: NOTICE: aws_zfs_tools $HOSTNAME" > $message_file ;;
            '2') echo "Subject: WARNING: aws_zfs_tools $HOSTNAME" > $message_file ;;
            '3') echo "Subject: ERROR: aws_zfs_tools $HOSTNAME" > $message_file ;;
        esac

        echo >> $message_file
        echo "$1" >> $message_file

        $TOOLS_ROOT/reporting/send_email.sh $message_file $4        
        if [ "$?" -eq "0" ]; then
            rm $message_file
        fi 

    fi

    if [[ "x$3" == "xreport" || "x$3" == "xnow" ]]; then
        # Add the message to the next email report

        # Raise the report level if necessary
        if [ -f $TOOLS_ROOT/reporting/report_level ]; then
            source $TOOLS_ROOT/reporting/report_level
        fi
        if [[ "$report_level" == "" || "$report_level" -le "$2" ]]; then
            echo "report_level=\"$2\"" > $TOOLS_ROOT/reporting/report_level
        fi

        echo "$1" >> $TOOLS_ROOT/reporting/report_pending             
    fi

}


