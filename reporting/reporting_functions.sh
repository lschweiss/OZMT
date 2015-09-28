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

    if [ "$#" -eq "2" ]; then
        process_message "$1" 0 $email_debug none $2
    else
        process_message "$1" 0 $email_debug none
    fi

}

notice() {

    if [ "$#" -eq "2" ]; then
        process_message "$1" 1 $email_notice none $2
    else
        process_message "$1" 1 $email_notice none
    fi

}


warning() {

    if [ "$#" -eq "2" ]; then
        process_message "$1" 2 $email_warnings high $2
    else
        process_message "$1" 2 $email_warnings high
    fi

}


error() {

    if [ "$#" -eq "2" ]; then
        process_message "$1" 3 $email_errors high $2
    else
        process_message "$1" 3 $email_errors high
    fi

}


process_message() {

    local terminal=
    local importance=
    local messagefile=
    local send_options=
    local basename=
    local noreport=

    # Inputs:
    # $1 - The message.  Should be quoted.
    # $2 - Message level
    # $3 - Report level
    # $4 - Importance level (set to 'none' if not used)
    # $5 - Include contents of file $5.  (optional)

    local message="$1"
    local this_message=
    local this_message_level="$2"
    local this_report_level="$3"
    local this_import_level="$4"
    local this_include_file="$5"
    local message_file=
    local this_subject=
    local email_limit="0"
    local this_hash=
    local limit_dir="/var/zfs_tools/reporting/limit"
    local hash_dir=
    local limit_file=
    local limit=
    local limits=
    local limit_type=
    local limit_num=
    local count=
    local skip=

    case $this_message_level in
        '0')
            this_message="DEBUG: $(now): $message"
            ;;
        '1')
            this_message="NOTICE: $(now): $message"
            ;;
        '2')
            this_message="WARNING: $(now): $message"
            ;;
        '3')
            this_message="ERROR: $(now): $message"
            ;;
        
    esac

    

    if [ "$0" == '-bash' ]; then
        basename="/bin/bash"
    else
        basename=`basename $0`
    fi

    mkdir -p "${TMP}/reporting"

    if [ "$DEBUG" == "true" ]; then
        noreport="$(color red)Not reporting: "
    else
        noreport=""
    fi

    if [ "x$default_report_title" == "x" ]; then
        default_report_title="zfs_tools"
    fi

    if [ "$email_cc" != "" ]; then
        send_options="-c $email_cc"
    fi

    if [ "$email_bcc" != "" ]; then
        send_options="-b $email_bcc $send_options"
    fi

    if [[ "$debug_level" == "" || "${this_message_level}" -ge "$debug_level" || "$DEBUG" == "true" ]]; then
        # Determine if we are running on a terminal
        if [[ -t 1 || "$DEBUG" == "true" && "$DEBUG" != "false" ]]; then
            source $TOOLS_ROOT/ansi-color-0.6/color_functions.sh
            # Set the color
            case "$2" in 
                '0') echo -n "${noreport}$(color bd white)" >&2 ;;
                '1') echo -n "${noreport}$(color bd blue)" >&2 ;;
                '2') echo -n "${noreport}$(color bd yellow)" >&2 ;;
                '3') echo -n "${noreport}$(color bd red)" >&2 ;;
            esac 
            # Display the message
            if [ "${this_message_level}" -gt 1 ]; then
                echo "${basename} ${this_message}$(color off)" >&2
            else
                echo "${basename} ${this_message}$(color off)" >&2
            fi

        fi
    fi

    if [ "${this_import_level}" == "none" ]; then
        importance=""
    else
        importance="${this_import_level}"
    fi

    if [ "x${report_name}" == "x" ]; then
        report_name="$default_report_name"
    fi
            
    mkdir -p "${report_spool}"

    if [ "x${this_report_level}" == "xnow" ]; then
        # Send the email report now
        message_file=${TMP}/reporting/process_message_$$
        case "${this_message_level}" in
            '0') 
                this_subject="DEBUG: ${basename} ${report_name} $HOSTNAME"
                email_limit="$DEBUG_EMAIL_LIMIT"
                ;;            
            '1') 
                this_subject="NOTICE: ${basename} ${report_name} $HOSTNAME" 
                email_limit="$NOTICE_EMAIL_LIMIT"
                ;;
            '2') 
                this_subject="WARNING: ${basename} ${report_name} $HOSTNAME"
                email_limit="$WARNING_EMAIL_LIMIT"
                ;;
            '3') 
                this_subject="ERROR: ${basename} ${report_name} $HOSTNAME"
                email_limit="$ERROR_EMAIL_LIMIT"
                ;;
        esac

        echo >> $message_file
        echo "${this_message}" >> $message_file

        if [[ "$#" -eq "5" && -f ${this_include_file} ]]; then
            if [ -t 1 ]; then
                cat ${this_include_file} >&2
            fi
            echo ${this_include_file} > ${message_file}_attachments
        fi

        # Rate limit emails
        skip='false'
        if [ "$email_limit" != '0' ]; then
            this_hash=`echo "${this_subject}_${message}" | ${MD5SUM} | ${CUT} -f1 -d" "`
            hash_dir="${limit_dir}/${this_hash}"
            mkdir -p "$hash_dir"
            for limit in $email_limit; do    
                limit_type="${limit:0:1}"
                limit_num="${limit:1}"
                count=0
                case $limit_type in
                    m) count=`${FIND} ${hash_dir} -type f -mmin -1 | ${WC} -l` ;;
                    h) count=`${FIND} ${hash_dir} -type f -mmin -60 | ${WC} -l` ;;
                    d) count=`${FIND} ${hash_dir} -type f -mtime -1 | ${WC} -l` ;;

                esac
                if [ $count -ge $limit_num ]; then
                    skip='true'
                    if [ -t 1 ]; then
                        echo "Skipping email, limit ${limit}: $this_subject"
                    fi
                fi
            done

            if [ "$skip" == 'false' ]; then
                limit_file="${hash_dir}/$(${DATE} +%F_%H:%M:%S:%N)"
                if [ -t 1 ]; then
                    echo "limit file: $limit_file"
                fi
                echo "$this_subject" > "$limit_file"
                echo "$this_message" >> "$limit_file"
            fi
        fi

        if [[ "$DEBUG" != 'true' && "$skip" != 'true' ]]; then
            $TOOLS_ROOT/reporting/send_email.sh $send_options -f "$message_file" -s "$this_subject" -i "${importance}" -r "$email_to"
            if [ $? -eq 0 ]; then
                rm $message_file
            fi 
        fi


    fi

    if [[ "x${this_report_level}" == "xreport" || "x${this_report_level}" == "xnow" ]]; then

        # Add the message to the next email report

        # Move to spool directory if it hasn't

        if [ -d "$TOOLS_ROOT/reporting/reports_pending/${report_name}" ]; then
            # Move to ${report_spool}
            mv "$TOOLS_ROOT/reporting/reports_pending/${report_name}" "${report_spool}/${report_name}"
        fi

        mkdir -p "${report_spool}/${report_name}/attach"

        # Raise the report level if necessary
        if [ -f "${report_spool}/${report_name}/report_level" ]; then
            source "${report_spool}/${report_name}/report_level"
        fi
        if [[ "$report_level" == "" || "$report_level" -le "${this_message_level}" ]]; then
            echo "report_level=\"${this_message_level}\"" > "${report_spool}/${report_name}/report_level"
        fi

        if [ "$DEBUG" != "true" ]; then
            echo "${this_message}" >> "${report_spool}/${report_name}/report_pending"
            if [[ "$#" -eq "5" && -f "${this_include_file}" ]]; then
                this_file="$(basename "${this_include_file}")"
                cp ${this_include_file} "${report_spool}/${report_name}/attach/report_file_$$.txt"
                echo "${report_spool}/${report_name}/attach/report_file_$$.txt" >> "${report_spool}/${report_name}/report_attachments"
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


