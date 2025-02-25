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


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )


. ../zfs-tools-init.sh

if [ "x$samba_logfile" != "x" ]; then
    logfile="$samba_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$samba_report" != "x" ]; then
    report_name="$samba_report"
else
    report_name="$default_report_name"
fi

now=`${DATE} +"%F %H:%M:%S%z"`

pools="$(pools)"

active_smb_dir="/var/zfs_tools/samba/active"
smb_datasets_dir="/var/zfs_tools/samba/datasets"
smb_datasets_lock="${TMP}/samba/datasets.lockfile"

MKDIR $active_smb_dir
MKDIR $smb_datasets_dir
MKDIR ${TMP}/samba

if [ ! -f ${smb_datasets_lock} ]; then
    touch ${smb_datasets_lock}
    init_lock ${smb_datasets_lock}
fi

source ./samba-functions.sh


##
# Functions used to start and stop samba services
##

start_smb_dataset () {

    local dataset_name="$1"
    
    wait_for_lock ${smb_datasets_lock}

    local zfs_folder=`cat ${smb_datasets_dir}/${dataset_name}`
    local dataset_mountpoint=`zfs_cache get -H -o value mountpoint $zfs_folder 3>/dev/null`
    local pool=`cat $smb_datasets_dir/$dataset_name | ${AWK} -F '/' '{print $1}'`

    release_lock ${smb_datasets_lock}

    local server_name=`zfs_cache get -H -o value -s local,received ${zfs_cifs_property} ${zfs_folder} 3>/dev/null`
    local active_smb="${active_smb_dir}/${dataset_name}"
    local smbd_bin=
    local smbd_pid=
    local nmbd_bin=
    local nmbd_pid=
    local winbindd_bin=
    local winbindd_pid=
    local smbd_running='false'
    local nmbd_running='false'
    local winbindd_running='false'
    #local smb_conf_dir="/${pool}/zfs_tools/etc/samba/$dataset_name/running"
    local smb_conf_dir="${dataset_mountpoint}/samba/etc/running"
    local server_conf=
    local cifs_template=
    local template_config_file=
    local shared_folder=
    local shared_folders=
    local cifs_share=
    local mountpoint=
    local share_config=
    local share_config_file=
    local smb_valid_users=
    local smbd_path=
    local nmbd_path=
    local lib_path=
    local conf_type=
    local conf_name=
    local vip_count=
    local interfaces=
    local x=
    local ip=
    local vip_host=
    local smb_pidfile=
    local nmb_pidfile=
    local smb_conf=
    local log_dir=


    if [ -f $active_smb ]; then
        # We have an active record for this dataset
        # Check if the server is running
        wait_for_lock $active_smb
        source $active_smb
        release_lock $active_smb

        if [ -f "/var/zfs_tools/samba/${dataset_name}/run/smbd.pid" ]; then
            smbd_pid=`cat /var/zfs_tools/samba/${dataset_name}/run/smbd.pid`
        fi
        if [ -f "/var/zfs_tools/samba/${dataset_name}/run/nmbd.pid" ]; then
            nmbd_pid=`cat /var/zfs_tools/samba/${dataset_name}/run/nmbd.pid`
        fi
        if [ -f "/var/zfs_tools/samba/${dataset_name}/run/winbindd.pid" ]; then
            nmbd_pid=`cat /var/zfs_tools/samba/${dataset_name}/run/winbindd.pid`
        fi

        # smbd
        if isrunning "/var/zfs_tools/samba/${dataset_name}/run/smbd.pid" "$smbd_bin"; then
            smbd_running='true'
        else
            warning "Samba smbd server for $dataset_name is defunct.   Restarting server."
            smbd_running='false'
            rm $active_smb 2> /dev/null
        fi
        # nmbd
        if isrunning "/var/zfs_tools/samba/${dataset_name}/run/nmbd.pid" "$nmbd_bin"; then
            if [ "$smbd_running" == 'false' ]; then
                warning "Samba nmbd server running, but smbd is defunct.  Killing nmbd and restarting both."
                kill $nmbd_pid
                nmbd_running='false'
            else
                nmbd_running='true'
            fi
        else
            warning "Samba nmbd server for $dataset_name is defunct.   Restarting server."
            nmbd_running='false'
            if [ "$smbd_running" == 'false' ]; then
                rm $active_smb 2> /dev/null
            fi
        fi
        #winbindd
        if isrunning "/var/zfs_tools/samba/${dataset_name}/run/winbindd.pid" "$winbindd_bin"; then
            if [ "$smbd_running" == 'false' ]; then
                warning "Samba winbindd server running, but smbd is defunct.  Killing winbindd and restarting both."
                kill $winbindd_pid
                winbindd_running='false'
            else
                winbindd_running='true'
            fi
        else
            warning "Samba winbindd server for $dataset_name is defunct.   Restarting server."
            winbindd_running='false'
            if [ "$smbd_running" == 'false' ]; then
                rm $active_smb 2> /dev/null
            fi
        fi
    else
        touch $active_smb
        init_lock $active_smb
        # no active record for this dataset
        smbd_running='false'
        nmbd_running='false'
        winbindd_running='false'
    fi # -f $active_smb

    ##
    # Start the smbd, nmbd and winbindd daemon
    ##
    if [[ "$smbd_running" == 'false' || "$nmbd_running" == 'false' || "$winbindd_running" == 'false' ]]; then
        build_smb_conf ${dataset_name}
        if [ $? -ne 0 ]; then
            return 1
        fi
    else
        debug "smbd, nmbd and winbindd running for $dataset_name"
    fi


    ##
    # Start smbd, nmbd, and winbindd
    ##

    MKDIR /var/zfs_tools/samba/${dataset_name}/run

    smb_pidfile="/var/zfs_tools/samba/${dataset_name}/run/smbd.pid"
    nmb_pidfile="/var/zfs_tools/samba/${dataset_name}/run/nmbd.pid"
    winbindd_pidfile="/var/zfs_tools/samba/${dataset_name}/run/winbindd.pid"

    smb_conf="${smb_conf_dir}/smb.conf"
    #log_dir="/${pool}/zfs_tools/var/samba/${dataset_name}/log"
    log_dir="${dataset_mountpoint}/samba/var/log"

    MKDIR $log_dir

    touch $active_smb

    # smbd
    smbd_path=`zfs_cache get -H -o value -s local,received ${zfs_cifs_property}:smbd ${zfs_folder} 3>/dev/null`
    if [ "$smbd_path" != '' ]; then
        debug "Overriding default smbd for: $smbd_path"
    else
        debug "smbd path: $SMBD"
        smbd_path="$SMBD"
    fi
    # nmbd
    nmbd_path=`zfs_cache get -H -o value -s local,received ${zfs_cifs_property}:nmbd ${zfs_folder} 3>/dev/null`
    if [ "$nmbd_path" != '' ]; then
        debug "Overriding default nmbd for: $smbd_path"
    else
        debug "nmbd path: $NMBD"
        nmbd_path="$NMBD"
    fi
    # winbindd
    winbindd_path=`zfs_cache get -H -o value -s local,received ${zfs_cifs_property}:winbindd ${zfs_folder} 3>/dev/null`
    if [ "$winbindd_path" != '' ]; then
        debug "Overriding default winbindd for: $winbindd_path"
    else
        debug "winbindd path: $WINBINDD"
        winbindd_path="$WINBINDD"
    fi

    # Lib path
    lib_path=`zfs_cache get -H -o value -s local,received ${zfs_cifs_property}:lib ${zfs_folder} 3>/dev/null`
    if [ "lib_path" != '' ]; then
        debug "LD_LIBRARY_PATH set to: $lib_path"
        export LD_LIBRARY_PATH=$lib_path
    else
        export LD_LIBRARY_PATH=
    fi

    # smbcontrol
    smbcontrol_path=`zfs_cache get -H -o value -s local,received ${zfs_cifs_property}:smbcontrol ${zfs_folder} 3>/dev/null`
    if [ "$smbcontrol_path" != '' ]; then
        debug "Overriding default smbcontrol for: $smbcontrol_path"
    else
        debug "smbcontrol path: $SMBCONTROL"
        smbcontrol_path="$SMBCONTROL"
    fi

    

    if [ "$smbd_running" == 'false' ]; then
        debug "Starting smbd"
        rm -f $smb_pidfile 2> /dev/null
        ${smbd_path} -D -s $smb_conf -l $log_dir &
        smbd_pid=`get_pid $smb_pidfile $zfs_samba_server_startup_timeout`
        smbd_running='true'
    fi

    if [ "$nmbd_running" == 'false' ]; then
        debug "Starting nmbd"
        rm -f $nmbd_pidfile 2> /dev/null
        ${nmbd_path} -D -s $smb_conf -l $log_dir &
        nmbd_pid=`get_pid $nmb_pidfile $zfs_samba_server_startup_timeout`
        nmbd_running='true'
    fi

    if [ "$winbindd_running" == 'false' ]; then
        debug "Starting winbindd"
        rm -f $winbindd_pidfile 2> /dev/null
        ${winbindd_path} -D -s $smb_conf -l $log_dir &
        winbindd_pid=`get_pid $nmb_pidfile $zfs_samba_server_startup_timeout`
        winbindd_running='true'
    fi

    # Turn on profiling    
    ${smbcontrol_path} all profile on

     
    update_job_status "$active_smb" "smbd_bin" "${smbd_path}" \
        "pool" "$pool" \
        "zfs_folder" "$zfs_folder" \
        "nmbd_bin" "${nmbd_path}" \
        "winbindd_bin" "${winbindd_path}"

}



