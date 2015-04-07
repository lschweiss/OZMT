# /bin/bash

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

# Search all the historical places the config has been kept

if [ -f /etc/ozmt/config ]; then
    source /etc/ozmt/config
else
    # All other locations are depricated at the release of OZMT:
    if [ -f /etc/zfs-tools-config ]; then
        source /etc/zfs-tools-config
    fi
    
    if [ -f /etc/sysconfig/zfs-tools-config ]; then
        source /etc/sysconfig/zfs-tools-config
    else 
        if [ -f /etc/sysconfig/zfs-config ]; then 
            source /etc/sysconfig/zfs-config
        fi
    fi
    
    if [ -f /root/zfs-config.sh ]; then
        source /root/zfs-config.sh 
    else 
        if [ -f ./zfs-config.sh ]; then
            source ./zfs-config.sh 
        fi 
    fi 
    
    if [ ! -d /etc/ozmt ]; then
        mkdir -p /etc/ozmt
        if [ -f /root/zfs-config.sh ]; then
            mv /root/zfs-config.sh /etc/ozmt/config
            echo "# moved to /etc/ozmt/config" > /root/zfs-config.sh
        fi
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


case os in
    'SunOS')
        search_path="/opt/csw/gnu:/opt/csw/bin:/opt/csw/sbin:/usr/gnu/bin"
        ;;
    'Linux')
        # Distributions confirmed:
        # RHEL/CentOS 5.x, 6.x
        # Amazon Linux
        search_path="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
        ;;
esac



gnu_source () {
    # Find an acceptable GNU binary for our standard functions
    local binary="$1"
    local bin_path=
    if [ -f $TOOLS_ROOT/bin/${os}/${binary} ]; then
        echo $TOOLS_ROOT/bin/${os}/${binary}
        return 0
    fi
    IFS=":"
    for dir in $search_path; do
        if [ -f ${dir}/${binary} ]; then
            echo ${dir}/${binary}
            return 0
        fi
    done
    # Last resort
    which $binary
    return 1           
}


# Load paths if not defined in configs
if [ -z $GREP ]; then
    GREP=`gnu_source grep`
fi

if [ -z $HEAD ]; then
    HEAD=`gnu_source head`
fi

if [ -z $TAIL ]; then
    TAIL=`gnu_source tail`
fi

if [ -z $SED ]; then
    SED=`gnu_source sed`
fi

if [ -z $AWK ]; then
    AWK=`gnu_source awk`
fi

if [ -z $CUT ]; then
    CUT=`gnu_source cut`
fi

if [ -z $SORT ]; then
    SORT=`gnu_source sort`
fi

if [ -z $WC ]; then
    WC=`gnu_source wc`
fi

if [ -z $MUTT ]; then
    MUTT=`gnu_source mutt`
fi

if [ -z $DATE ]; then
    DATE=`gnu_source date`
fi

if [ -z $RSYNC ]; then
    RSYNC=`gnu_source rsync`
fi

if [ -z $SSH ]; then
    SSH=`gnu_source ssh`
fi

if [ -z $TIMEOUT ]; then
    TIMEOUT=`gnu_source timeout`
fi

if [ -z $BC ]; then
    BC=`gnu_source bc`
fi

if [ -z $PARALLEL ]; then
    PARALLEL=`gnu_source parallel`
fi

if [ -z $bbcp ]; then
    bbcp=`gnu_source bbcp`
fi

if [ -z $mbuffer ]; then
    mbuffer=`gnu_source mbuffer` 
fi

if [ -z $lz4 ]; then
    lz4=`gnu_source lz4`
fi

if [ -z $gzip ]; then
    gzip=`gnu_source gzip`
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

if [ "$zfs_replication_dataset_property" == "" ]; then
    zfs_replication_dataset_property="edu.wustl.nrg:replicationdataset"
fi

if [ "$zfs_replication_endpoints_property" == "" ]; then
    zfs_replication_endpoints_property="edu.wustl.nrg:replicationendpoints"
fi

if [ "$zfs_replication_failure_limit" == "" ]; then
    zfs_replication_failure_limit="30m"
fi

if [ "$zfs_replication_queue_delay_count" == "" ]; then
    zfs_replication_queue_delay_count=2
fi

if [ "$zfs_replication_queue_max_count" == "" ]; then
    zfs_replication_queue_max_count=5
fi

if [ "$zfs_replication_completed_job_retention" == "" ]; then
    zfs_replication_completed_job_retention="-mtime +30"
fi

if [ "$zfs_replication_snapshot_name" == "" ]; then
    zfs_replication_snapshot_name=".ozmt-replication"
fi

if [ "$zfs_replication_sync_filelist" == "" ]; then
    zfs_replication_sync_filelist="/etc/hosts:{pool}/etc/config.common"
fi

if [ -z $suspend_all_jobs_timeout ]; then
    suspend_all_jobs_timeout=60
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


# Skip pools default requires rpool function, sourced above
if [ "$skip_pools" == "" ]; then
    skip_pools="$(rpool)"
fi  


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

if [ -t 1 ]; then 
    if [ "$OZMTpath" != "" ]; then
        export OZMTpath="$TOOLS_ROOT/pool-filesystems:$TOOLS_ROOT/bin/${os}:$TOOLS_ROOT/3rdparty/tools"
        export PATH=$OZMTpath:$PATH
    fi
fi
