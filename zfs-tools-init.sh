#! /bin/bash

# zfs-tools-init.sh
#
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

if [ -f /etc/zfs-tools-config ]; then
    . /etc/zfs-tools-config
fi

if [ -f /etc/sysconfig/zfs-tools-config ]; then
    . /etc/sysconfig/zfs-tools-config
else 
    if [ -f /etc/sysconfig/zfs-config ]; then 
        . /etc/sysconfig/zfs-config
    fi
fi

if [ -f /root/zfs-config.sh ]; then
    . /root/zfs-config.sh 
else 
    if [ -f ./zfs-config.sh ]; then
        . ./zfs-config.sh 
    fi 
fi 

_DEBUG="on"
function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

os=`uname`

# Handle depricated zfs-config files format
GREP=$grep
SED=$sed
AWK=$awk
CUT=$cut
MUTT=$mutt
DATE=$date
RSYNC=$rsync
SSH=$ssh
TIMEOUT=$timeout

# Load paths if not defined in configs
if [ -z $GREP ]; then
    GREP=`which grep`
fi

if [ -z $SED ]; then
    SED=`which sed`
fi

if [ -z $AWK ]; then
    AWK=`which awk`
fi

if [ -z $CUT ]; then
    CUT=`which cut`
fi

if [ -z $MUTT ]; then
    MUTT=`which mutt`
fi

if [ -z $DATE ]; then
    DATE=`which date`
fi

if [ -z $RSYNC ]; then
    RSYNC=`which rsync`
fi

if [ -z $SSH ]; then
    SSH=`which ssh`
fi

if [ -z $TIMEOUT ]; then
    TIMEOUT=`which timeout`
fi

if [ -z $BC ]; then
    BC=`which bc`
fi


if [ -z $bbcp ]; then
    if [ -f "$TOOLS_ROOT/utils/bbcp.${os}" ]; then
        bbcp="$TOOLS_ROOT/utils/bbcp.${os}"
    else
        bbcp=`which bbcp`
    fi
fi

if [ -z $mbuffer ]; then
    if [ -f "$TOOLS_ROOT/utils/mbuffer.${os}" ]; then
        mbuffer="$TOOLS_ROOT/utils/mbuffer.${os}"
    else
        mbuffer=`which bbcp` 
    fi
fi

if [ -z $lz4 ]; then
    if [ -f "$TOOLS_ROOT/utils/lz4.${os}" ]; then
        lz4="$TOOLS_ROOT/utils/lz4.${os}"
    else
        lz4=`which lz4`
    fi
fi

if [ -z $gzip ]; then
    if [ -f "$TOOLS_ROOT/utils/gzip.${os}" ]; then
        gzip="$TOOLS_ROOT/utils/gzip.${os}"
    else
        gzip=`which gzip`
    fi
fi

# Set defaults

if [ "$minimum_report_frequency" == "" ]; then
    minmum_report_frequency=1800
fi

if [ "$QUOTA_REPORT_TEMPLATE" == "" ]; then
    QUOTA_REPORT_TEMPLATE="$TOOLS_ROOT/reporting/quota-report.html"
fi

if [ "$zfs_replication_property" == "" ]; then
    zfs_replication_property="edu.wustl.nrg:replication"
fi

# Test essential binaries

binary_error=0

# date

${DATE} --date 2013-11-14 +%s 2>/dev/null 1>/dev/null

if [ $? -ne 0 ]; then
    echo "date function not compatible.  Make sure the path includes a gnu compatible date function or define the variable 'date'."
    binary_error=1
fi

# grep

echo 'Today is not 2010-10-01.'|${GREP} -o -e '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 2> /dev/null 1> /dev/null

if [ $? -ne 0 ]; then
    echo "grep function not compatible.  Make sure the path includes a gnu compatible grep function or define the varible 'grep'."
    binary_error=1
fi

# awk TODO: need a test

# sed TODO: need a test

# mutt TODO: need a test

# cut TODO: need a test

# rync TODO: need a test

if [ $binary_error -ne 0 ]; then
    echo Aborting
    exit 1
fi

if [ -z $tools_snapshot_name ]; then
    tools_snapshot_name="aws-backup_"
fi


##
# 
# Source other functions
#
##

source $TOOLS_ROOT/zfs-tools-functions.sh




##
# EC2 Backup
##

if [ "$ec2_backup" == "true" ]; then

    volumes=`expr $vdevs \* $devices`
    
    # Define device groups, crypt groups
    
    alphabet='abcdefghijklmnopqrstuvwxyz'
    
    first_index=`expr index "$alphabet" $dev_first_letter`
    
    x=0
    
    while [ $x -lt $vdevs ]; do
        # Bash uses 0 base indexing
        index=`expr $x + $first_index - 1`
        d=$(( $x + 1 ))
        dev_letter=${alphabet:${index}:1}
        y=1
        awsdev[$d]=""
        phydev[$d]=""
        devname[$d]=""
        cryptdev[$d]=""
        cryptname[$d]=""
        while [ $y -le $devices ]; do
            awsdev[$d]="${awsdev[$d]}/dev/sd${dev_letter}${y} "
            phydev[$d]="${phydev[$d]}/dev/xvd${dev_letter}${y} "
            devname[$d]="${devname[$d]}xvd${dev_letter}${y} "
            cryptdev[$d]="${cryptdev[$d]}/dev/mapper/crypt${dev_letter}${y} "
            cryptname[$d]="${cryptname[$d]}crypt${dev_letter}${y} "
            y=$(( $y + 1 ))
        done
        x=$(( $x + 1 ))
    done

fi

# Backup defaults
if [ "$skiptypes" == "" ]; then
    # Skip processing increments smaller than daily
    skiptypes="mid-day hourly 30min 15min 5min min"
fi

# Reporting defaults

if [ "x$default_report_name" == "x" ]; then
    default_report_name="default"
fi

if [ "x$report_spool" == "x" ]; then
    report_spool="/var/zfs_tools/reporting/pending"
fi

if [ "x$TMP" == "x" ]; then
    TMP="/tmp"
fi

mkdir -p ${TMP}
