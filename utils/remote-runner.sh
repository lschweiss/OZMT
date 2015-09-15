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

# Usage
# First parameter exit code file
# Remaining parameters process to run

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source ../zfs-tools-init.sh

trap "" HUP

pid=

stdin="$1"
shift 1
stdout="$1"
shift 1
stderr="$1"
shift 1
exitfile="$1"
shift 1
pidfile="$1"
shift 1

##
# Launch the job and capture output and PID of the bash subshell
##
( $@ < "$stdin" > "$stdout" 2> "$stderr" ; echo $? > "$exitfile" ) &
ppid=$!

##
# Find the PID of the actual job
##
case $os in
    'SunOS')
        pid=`/usr/bin/ptree $ppid | ${TAIL} -1 | ${AWK} -F ' ' '{print $1}'`
        ;;

    'Linux')
        ps -eo ppid,pid > ${TMP}/remote_runner_$$.txt
        # Find the child of ppid because ppid is still bash not our process.
        pid=`ps -eo ppid,pid|${GREP} "^\s*${ppid} "|${AWK} -F " " '{print $2}'`
        ;;
    *)
        error "$os not support by remote-runner.sh"
        ;;
esac

if [ "$pid" == "" ]; then
    error "Could not get the PID for \"$@\".  OS: $os Parent PID: $ppid  Could cause additional errors. " ${TMP}/remote_runner_$$.txt
fi

echo $pid > "$pidfile"

##
# Wait for our job to complete
##
wait
