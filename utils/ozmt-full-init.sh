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
[ -z "$LS" ] && LS=`gnu_source ls`

[ -z "$GREP" ] && GREP=`gnu_source grep`

[ -z "$HEAD" ] && HEAD=`gnu_source head`

[ -z "$TAIL" ] && TAIL=`gnu_source tail`

[ -z "$TAC" ] && TAC=`gnu_source tac`

[ -z "$FIND" ] && FIND=`gnu_source find`

[ -z "$SED" ] && SED=`gnu_source sed`

[ -z "$AWK" ] && AWK=`gnu_source awk`

[ -z "$CUT" ] && CUT=`gnu_source cut`

[ -z "$SORT" ] && SORT=`gnu_source sort`

[ -z "$WC" ] && WC=`gnu_source wc`

[ -z "$TAC" ] && TAC=`gnu_source tac`

[ -z "$NL" ] && NL=`gnu_source nl`

[ -z "$STAT" ] && STAT=`gnu_source stat`

[ -z "$MUTT" ] && MUTT=`gnu_source mutt`

[ -z "$DATE" ] && DATE=`gnu_source date`

[ -z "$RSYNC" ] && RSYNC=`gnu_source rsync`

[ -z "$SSH" ] && SSH=`gnu_source ssh`

[ -z "$TIMEOUT" ] &&TIMEOUT=`gnu_source timeout`

[ -z "$MD5SUM" ] && MD5SUM=`gnu_source md5sum`

[ -z "$BC" ] && BC=`gnu_source bc`

[ -z "$BASENAME" ] && BASENAME=`gnu_source basename`

[ -z "$DIRNAME" ] && DIRNAME=`gnu_source dirname`

[ -z "$PARALLEL" ] && PARALLEL=`gnu_source parallel`

[ -z "$ARPING" ] && ARPING=`gnu_source arping`

[ -z "$DIALOG" ] && DIALOG=`gnu_source dialog`

[ -z "$bbcp" ] && bbcp=`gnu_source bbcp`

[ -z "$BBCP" ] && BBCP=`gnu_source bbcp`

[ -z "$mbuffer" ] && mbuffer=`gnu_source mbuffer` 

[ -z "$MBUFFER" ] && MBUFFER=`gnu_source mbuffer`

[ -z "$LSOF" ] && LSOF=`gnu_source lsof`

[ -z "$GROUPADD" ] && GROUPADD=`gnu_source groupadd`

[ -z "$lz4" ] && lz4=`gnu_source lz4`

[ -z "$LZ4" ] && LZ4=`gnu_source lz4`

[ -z "$gzip" ] && gzip=`gnu_source gzip`

[ -z "$GZIP" ] && GZIP=`gnu_source gzip`

[ -z "$TAR" ] && TAR=`gnu_source tar`

[ -z "$SMBD" ] && SMBD="/usr/local/samba/sbin/smbd"

[ -z "$NMBD" ] && NMBD="/usr/local/samba/sbin/nmbd"

[ -z "$WINBINDD" ] && WINBINDD="/usr/local/samba/sbin/winbindd"

[ -z "$SMBCONTROL" ] && SMBCONTROL="/usr/local/samba/bin/smbcontrol"

[ -z "$SAS2IRCU" ] && SAS2IRCU=`gnu_source sas2ircu`

[ -z "$SAS3IRCU" ] && SAS3IRCU=`gnu_source sas3ircu`



# Set defaults

[ -z "$debug_level" ] && debug_level=0

[ -z "$log_dir" ] && log_dir="/var/zfs_tools/log"

[ -z "$minimum_report_frequency" ] && minmum_report_frequency=1800

[ -z "$QUOTA_REPORT_TEMPLATE" ] && QUOTA_REPORT_TEMPLATE="$TOOLS_ROOT/reporting/quota-report.html"

[ -z "$QUOTA_AUTO_EXPAND_REQUIRED_FREE" ] && QUOTA_AUTO_EXPAND_REQUIRED_FREE="2T"

[ -z "$QUOTA_ALERT_TYPES" ] && QUOTA_ALERT_TYPES="warning critical"

[ -z "$DEBUG_EMAIL_LIMIT" ] && DEBUG_EMAIL_LIMIT="0" # Unlimited

[ -z "$NOTICE_EMAIL_LIMIT" ] && NOTICE_EMAIL_LIMIT="h3" # 3 identical per hour

[ -z "$WARNING_EMAIL_LIMIT" ] && WARNING_EMAIL_LIMIT="m5 h6" # 3 identical per hour

[ -z "$ERROR_EMAIL_LIMIT" ] && ERROR_EMAIL_LIMIT="m2 h3 d6" # 2 identical per minuted, 3 per hour, 6 per day

[ -z "$DEBUG_REPORT_LIMIT" ] && DEBUG_REPORT_LIMIT="0" # Unlimited

[ -z "$NOTICE_REPORT_LIMIT" ] && NOTICE_REPORT_LIMIT="h20" # 20 identical per hour

