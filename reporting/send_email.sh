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

die () {

    echo "$1" >&2
    exit 1

}

show_usage () {
    echo
    echo "Usage: $0 -f {message_file} -s {message_subject} -r {message_recipient}"
    echo "  [-i {importance}]       Message importance."
    echo "  [-c {cc}]               Message cc recipient.  (Repeatable)"
    echo "  [-b {bcc}]              Message bcc recipient. (Repeatable)"

}

mutt_options=""
attach_cmd=

while getopts f:s:i:r:c:b: opt; do
    case $opt in 
        f) message_file="$OPTARG" ;;
        s) message_subject="$OPTARG" ;;
        i) message_importance="$OPTARG" ;;
        r) message_recipient="$OPTARG" ;;
        c) message_cc="$OPTARG;$message_cc" ;;
        b) message_bcc="$OPTARG;$mesage_bcc" ;;
        ?) show_usage; exit 0 ;;
        :) die "Option -$OPTARG requires an argument." ;;
    esac
done 


if [ ! -f "$message_file" ]; then
    die "Specified message \"${message_file}\" does not exist"
fi

if [ "x$message_importance" != "x" ]; then

    echo "Importance:${message_importance}" > ${TMP}/mutt_message_$$

else 
    rm -f ${TMP}/mutt_message_$$

fi

cat $message_file >> ${TMP}/mutt_message_$$

# Gather attachment list

if [ -f ${message_file}_attachments ]; then

    attachments_file="${TMP}/report_attachements_$$"
    mv ${message_file}_attachments $attachments_file 


    attachments=`cat $attachments_file`

    for attach in $attachments; do
        # If the file is over 100K, compress it
        attach_size=`stat --format=%s $attach`
        if [ $attach_size -ge 100000 ]; then
            gzip $attach
            attach="${attach}.gz"
        fi
        attach_cmd="$attach $attach_cmd"
    done

    # add '-a' parameter and required separator for email address on mutt command line
    attach_cmd="-a $attach_cmd --"

fi


# Build cc and bcc list


if [ "$message_cc" != "" ]; then
    cc_num=1
    cc=`echo $message_cc | ${CUT} -d ";" -f $cc_num`
    while [ "$cc" != "" ]; do
        mutt_options="$mutt_options -c $cc"
        cc_num=$(( cc_num + 1 ))
        cc=`echo $message_cc | ${CUT} -d ";" -f $cc_num `
    done
fi 


if [ "$message_bcc" != "" ]; then
    bcc_num=1
    bcc=`echo $message_bcc | ${CUT} -d ";" -f $bcc_num`
    while [ "$bcc" != "" ]; do
        mutt_options="$mutt_options -b $bcc"
        bcc_num=$(( cc_num + 1 ))
        bcc=`echo $message_bcc | ${CUT} -d ";" -f $bcc_num `
    done
fi

# Move reporting.muttrc to /etc/ozmt
if [ -f $TOOLS_ROOT/reporting/reporting.muttrc ]; then
    mkdir -p /etc/ozmt
    mv $TOOLS_ROOT/reporting/reporting.muttrc /etc/ozmt/reporting.muttrc
fi


if [ ! -f /etc/ozmt/reporting.muttrc ]; then
    echo "/etc/ozmt/reporting.muttrc does not exist.  Please create this file to enable email reporting."
    exit 1
fi
    
# Send the message    
if [ "${message_file: -4}" == "html" ]; then
    $MUTT -F /etc/ozmt/reporting.muttrc -s "$message_subject" \
        -e "set content_type=text/html" $mutt_options $attach_cmd $message_recipient < ${TMP}/mutt_message_$$ &> ${TMP}/mutt_output_$$
else
    $MUTT -F /etc/ozmt/reporting.muttrc -s "$message_subject" \
        $mutt_options $attach_cmd $message_recipient < ${TMP}/mutt_message_$$ &> ${TMP}/mutt_output_$$
fi 

result=$?

if [ $result -ne 0 ]; then 
    echo "Failed to send message ${TMP}/mutt_message_$$" 
    cat ${TMP}/mutt_output_$$
else
    rm ${TMP}/mutt_message_$$
    if [ -f $attachments_file ]; then
        for attach in $attachments; do
            rm -f $attach
        done
        rm -f $attachments_file
    fi
fi

