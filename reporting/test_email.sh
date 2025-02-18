#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2015  Chip Schweiss

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

send_options=

if [ "$email_cc" != "" ]; then
    send_options="-c $email_cc"
fi

if [ "$email_bcc" != "" ]; then
    send_options="-b $email_bcc $send_options"
fi

echo "Test email from $HOSTNAME" >${TMP}/test_email

./send_email.sh $send_options -f "${TMP}/test_email" -s "${HOSTNAME}: Test email." -r "$email_to"

rm ${TMP}/test_email