[ -z "$WARNING_REPORT_LIMIT" ] && WARNING_REPORT_LIMIT="m5 h10 d60" # 5 per minute, 10 per hour, 60 per day

[ -z "$ERROR_REPORT_LIMIT" ] && ERROR_REPORT_LIMIT="m5 h10 d60" # 5 per minute, 10 per hour, 60 per day

[ -z "$samba_report" ] && samba_report="Samba"

[ -z "$samba_logfile" ] && samba_logfile="${log_dir}/samba.log"

[ -z "$zfs_property_tag" ] && zfs_property_tag='edu.wustl.nrg'

[ -z "$zfs_dataset_property" ] && zfs_dataset_property="${zfs_property_tag}:dataset"

[ -z "$zfs_replication_property" ] && zfs_replication_property="${zfs_property_tag}:replication"

[ -z "$zfs_replication_dataset_property" ] && zfs_replication_dataset_property="${zfs_property_tag}:replicationdataset"

[ -z "$zfs_quota_property" ] && zfs_quota_property="${zfs_property_tag}:quota"

[ -z "$zfs_refquota_property" ] && zfs_refquota_property="${zfs_property_tag}:refquota"

[ -z "$zfs_quota_reports_property" ] && zfs_quota_reports_property="${zfs_property_tag}:quotareports"

[ -z "$zfs_quota_report_property" ] && zfs_quota_report_property="${zfs_property_tag}:quotareport"

[ -z "$zfs_trend_reports_property" ] && zfs_trend_reports_property="${zfs_property_tag}:trendreports"

[ -z "$zfs_trend_report_property" ] && zfs_trend_report_property="${zfs_property_tag}:trendreport"

[ -z "$zfs_snapshots_property" ] && zfs_snapshots_property="${zfs_property_tag}:snapshots"

[ -z "$zfs_snapshot_property" ] && zfs_snapshot_property="${zfs_property_tag}:snapshot"

[ -z "$zfs_cifs_property" ] && zfs_cifs_property="${zfs_property_tag}:cifs"

[ -z "$zfs_samba_server_prefix" ] && zfs_samba_server_prefix="ZFS-"

[ -z "$zfs_samba_server_suffix" ] && zfs_samba_server_suffix=""

[ -z "$zfs_samba_server_startup_timeout" ] && zfs_samba_server_startup_timeout="10"

[ -z "$zfs_cifs_default_share_template" ] && zfs_cifs_default_share_template="$TOOLS_ROOT/samba/default_share.conf.template"

[ -z "$zfs_samba_default_version" ] && zfs_samba_default_version='4.4.2'

[ -z "$zfs_vip_property" ] && zfs_vip_property="${zfs_property_tag}:vip"

[ -z "$zfs_replication_job_runner_cycle" ] && zfs_replication_job_runner_cycle="60"

[ -z "$zfs_replication_failure_limit" ] && zfs_replication_failure_limit="30m"

[ -z "$zfs_replication_queue_delay_count" ] && zfs_replication_queue_delay_count=2

[ -z "$zfs_replication_queue_max_count" ] && zfs_replication_queue_max_count=20

[ -z "$zfs_replication_suspended_error_time" ] && zfs_replication_suspended_error_time='360' # 6 hours

[ -z "$zfs_replication_completed_job_retention" ] && zfs_replication_completed_job_retention="-mtime +30"

[ -z "$zfs_replication_snapshot_name" ] && zfs_replication_snapshot_name=".ozmt-replication"

[ -z "$zfs_replication_sync_filelist" ] && zfs_replication_sync_filelist="/etc/hosts:/etc/ozmt/config.common:{pool}/etc/config.common"

[ -z "$zfs_replication_job_cleaner_cycle" ] &&  zfs_replication_job_cleaner_cycle="60"

[ -z "$suspend_all_jobs_timeout" ] && suspend_all_jobs_timeout=60


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
# Handle running as non-root user and ozmt group
##

if [ $UID -ne 0 ]; then
    groups | grep -q 'ozmt'
    if [ $? -ne 0 ]; then
        echo "Running OZMT as a non-root user.  This user must be a member of the ozmt group."
        echo "Please add $USER to the OZMT group"
    fi
else
    cat /etc/group | grep -q 'ozmt'
    if [ $? -ne 0 ]; then
        echo "Creating ozmt group, gid 69999"
        $GROUPADD -g 69999 ozmt 1>/dev/null
    fi
fi


##
# 
# Source other functions
#
##

source $TOOLS_ROOT/zfs-tools-functions.sh


MKDIR $log_dir


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

MKDIR ${TMP}

if [ -t 1 ]; then 
    if [ "$OZMTpath" != "" ]; then
        export OZMTpath="$TOOLS_ROOT/pool-filesystems:$TOOLS_ROOT/bin/${os}:$TOOLS_ROOT/3rdparty/tools"
        export PATH=$OZMTpath:$PATH
    fi
fi

ozmt_init='true'

