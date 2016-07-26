#! /bin/bash

# zfs-tools-init.sh
#
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


case $os in
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
    unset IFS
    # Last resort
    which $binary 2> /dev/null
    if [ $? -ne 0 ]; then
        echo "/bin/false"
    fi
    return 1           
}


# Load paths if not defined in configs
if [ -z $LS ]; then
    LS=`gnu_source ls`
fi

if [ -z $GREP ]; then
    GREP=`gnu_source grep`
fi

if [ -z $HEAD ]; then
    HEAD=`gnu_source head`
fi

if [ -z $TAIL ]; then
    TAIL=`gnu_source tail`
fi

if [ -z $TAC ]; then
    TAC=`gnu_source tac`
fi

if [ -z $FIND ]; then
    FIND=`gnu_source find`
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

if [ -z $TAC ]; then
    TAC=`gnu_source tac`
fi

if [ -z $NL ]; then
    NL=`gnu_source nl`
fi

if [ -z $STAT ]; then
    STAT=`gnu_source stat`
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

if [ -z $MD5SUM ]; then
    MD5SUM=`gnu_source md5sum`
fi

if [ -z $BC ]; then
    BC=`gnu_source bc`
fi

if [ -z $BASENAME ]; then
    BASENAME=`gnu_source basename`
fi

if [ -z $PARALLEL ]; then
    PARALLEL=`gnu_source parallel`
fi

if [ -z $ARPING ]; then
    ARPING=`gnu_source arping`
fi

if [ -z $DIALOG ]; then
    DIALOG=`gnu_source dialog`
fi

if [ -z $bbcp ]; then
    bbcp=`gnu_source bbcp`
fi

if [ -z $BBCP ]; then
    BBCP=`gnu_source bbcp`
fi

if [ -z $mbuffer ]; then
    mbuffer=`gnu_source mbuffer` 
fi

if [ -z $MBUFFER ]; then
    MBUFFER=`gnu_source mbuffer`
fi

if [ -z $LSOF ]; then
    LSOF=`gnu_source lsof`
fi

if [ -z $lz4 ]; then
    lz4=`gnu_source lz4`
fi

if [ -z $LZ4 ]; then
    LZ4=`gnu_source lz4`
fi

if [ -z $gzip ]; then
    gzip=`gnu_source gzip`
fi

if [ -z $GZIP ]; then
    GZIP=`gnu_source gzip`
fi

if [ -z $TAR ]; then
    TAR=`gnu_source tar`
fi

if [ -z $SMBD ]; then
    SMBD="/usr/local/samba/sbin/smbd"
fi

if [ -z $NMBD ]; then
    NMBD="/usr/local/samba/sbin/nmbd"
fi

if [ -z $WINBINDD ]; then
    WINBINDD="/usr/local/samba/sbin/winbindd"
fi

if [ -z $SMBCONTROL ]; then
    SMBCONTROL="/usr/local/samba/bin/smbcontrol"
fi




# Set defaults

if [ "$debug_level" == "" ]; then
    debug_level=0
fi

if [ "$log_dir" == "" ]; then
    log_dir="/var/zfs_tools/log"
fi
mkdir -p $log_dir

if [ "$minimum_report_frequency" == "" ]; then
    minmum_report_frequency=1800
fi

if [ "$QUOTA_REPORT_TEMPLATE" == "" ]; then
    QUOTA_REPORT_TEMPLATE="$TOOLS_ROOT/reporting/quota-report.html"
fi

if [ "$QUOTA_AUTO_EXPAND_REQUIRED_FREE" == "" ]; then
    QUOTA_AUTO_EXPAND_REQUIRED_FREE="2T"
fi

if [ "$DEBUG_EMAIL_LIMIT" == "" ]; then
    DEBUG_EMAIL_LIMIT="0" # Unlimited
fi

if [ "$NOTICE_EMAIL_LIMIT" == "" ]; then
    NOTICE_EMAIL_LIMIT="h3" # 3 identical per hour
fi

if [ "$WARNING_EMAIL_LIMIT" == "" ]; then
    WARNING_EMAIL_LIMIT="m5 h6" # 3 identical per hour
fi

if [ "$ERROR_EMAIL_LIMIT" == "" ]; then
    ERROR_EMAIL_LIMIT="m2 h3 d6" # 2 identical per minuted, 3 per hour, 6 per day
fi

if [ "$DEBUG_REPORT_LIMIT" == "" ]; then
    DEBUG_REPORT_LIMIT="0" # Unlimited
fi

if [ "$NOTICE_REPORT_LIMIT" == "" ]; then
    NOTICE_REPORT_LIMIT="h20" # 20 identical per hour