stop_smb_dataset () {

    local dataset_name="$1"
    local smbd_pid=
    local smbd_bin=
    local nmbd_pid=
    local nmbd_bin=
    local winbindd_pid=
    local winbindd_bin=
    local pool=

    if [ ! -f ${active_smb_dir}/${dataset_name} ]; then
        debug "No active samba for $dataset_name"
        return 1
    fi

    source ${active_smb_dir}/${dataset_name}

    # Check if smbd, nmbd and winbindd is running
    if [ -f "/var/zfs_tools/samba/${dataset_name}/run/smbd.pid" ]; then
        smbd_pid=`cat /var/zfs_tools/samba/${dataset_name}/run/smbd.pid`
    fi
    if [ -f "/var/zfs_tools/samba/${dataset_name}/run/nmbd.pid" ]; then
        nmbd_pid=`cat /var/zfs_tools/samba/${dataset_name}/run/nmbd.pid`
    fi
    if [ -f "/var/zfs_tools/samba/${dataset_name}/run/winbindd.pid" ]; then
        winbindd_pid=`cat /var/zfs_tools/samba/${dataset_name}/run/winbindd.pid`
    fi

    # smbd
    if isrunning "/var/zfs_tools/samba/${dataset_name}/run/smbd.pid" "$smbd_bin"; then
        notice "Smbd process running for ${dataset_name}, sending kill to pid $smbd_pid"
        if [ "$DRY_RUN" == 'true' ]; then
            debug "Would have killed $smbd_pid"
        else
            kill $smbd_pid
        fi
    else
        debug "Smbd process NOT running for ${dataset_name}.  Doing nothing."
    fi
    # nmbd
    if isrunning "/var/zfs_tools/samba/${dataset_name}/run/nmbd.pid" "$nmbd_bin"; then
        notice "Nmbd process running for ${dataset_name}, sending kill to pid $nmbd_pid"
        if [ "$DRY_RUN" == 'true' ]; then
            debug "Would have killed $nmbd_pid"
        else
            kill $nmbd_pid
        fi
    else
        debug "Nmbd process NOT running for ${dataset_name}.  Doing nothing."
    fi
    # winbindd
    if isrunning "/var/zfs_tools/samba/${dataset_name}/run/winbindd.pid" "$winbindd_bin"; then
        notice "Winbindd process running for ${dataset_name}, sending kill to pid $winbindd_pid"
        if [ "$DRY_RUN" == 'true' ]; then
            debug "Would have killed $winbindd_pid"
        else
            kill $winbindd_pid
        fi
    else
        debug "Windbind process NOT running for ${dataset_name}.  Doing nothing."
    fi


    if [ "$DRY_RUN" != 'true' ]; then
        rm ${active_smb_dir}/${dataset_name}
    fi

}


