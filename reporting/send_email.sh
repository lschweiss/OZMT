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

die () {

    echo "$1" >&2
    exit 1

}

message_file="$1"

message_subject="$2"

message_importance="$3"


if [ ! -f "$message_file" ]; then
    die "Specified message \"${message_file}\" does not exist"
fi

if [ "x$message_importance" != "x" ]; then

    echo "Importance:${message_importance}" > /tmp/mutt_message_$$

else 
    rm -f /tmp/mutt_message_$$

fi

cat $message_file >> /tmp/mutt_message_$$

# Build cc and bcc list

mutt_options=""

for cc in $email_cc; do
    mutt_options="$mutt_options -c $cc"
done

for bcc in $email_bcc; do
    mutt_options="$mutt_options -c $bcc"
done
    
# Send the message    
mutt -s "$message_subject" -H /tmp/mutt_message_$$ $mutt_options $email_to

rm /tmp/mutt_message_$$
