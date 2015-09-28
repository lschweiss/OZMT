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

mkdir -p $active_smb_dir


##
# Start any samba server for specified dataset or pool
##

activate_smb () {

    local smb_target="$1"
    local pool=
    local zfs_folder=
    local zfs_folders=
    local test_folders=
    local dataset_name=
    local active_smb=
    local smbd_pid=
    local nmbd_pid=
    local winbindd_pid=
    local smbd_bin=
    local nmbd_bin=
    local winbindd_bin=
    local smbd_running=
    local nmbd_running=
    local winbindd_running=
    local smb_conf_dir=
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
        

    # Is this a local pool?
    echo ${pools} | ${GREP} -q $smb_target
    if [ $? -eq 0 ]; then
        debug "Activating pool: $smb_target"
        pool="$smb_target"
        zfs_folders=`zfs_cache get -H -o name -s local -r ${zfs_cifs_property} ${pool}`
    else
        # smb_target is a dataset 
        # Find the pool with this dataset
        debug "Locating dataset: $smb_target"
        for pool in $pools; do
            debug "Checking pool: $pool"
            test_folders=`zfs_cache get -H -o name -s local -r ${zfs_cifs_property} ${pool}`
            for zfs_folder in $test_folders; do
                debug "    Checking folder: $zfs_folder"
                dataset_name=`zfs_cache get -H -o value -s local $zfs_replication_dataset_property ${zfs_folder}`
                if [ "$dataset_name" == "$smb_target" ]; then
                    zfs_folders="$zfs_folder"
                    debug "  Found dataset folder: $zfs_folder"
                    break
                fi
            done
            if [ "$zfs_folders" != "" ]; then
                break
            fi
        done
    fi

    if [ "$zfs_folders" == "" ]; then
        debug "activate_smb: Could not find $smb_target on this host"
        return 1
    fi
    

    for zfs_folder in $zfs_folders; do
        debug "Configuring CIFS for $zfs_folder"
        dataset_name=`zfs_cache get -H -o value -s local $zfs_replication_dataset_property ${zfs_folder}`
        server_name=`zfs_cache get -H -o value -s local ${zfs_cifs_property} ${zfs_folder}`
        active_smb="${active_smb_dir}/${dataset_name}"
        if [ -f $active_smb ]; then
            smbd_pid=
            nmbd_pid=
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
    
            debug "smbd.bin = $smbd_bin"
            debug "smbd.pid = $smbd_pid"
            debug "nmbd.bin = $nmbd_bin"
            debug "nmbd.pid = $nmbd_pid"
            debug "winbindd.bin = $winbindd_bin"
            debug "winbindd.pid = $winbindd_pid"

            case $os in 
                SunOS)
                    # smbd
                    if [[ -f /proc/${smbd_pid}/path/a.out && "$smbd_bin" == `ls -l /proc/${smbd_pid}/path/a.out| ${AWK} '{print $11}'` ]]; then
                        smbd_running='true'
                    else
                        warning "Samba smbd server for $dataset_name is defunct.   Restarting server."
                        smbd_running='false'
                        rm $active_smb 2> /dev/null
                    fi
                    # nmbd
                    if [[ -f /proc/${nmbd_pid}/path/a.out && "$nmbd_bin" == `ls -l /proc/${nmbd_pid}/path/a.out| ${AWK} '{print $11}'` ]]; then
                        if [ "$smbd_running" == 'false' ]; then
                            warning "Samba nmbd server running, but smbd is defunt.  Killing nmbd and restarting both."
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
                    if [[ -f /proc/${winbindd_pid}/path/a.out && "$winbindd_bin" == `ls -l /proc/${winbindd_pid}/path/a.out| ${AWK} '{print $11}'` ]]; then
                        if [ "$smbd_running" == 'false' ]; then
                            warning "Samba winbindd server running, but smbd is defunt.  Killing winbindd and restarting both."
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
                    ;;
                *)
                    error "Unsupported operating system for samba: $os"
                    exit 1
                    ;;
            esac
        else
            touch $active_smb
            init_lock $active_smb
            # no active record for this dataset
            smbd_running='false'
            nmbd_running='false'
            winbindd_running='false'
        fi

        ##
        # Start the smbd, nmbd and winbindd daemon
        ##

        if [[ "$smbd_running" == 'false' || "$nmbd_running" == 'false' || "$winbindd_running" == 'false' ]]; then
            # Start samba for this dataset
            smb_conf_dir="/${pool}/zfs_tools/etc/samba/$dataset_name"
            server_conf="$smb_conf_dir/smb_server.conf"

            # Build the smb_{dataset_name}.conf
            cifs_template=`zfs get -H -o value -s local ${zfs_cifs_property}:template ${zfs_folder}`
            if [ "$cifs_template" == "" ]; then
                error "Missing cifs template definition for dataset $dataset_name"
                continue
            fi

            IFS=':'
            read -r conf_type conf_name <<< "$cifs_template"
            unset IFS

            debug "Config type: $conf_type  Config name: $conf_name"
        
            case $conf_type in
                'dataset')
                    template_config_file="/${pool}/zfs_tools/etc/samba/${dataset_name}/${conf_name}"
                    ;;
                'pool')
                    template_config_file="/${pool}/zfs_tools/etc/samba/${conf_name}"
                    ;;
                'system')
                    template_config_file="/etc/ozmt/samba/${conf_name}"
                    ;;
            esac
            if [ ! -f ${template_config_file} ]; then
                error "Missing cifs config file ${template_config_file} for dataset ${dataset_name}"
                continue
            fi

            if [[ "${template_config_file}" == *".template" ]]; then
                debug "template: ${template_config_file}"

                ${SED} s,#ZFS_FOLDER#,${zfs_folder},g "${template_config_file}" | \
                    ${SED} s,#SERVER_NAME#,${server_name},g > \
                    "${smb_conf_dir}/smb_${dataset_name}.conf"

            else
                cp "$template_config_file" "${smb_conf_dir}/smb_${dataset_name}.conf"
            fi

            # If no smb.conf for the dataset exists create an empty file
            if [ ! -f /${smb_conf_dir}/smb.conf ]; then
                touch /${smb_conf_dir}/smb.conf
            fi

            # Make sure template config line is in smb.conf
            cat /${smb_conf_dir}/smb.conf | ${GREP} "include =" | ${GREP} -q "smb_${dataset_name}.conf"
            if [ $? -ne 0 ]; then
                echo "    include = /${pool}/zfs_tools/etc/samba/$dataset_name/smb_${dataset_name}.conf" >> /${smb_conf_dir}/smb.conf
            fi

            # Make sure server config line is in smb.conf
            cat /${smb_conf_dir}/smb.conf | ${GREP} "include =" | ${GREP} -q "smb_server.conf"
            if [ $? -ne 0 ]; then
                echo "    include = /${pool}/zfs_tools/etc/samba/$dataset_name/smb_server.conf" >> /${smb_conf_dir}/smb.conf
            fi

            # Make sure share include line is in smb.conf
            cat /${smb_conf_dir}/smb.conf | ${GREP} "include =" | ${GREP} -q "smb_shares.conf"
            if [ $? -ne 0 ]; then
                echo "    include = /${pool}/zfs_tools/etc/samba/$dataset_name/smb_shares.conf" >> /${smb_conf_dir}/smb.conf
            fi

            # remove and rebuild share defintions
            rm -f /${smb_conf_dir}/smb_share*.conf

            # Construct shares config
            shared_folders=`zfs get -H -o name -s local -r ${zfs_cifs_property}:share ${zfs_folder}`
            debug "Shared folders: $shared_folders"
            for shared_folder in $shared_folders; do
                cifs_share=`echo "$shared_folder" | ${AWK} -F '/' '{print $NF}'`
                mountpoint=`zfs_cache get -H -o value mountpoint ${shared_folder}`
                share_config=`zfs get -H -o value -s local ${zfs_cifs_property}:share ${shared_folder}`
                smb_valid_users=`zfs get -H -o value -s local ${zfs_cifs_property}:users ${shared_folder}`
                if [ "$smb_valid_users" == '-' ]; then
                    smb_valid_users=''
                fi
                # smbd
                smbd_path=`zfs get -H -o value -s local ${zfs_cifs_property}:smbd ${shared_folder}`
                if [ "$smbd_path" != '' ]; then
                    debug "Overriding default smbd for: $smbd_path"
                else
                    debug "smbd path: $SMBD"
                    smbd_path="$SMBD"
                fi
                # nmbd
                nmbd_path=`zfs get -H -o value -s local ${zfs_cifs_property}:nmbd ${shared_folder}`
                if [ "$nmbd_path" != '' ]; then
                    debug "Overriding default nmbd for: $smbd_path"
                else
                    nmbd_path="$NMBD"
                fi
                # winbindd
                winbindd_path=`zfs get -H -o value -s local ${zfs_cifs_property}:winbindd ${shared_folder}`
                if [ "$winbindd_path" != '' ]; then
                    debug "Overriding default winbindd for: $winbindd_path"
                else
                    winbindd_path="$WINBINDD"
                fi
            
                debug "Adding share $cifs_share to $server_name for $mountpoint"
                IFS=':'
                read -r conf_type conf_name <<< "$share_config"
                unset IFS
                case $conf_type in
                    'dataset')
                        share_config_file="/${pool}/zfs_tools/etc/samba/${dataset_name}/${conf_name}"
                        ;;
                    'pool')
                        share_config_file="/${pool}/zfs_tools/etc/samba/${conf_name}"
                        ;;
                    'system')
                        share_config_file="/etc/ozmt/samba/${conf_name}"
                        ;;
                esac
                if [ ! -f ${share_config_file} ]; then
                    error "Missing cifs config file ${share_config_file} for dataset ${dataset_name} share ${cifs_share}"
                    continue
                fi

                if [[ "${share_config_file}" == *".template" ]]; then
                    debug "template: ${share_config_file}"

                    ${SED} s,#CIFS_SHARE#,${cifs_share},g "${share_config_file}" | \
                        ${SED} s,#ZFS_FOLDER#,${zfs_folder},g | \
                        ${SED} s,#SERVER_NAME#,${server_name},g | \
                        ${SED} s,#MOUNTPOINT#,${mountpoint},g | \
                        ${SED} "s%#VALID_USERS#%${smb_valid_users}%g" > \
                        "${smb_conf_dir}/smb_share_${cifs_share}.conf"

                else
                    cp "$share_config_file" "${smb_conf_dir}/smb_share_${cifs_share}.conf"
                fi
                echo "include = ${smb_conf_dir}/smb_share_${cifs_share}.conf" >> "${smb_conf_dir}/smb_shares.conf"
            done

            ##
            # Build the smb_server.conf
            ##
            
            echo "private dir = /${pool}/zfs_tools/var/samba/${dataset_name}" > $server_conf
            echo "pid directory = /var/zfs_tools/samba/${dataset_name}/run" >> $server_conf
            echo "lock directory = /${pool}/zfs_tools/var/samba/${dataset_name}" >> $server_conf
            
            # Collect vIPs
    
            vip_count=`zfs_cache get -H -o value $zfs_vip_property ${zfs_folder}`
            interfaces=
            x=1
            while [ $x -le $vip_count ]; do
                ip=
                vip_host=`zfs_cache get -H -o value ${zfs_vip_property}:${x} ${zfs_folder} | ${CUT} -d '/' -f 1`
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
                            error "$vip_host is not valid.  It is not an raw IP, in /etc/host or DNS resolvable. Cannot configure cifs for $dataset_name share ${cifs_share}"
                            rm ${TMP}/islocal_host_$$ 2>/dev/null
                            
                        fi
                    fi
                fi

                debug "Samba interface IP: $ip"
                
                if [ "$ip" != "" ]; then
                    debug "Adding $ip to interfaces"
                    interfaces="$interfaces $ip"
                fi
                x=$(( x + 1 ))
            done 
          
            echo "interfaces =$interfaces" >> $server_conf
            echo "bind interfaces only = yes" >> $server_conf
            echo "netbios name = ${server_name}" >> $server_conf

        else
            debug "smbd and nmbd running for $dataset_name"
        fi
                        

        ##
        # Start smbd, nmbd, and winbindd
        ##

        mkdir -p /var/zfs_tools/samba/${dataset_name}/run

        smb_pidfile="/var/zfs_tools/samba/${dataset_name}/run/smbd.pid"
        nmb_pidfile="/var/zfs_tools/samba/${dataset_name}/run/nmbd.pid"
        winbindd_pidfile="/var/zfs_tools/samba/${dataset_name}/run/winbindd.pid"

        smb_conf="${smb_conf_dir}/smb.conf"
        log_dir="/${pool}/zfs_tools/var/samba/${dataset_name}/log" 

        mkdir -p $log_dir

        touch $active_smb
    
        if [ "$smbd_running" == 'false' ]; then
            debug "Starting smbd"
            rm -f $smb_pidfile 2> /dev/null
            ${smbd_path} -D -s $smb_conf -l $log_dir &
            smbd_pid=`get_pid $smb_pidfile $zfs_samba_server_startup_timeout`
            smbd_running='true'
            update_job_status "$active_smb" "smbd_bin" "${smbd_path}"
            update_job_status "$active_smb" "pool" "$pool" 
        fi

        if [ "$nmbd_running" == 'false' ]; then
            debug "Starting nmbd"
            rm -f $nmbd_pidfile 2> /dev/null
            ${nmbd_path} -D -s $smb_conf -l $log_dir &
            nmbd_pid=`get_pid $nmb_pidfile $zfs_samba_server_startup_timeout`
            nmbd_running='true'
            update_job_status "$active_smb" "nmbd_bin" "${nmbd_path}"
        fi

        if [ "$winbindd_running" == 'false' ]; then
            debug "Starting winbindd"
            rm -f $winbindd_pidfile 2> /dev/null
            ${winbindd_path} -D -s $smb_conf -l $log_dir &
            winbindd_pid=`get_pid $nmb_pidfile $zfs_samba_server_startup_timeout`
            winbindd_running='true'
            update_job_status "$active_smb" "winbindd_bin" "${winbindd_path}"
        fi

    done 

}


