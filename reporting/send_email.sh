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

message_file="$1"

message_subject="$2"

message_importance="$3"

attach_cmd=


if [ ! -f "$message_file" ]; then
    die "Specified message \"${message_file}\" does not exist"
fi

if [ "x$message_importance" != "x" ]; then

    echo "Importance:${message_importance}" > /tmp/mutt_message_$$

else 
    rm -f /tmp/mutt_message_$$

fi

cat $message_file >> /tmp/mutt_message_$$

# Gather attachment list

if [ -f ${message_file}_attachments ]; then

    attachments_file="/tmp/report_attachements_$$"
    mv ${message_file}_attachments $attachments_file 


    attachments=`cat $attachments_file`

    for attach in $attachments; do
        attach_cmd="$attach $attach_cmd"
    done

    # add '-a' parameter and required separator for email address on mutt command line
    attach_cmd="-a $attach_cmd --"

fi


# Build cc and bcc list

mutt_options=""

for cc in $email_cc; do
    mutt_options="$mutt_options -c $cc"
done

for bcc in $email_bcc; do
    mutt_options="$mutt_options -c $bcc"
done

if [ ! -f $TOOLS_ROOT/reporting/reporting.muttrc ]; then
    error "$TOOLS_ROOT/reporting/reporting.muttrc does not exist.  Please create this file to enable email reporting."
fi
    
# Send the message    
$mutt -F $TOOLS_ROOT/reporting/reporting.muttrc -s "$message_subject" \
    $mutt_options $attach_cmd $email_to < /tmp/mutt_message_$$ &> /tmp/mutt_output_$$ 

result=$?

if [ $result -ne 0 ]; then 
   error "Failed to send message /tmp/mutt_message_$$" /tmp/mutt_output_$$
fi

if [ ! -f /tmp/mutt_message_$$ ]; then
    # Message was sent clean up attachments
    if [ -f $attachments_file ]; then

        for attach in $attachments; do
            rm -f $attach
        done

        rm -f $attachments_file
    fi
fi
