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
        process_message "$message" 2 $email_warnings high $2
    else
        process_message "$message" 2 $email_warnings high
    fi

}


error() {

    local message="ERROR: $(now): $1"

    if [ "$#" -eq "2" ]; then
        process_message "$message" 3 $email_errors high $2
    else
        process_message "$message" 3 $email_errors high
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

    local this_message="$1"
    local this_message_level="$2"
    local this_report_level="$3"
    local this_import_level="$4"
    local this_include_file="$5"

    if [ "$DEBUG" == "true" ]; then
        noreport="$(color red)Not reporting: "
    else
        noreport=""
    fi

    if [ "x$default_report_title" == "x" ]; then
        default_report_title="zfs_tools"
    fi

    if [[ "$debug_level" == "" || "${this_message_level}" -ge "$debug_level" || "$DEBUG" == "true" ]]; then
        # Determine if we are running on a terminal
        if [[ -t 1 || "$DEBUG" == "true" && "$DEBUG" != "false" ]]; then
            # Set the color
            case "$2" in 
                '0') echo -n "${noreport}$(color bd white)" ;;
                '1') echo -n "${noreport}$(color bd blue)" ;;
                '2') echo -n "${noreport}$(color bd yellow)" ;;
                '3') echo -n "${noreport}$(color bd red)" ;;
            esac 
            # Display the message
            if [ "${this_message_level}" -gt 1 ]; then
                echo "${this_message}$(color off)" 1>&2
            else
                echo "${this_message}$(color off)"
            fi

        fi
    fi

    if [ "${this_import_level}" == "none" ]; then
        importance=""
    else
        importance="${this_import_level}"
    fi

    if [ "x$report_name" == "x" ]; then
        report_name="$default_report_name"
    fi
        

    if [ "x${this_report_level}" == "xnow" ]; then
        # Send the email report now
        message_file=${TMP}/process_message_$$
        case "${this_message_level}" in
            '0') this_subject="DEBUG: ${report_name} $HOSTNAME" ;;
            '1') this_subject="NOTICE: ${report_name} $HOSTNAME" ;;
            '2') this_subject="WARNING: ${report_name} $HOSTNAME" ;;
            '3') this_subject="ERROR: ${report_name} $HOSTNAME" ;;
        esac

        echo >> $message_file
        echo "${this_message}" >> $message_file

        if [[ "$#" -eq "5" && -f ${this_include_file} ]]; then
            echo ${this_include_file} > ${message_file}_attachments
        fi

        if [ "$DEBUG" != "true" ]; then
            $TOOLS_ROOT/reporting/send_email.sh -f "$message_file" -s "$this_subject" -i "${importance}" -r "$email_to"
        fi

        if [ "$?" -eq "0" ]; then
            rm $message_file
        fi 

    fi

    if [[ "x${this_report_level}" == "xreport" || "x${this_report_level}" == "xnow" ]]; then

        # Add the message to the next email report

        # Move to spool directory if it hasn't

        if [ -d "$TOOLS_ROOT/reporting/reports_pending/$report_name" ]; then
            # Move to $report_spool
            mkdir -p "$report_spool"
            mv "$TOOLS_ROOT/reporting/reports_pending/$report_name" "${report_spool}/${report_name}"
        fi


        mkdir -p "$report_spool/attach"

        # Raise the report level if necessary
        if [ -f "$report_spool/report_level" ]; then
            source "$report_spool/report_level"
        fi
        if [[ "$report_level" == "" || "$report_level" -le "${this_message_level}" ]]; then
            echo "report_level=\"${this_message_level}\"" > "$report_spool/report_level"
        fi

        if [ "$DEBUG" != "true" ]; then
            echo "${this_message}" >> "$report_spool/report_pending"
            if [[ "$#" -eq "5" && -f "${this_include_file}" ]]; then
                this_file=$(basename ${this_include_file})
                cp ${this_include_file} "$report_spool/attach/report_file_$$.txt"
                echo "$report_spool/attach/report_file_$$.txt" >> "$report_spool/report_attachments"
            fi
        fi
    fi

    # If enable append to log file
    if [[ "x$logfile" != "x" && "${this_message_level}" -ge "$logging_level" ]]; then
        echo ${this_message} >> $logfile

        if [[ "$#" -eq "5" && -f "${this_include_file}" ]]; then
            cat ${this_include_file} >> $logfile
        fi
    fi        

}