deactivate_smb () {

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


    debug "smbd.bin = $smbd_bin"
    debug "smbd.pid = $smbd_pid"
    debug "nmbd.bin = $nmbd_bin"
    debug "nmbd.pid = $nmbd_pid"
    debug "winbindd.bin = $winbindd_bin"
    debug "winbindd.pid = $winbindd_pid"

    case $os in
        SunOS)
            # smbd
            if [[ -f /proc/${smbd_pid}/path/a.out && "$smbd_bin" == `ls -l /proc/${smbd_pid}/path/a.out| ${AWK} '{print $11}'` ]]; then
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
            if [[ -f /proc/${nmbd_pid}/path/a.out && "$nmbd_bin" == `ls -l /proc/${nmbd_pid}/path/a.out| ${AWK} '{print $11}'` ]]; then
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
            if [[ -f /proc/${winbindd_pid}/path/a.out && "$winbindd_bin" == `ls -l /proc/${winbindd_pid}/path/a.out| ${AWK} '{print $11}'` ]]; then
                notice "Winbindd process running for ${dataset_name}, sending kill to pid $winbindd_pid"
                if [ "$DRY_RUN" == 'true' ]; then
                    debug "Would have killed $winbindd_pid"
                else
                    kill $winbindd_pid
                fi
            else
                debug "Nmbd process NOT running for ${dataset_name}.  Doing nothing."
            fi
            
            ;;
        *)
            error "Unsupported operating system for samba: $os"
            exit 1
            ;;
    esac

    if [ "$DRY_RUN" != 'true' ]; then
        rm ${active_smb_dir}/${dataset_name}    
    fi

}


###
###
##
## Main loop which checks the status of all samba servers and triggers changes
##
###
###

case $1 in
    "deactivate")
        # Deactive all samba servers on a specified pool or dataset
        active_smbs=`ls -1 $active_smb_dir | ${GREP} -v '\.lock\|\.unlock'`
        debug "Active samba servers: $active_smbs"
        for smb in $active_smbs; do
            debug "Checking if $smb matches"
            source ${active_smb_dir}/${smb}
            if [ "$DEBUG" == 'true' ]; then
                cat ${active_smb_dir}/${smb}
            fi
            if [[ "$2" == "$smb" || "$2" == "$pool" ]]; then
                debug "Deactivating: $smb"
                deactivate_smb $smb
            fi
        done
        # If we got here we didn't match any active samba servers
        debug "deactivate \"$2\" did not match any pool or datasets with active samba servers"
        exit 1
    ;;

    "activate")
        debug "Activating: $2"
        activate_smb "$2"
    ;;

    *)
        for pool in $pools; do
            activate_smb $pool
        done
    ;;

esac