restart_smb_dataset () {

    stop_smb_dataset $1
    start_smb_dataset $1

}

check_smb_dataset () {
    
    local dataset_name="$1"
    local pool=
    local active_smb="${active_smb_dir}/${dataset_name}"
    local start_smb='false'
    wait_for_lock ${smb_datasets_lock}
    local zfs_folder=`cat ${smb_datasets_dir}/${dataset_name}`
    release_lock ${smb_datasets_lock}
    local smbd_pid=
    local smbd_bin=
    local nmbd_pid=
    local nmbd_bin=
    local winbindd_pid=
    local winbindd_bin=
    local start_smb='false'
    local start_nmb='false'
    local start_winbindb='false'
    local vip_count=
    local x=
    local vip_host=
    local ip=

    if [ -f $active_smb ]; then
        source $active_smb
        # Check smbd
        if isrunning "/var/zfs_tools/samba/${dataset_name}/run/smbd.pid" $smbd_bin; then 
            debug "smbd is running for dataset $dataset_name"
        else
            error "smbd is NOT running for dataset ${dataset_name}. Restarting."
            start_smb='true'
        fi
        # Check nmbd
        if isrunning "/var/zfs_tools/samba/${dataset_name}/run/nmbd.pid" $nmbd_bin; then
            debug "nmbd is running for dataset $dataset_name"
        else
            error "nmbd is NOT running for dataset ${dataset_name}. Restarting."
            start_smb='true'
        fi
        # Check winbindd
        if isrunning "/var/zfs_tools/samba/${dataset_name}/run/winbindd.pid" $winbindd_bin; then
            debug "winbindd is running for dataset $dataset_name"
        else
            error "winbindd is NOT running for dataset ${dataset_name}. Restarting."
            start_smb='true'
        fi
    else
        debug "No active samba service for dataset $dataset"
        return 0
    fi

    # Check the vip(s)

    vip_count=`zfs_cache get -H -o value $zfs_vip_property ${zfs_folder} 3>/dev/null`
    x=1
    while [ $x -le $vip_count ]; do
        ip=
        vip_host=`zfs_cache get -H -o value ${zfs_vip_property}:${x} ${zfs_folder} | ${CUT} -d '/' -f 1 3>/dev/null`
        debug "vIP host: $vip_host"
        # Get this in IP form
        if valid_ip $vip_host; then
            ip="$vip_host"
        else
            # See if it's in /etc/hosts
            getent hosts $vip_host | ${AWK} -F " " '{print $1}' > ${TMP}/islocal_host_$$
            if [ $? -eq 0 ]; then
                ip=`cat ${TMP}/islocal_host_$$`
                rm ${TMP}/islocal_host_$$ 2>/dev/null
            else
                # Try DNS
                dig +short $vip_host > ${TMP}/islocal_host_$$
                if [ $? -eq 0 ]; then
                    ip=`cat ${TMP}/islocal_host_$$`
                    rm ${TMP}/islocal_host_$$ 2>/dev/null
                else
                    error "$vip_host is not valid.  It is not an raw IP, in /etc/host or DNS resolvable. Cannot stoping samba for $dataset_name"
                    rm ${TMP}/islocal_host_$$ 2>/dev/null
                    stop_smb_dataset $dataset_name
                    return 1
                fi
            fi
        fi

        debug "Samba interface IP: $ip"
        if [ "$ip" != "" ]; then
            debug "Checking ip: $ip"
            if ! islocal $ip; then
                warning "vIP: $ip is not on this host. Stopping Samba for $dataset_name"
                stop_smb_dataset $dataset_name
                return 1
            fi
        fi
        x=$(( x + 1 ))
    done

    # Start services

    if [ "$start_smb" == 'true' ]; then
        start_smb_dataset $dataset_name
        return 1
    fi


}



