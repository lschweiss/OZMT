#! /bin/bash


# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2014  Chip Schweiss

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

#USAGE: nfssvrtop [-Cj] [-b blocksize] [-c client_IP] [-n vers] [-t top]
#                 [interval [count]]
#             -b blocksize # alignment blocksize (default=4096)
#             -c client_IP # trace for this client only
#             -C           # don't clear the screen
#             -j           # print output in JSON format
#             -n vers      # show only NFS version
#             -t top       # print top number of entries only
#   examples:
#     nfssvrtop         # default output, 10 second samples
#     nfssvrtop -b 1024 # check alignment on 1KB boundary
#     nfssvrtop 1       # 1 second samples
#     nfssvrtop -n 4    # only show NFSv4 traffic
#     nfssvrtop -C 60   # 60 second samples, do not clear screen
#     nfssvrtop -t 20   # print top 20 lines only
#     nfssvrtop 5 12    # print 12 x 5 second samples
#


cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../../zfs-tools-init.sh

now=`date +%F_%H:%M%z`

pool=$1

logfile="/$pool/zfs_tools/logs/nfs_stat_${now}"

$TOOLS_ROOT/utils/arcstat.pl -o $logfile -f time,arcsz,read,hits,hit%,l2read,l2hits,l2miss,l2hit%,l2size,mrug,mfug 60 60 

