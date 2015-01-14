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

trap "" HUP

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
( $@ < "$stdin" > "$stdout" 2> "$stderr" ; echo $? > "$exitfile" ) &
echo $! > "$pidfile"
wait