start_smb () {

    local name="$1"
    local dataset=
    local datasets=
    
    datasets=`samba_datasets $name`

    for dataset in $datasets; do
        debug "launch start_smb_dataset $dataset"
        launch start_smb_dataset $dataset 
    done

}


stop_smb () {

    local name="$1"
    local dataset=
    local datasets=

    datasets=`samba_datasets $name`

    for dataset in $datasets; do
        debug "launch stop_smb_dataset $dataset"
        launch stop_smb_dataset $dataset
    done

}

restart_smb () {

    local name="$1"
    local dataset=
    local datasets=

    datasets=`samba_datasets $name`

    for dataset in $datasets; do
        launch restart_smb_dataset $dataset
    done

}

check_smb () {

    local name="$1"
    local dataset=
    local datasets=
    local pool=

    debug "Check $name"

    if [ "$name" == "" ]; then
        debug "Checking on all pools"
        for pool in $pools; do
            debug "Checking pool $pool"
            launch check_smb $pool
        done
    else
        datasets=`samba_datasets $name`
    
        for dataset in $datasets; do
            debug "Checking dataset $dataset"
            launch check_smb_dataset $dataset
        done
    fi

}



###
###
##
## Main case statement to operate on Samba services
##
###
###

samba_populate_datasets

case $1 in
    'stop')
        stop_smb $2
    ;;

    'start')
        start_smb $2
    ;;

    'restart')
        restart_smb $2
    ;;

    'check')
        check_smb $2      
    ;;

    *)
        for pool in $pools; do
            start_smb $pool           
        done
    ;;

esac