fi

if [ "$WARNING_REPORT_LIMIT" == "" ]; then
    WARNING_REPORT_LIMIT="m5 h10 d60" # 5 per minute, 10 per hour, 60 per day
fi

if [ "$ERROR_REPORT_LIMIT" == "" ]; then
    ERROR_REPORT_LIMIT="m5 h10 d60" # 5 per minute, 10 per hour, 60 per day
fi

if [ "$samba_report" == "" ]; then
    samba_report="Samba"
fi

if [ "$samba_logfile" == "" ]; then
    samba_logfile="${log_dir}/samba.log"
fi

if [ "$zfs_property_tag" == '' ]; then
    zfs_property_tag='edu.wustl.nrg'
fi

if [ "$zfs_dataset_property" == "" ]; then
    zfs_dataset_property="${zfs_property_tag}:dataset"
fi

if [ "$zfs_replication_property" == "" ]; then
    zfs_replication_property="${zfs_property_tag}:replication"
fi

if [ "$zfs_replication_dataset_property" == "" ]; then
    zfs_replication_dataset_property="${zfs_property_tag}:replicationdataset"
fi

if [ "$zfs_replication_endpoints_property" == "" ]; then
    zfs_replication_endpoints_property="${zfs_property_tag}:replication:endpoints"
fi

if [ "$zfs_quota_property" == "" ]; then
    zfs_quota_property="${zfs_property_tag}:quota"
fi

if [ "$zfs_refquota_property" == "" ]; then
    zfs_refquota_property="${zfs_property_tag}:refquota"
fi

if [ "$zfs_quota_reports_property" == "" ]; then
    zfs_quota_reports_property="${zfs_property_tag}:quotareports"
fi

if [ "$zfs_quota_report_property" == "" ]; then
    zfs_quota_report_property="${zfs_property_tag}:quotareport"
fi

if [ "$zfs_trend_reports_property" == "" ]; then
    zfs_trend_reports_property="${zfs_property_tag}:trendreports"
fi

if [ "$zfs_trend_report_property" == "" ]; then
    zfs_trend_report_property="${zfs_property_tag}:trendreport"
fi

if [ "$zfs_snapshots_property" == "" ]; then
    zfs_snapshots_property="${zfs_property_tag}:snapshots"
fi

if [ "$zfs_snapshot_property" == "" ]; then
    zfs_snapshot_property="${zfs_property_tag}:snapshot"
fi

if [ "$zfs_cifs_property" == "" ]; then
    zfs_cifs_property="${zfs_property_tag}:cifs"
fi

if [ "$zfs_samba_server_prefix" == "" ]; then
    zfs_samba_server_prefix="ZFS-"
fi

if [ "$zfs_samba_server_suffix" == "" ]; then
    zfs_samba_server_suffix=""
fi

if [ "$zfs_samba_server_startup_timeout" == "" ]; then
    zfs_samba_server_startup_timeout="10"
fi

if [ "$zfs_cifs_default_share_template" == "" ]; then
    zfs_cifs_default_share_template="$TOOLS_ROOT/samba/default_share.conf.template"
fi

if [ "$zfs_samba_default_version" == "" ]; then
    zfs_samba_default_version='4.4.2'
fi

if [ "$zfs_vip_property" == "" ]; then
    zfs_vip_property="${zfs_property_tag}:vip"
fi

if [ "$zfs_replication_job_runner_cycle" == "" ]; then
    zfs_replication_job_runner_cycle="60"
fi

if [ "$zfs_replication_failure_limit" == "" ]; then
    zfs_replication_failure_limit="30m"
fi

if [ "$zfs_replication_queue_delay_count" == "" ]; then
    zfs_replication_queue_delay_count=2
fi

if [ "$zfs_replication_queue_max_count" == "" ]; then
    zfs_replication_queue_max_count=20
fi

if [ "$zfs_replication_suspended_error_time" == "" ]; then
    zfs_replication_suspended_error_time='360' # 6 hours
fi

if [ "$zfs_replication_completed_job_retention" == "" ]; then
    zfs_replication_completed_job_retention="-mtime +30"
fi

if [ "$zfs_replication_snapshot_name" == "" ]; then
    zfs_replication_snapshot_name=".ozmt-replication"
fi

if [ "$zfs_replication_sync_filelist" == "" ]; then
    zfs_replication_sync_filelist="/etc/hosts:/etc/ozmt/config.common:{pool}/etc/config.common"
fi

if [ "$zfs_replication_job_cleaner_cycle" == "" ]; then
    zfs_replication_job_cleaner_cycle="60"
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
    skip_pools="$(rpool) dump"
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

ozmt_init='true'

