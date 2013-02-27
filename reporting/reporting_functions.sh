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

    if [ "$#" -eq "2" ]; then
        process_message "$message" 0 $email_debug none $2
    else
        process_message "$message" 0 $email_debug none
    fi

}

notice() {

    local message="NOTICE: $(now): $1"

    if [ "$#" -eq "2" ]; then
        process_message "$message" 1 $email_notice none $2
    else
        process_message "$message" 1 $email_notice none
    fi

}


warning() {

    local message="WARNING: $(now): $1"

    if [ "$#" -eq "2" ]; then
        process_message "$message" 2 $email_warning high $2
    else
        process_message "$message" 2 $email_warning high
    fi

}


error() {

    local message="ERROR: $(now): $1"

    if [ "$#" -eq "2" ]; then
        process_message "$message" 3 $email_error high $2
    else
        process_message "$message" 3 $email_error high
    fi

}


process_message() {

    local terminal=
    local importance=
    local messagefile=

    # Inputs:
    # $1 - The message.  Should be quoted.
    # $2 - Message level
    # $3 - Report level
    # $4 - Importance level (set to 'none' if not used)
    # $5 - Include contents of file $5.  (optional)

    if [[ "$debug_level" == "" || "$2" -ge "$debug_level" || "$DEBUG" == "true" ]]; then
        # Determine if we are running on a terminal
        tty -s
        terminal=$?        
        if [[ "$terminal" -eq "0" || "$DEBUG" == "true" ]]; then
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

    if [ "$4" == "none" ]; then
        importance=""
    else
        importance="$4"
    fi
        

    if [ "x$3" == "xnow" ]; then
        # Send the email report now
        message_file=/tmp/process_message_$$
        case "$2" in
            '0') echo "Subject: DEBUG: aws_zfs_tools $HOSTNAME" > $message_file ;;
            '1') echo "Subject: NOTICE: aws_zfs_tools $HOSTNAME" > $message_file ;;
            '2') echo "Subject: WARNING: aws_zfs_tools $HOSTNAME" > $message_file ;;
            '3') echo "Subject: ERROR: aws_zfs_tools $HOSTNAME" > $message_file ;;
        esac

        echo >> $message_file
        echo "$1" >> $message_file

        if [[ "$#" -eq "5" && -f "$5" ]]; then
            cat $5 >> $message_file
        fi

        if [ "$DEBUG" == "true" ]; then
            # We are debuging on the console don't send email
            echo "$(color bd red)DEBUG: Not sending email $message_file"
        else
            $TOOLS_ROOT/reporting/send_email.sh $message_file $4
        fi

        if [ "$?" -eq "0" ]; then
            rm $message_file
        fi 

    fi

    if [[ "x$3" == "xreport" || "x$3" == "xnow" ]]; then

        if [ "x$report_name" == "x" ]; then
            report_name="$default_report_name"
        fi

        # Add the message to the next email report

        report_path="$TOOLS_ROOT/reporting/reports_pending/$report_name"

        mkdir -p $report_path

        # Raise the report level if necessary
        if [ -f $report_path/report_level ]; then
            source $report_path/report_level
        fi
        if [[ "$report_level" == "" || "$report_level" -le "$2" ]]; then
            echo "report_level=\"$2\"" > $report_path/report_level
        fi

        if [ "$DEBUG" == "true" ]; then
            # We are debuging on the console don't report
            echo "$(color bd red)DEBUG: not reporting $1"
        else            
            echo "$1" >> $report_path/report_pending
            if [[ "$#" -eq "5" && -f "$5" ]]; then
                cat $5 >> $report_path/report_pending
            fi
        fi
                     
    fi

    # If enable append to log file
    if [[ "x$logfile" != "x" && "$2" -ge "$logging_level" ]]; then
        echo $1 >> $logfile

        if [[ "$#" -eq "5" && -f "$5" ]]; then
            cat $5 >> $logfile
        fi
    fi        

    if [ "$DEBUG" == "true" ]; then
        echo "$(color)"
    fi

}


