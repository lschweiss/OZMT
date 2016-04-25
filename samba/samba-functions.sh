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


active_smb_dir="/var/zfs_tools/samba/active"
smb_datasets_dir="/var/zfs_tools/samba/datasets"
smb_datasets_lock="${TMP}/samba/datasets.lockfile"

samba_populate_datasets () {
    local pool=
    local zfs_folders=
    local folder=
    local datasets=
    local dataset=
    local cifs_property=

    mkdir -p ${TMP}/samba

    if [ ! -f ${smb_datasets_lock} ]; then
        touch ${smb_datasets_lock}
        init_lock ${smb_datasets_lock}
    fi


    wait_for_lock ${smb_datasets_lock}
    
    rm -f $smb_datasets_dir/*

    for pool in $pools; do
        debug "Collecting datasets for pool: $pool"
        # Collect zfs_folders with cifs property set
        zfs_folders=`zfs_cache get -r -H -o name -s local,received $zfs_cifs_property $pool 3>/dev/null`
        for folder in $zfs_folders; do
            debug "Checking folder: $folder"
            # Dataset is in this pool
            dataset=`zfs_cache get -H -o value -s local,received ${zfs_dataset_property} $folder 3>/dev/null`
            if [ "$dataset" != "" ]; then
                echo "$folder" > ${smb_datasets_dir}/${dataset}
            fi
        done # for folder
    done # for pool

    release_lock ${smb_datasets_lock}

}


samba_datasets () {

    local pool=
    local zfs_folders=
    local folder=
    local datasets=
    local dataset=
    local cifs_property=
    local result=1
    # Returns a list of datasets for a given input

    debug "Finding $1"

    wait_for_lock ${smb_datasets_lock}
    
    echo "${pools}" | ${GREP} -q $1
    if [ $? -eq 0 ]; then
        # Collecting dataset for a specified pool
        datasets=`${LS} -1 $smb_datasets_dir`
        for dataset in $datasets; do
            cat $smb_datasets_dir/$dataset | ${GREP} -q "^${1}/"
            if [ $? -eq 0 ]; then
                echo $dataset
            fi
        done
        result=0
    else
        # Single dataset specified.  Valid it.
        if [ -f $smb_datasets_dir/$1 ]; then
            echo $1
            result=0
        else
            result=1
        fi
    fi

    release_lock ${smb_datasets_lock}

    return $result

}

build_smb_conf () {

    local dataset_name="$1"
    wait_for_lock ${smb_datasets_lock}
    local zfs_folder=`cat ${smb_datasets_dir}/${dataset_name}`
    local dataset_mountpoint=`zfs_cache get -H -o value mountpoint $zfs_folder 3>/dev/null`
    local pool=`cat $smb_datasets_dir/$dataset_name | ${AWK} -F '/' '{print $1}'`
    release_lock ${smb_datasets_lock}
    local server_name=`zfs_cache get -H -o value -s local,received ${zfs_cifs_property} ${zfs_folder} 3>/dev/null`
    local smb_conf_dir="${dataset_mountpoint}/samba/etc/running"
    local server_conf="${smb_conf_dir}/smb_server.conf"
    local keytab_file=
    local cifs_template=
    local template_config_file=
    local shares=
    local shared_folder=
    local shared_folders=
    local cifs_share=
    local mountpoint=
    local share_config=
    local share_config_file=
    local smb_valid_users=
    local smb_admin_users=
    local smb_log_level=
    local smb_inherit_owner=
    local smbd_path=
    local nmbd_path=
    local winbindd_path=
    local conf_type=
    local conf_name=
    local vip_count=
    local interfaces=
    local x=
    local ip=
    local vip_host=

    if [ "$(zfs get -H -o value mounted $zfs_folder)" != 'yes' ]; then
        error "Dataset $dataset_name is not mounted on ${zfs_folder}.  Cannot start CIFS services."
        return 1
    fi

#    if [ -d /${pool}/zfs_tools/etc/samba/${dataset_name} ]; then
#        # Move the samba etc and var dirs into the dataset.
#        mkdir -p ${dataset_mountpoint}/samba
#        chmod 770 ${dataset_mountpoint}/samba
#        mv /${pool}/zfs_tools/etc/samba/${dataset_name} ${dataset_mountpoint}/samba/etc
#        mv /${pool}/zfs_tools/var/samba/${dataset_name} ${dataset_mountpoint}/samba/var
#    fi

    mkdir -p $smb_conf_dir
    

    # Build the smb_{dataset_name}.conf
    cifs_template=`zfs get -H -o value -s local,received ${zfs_cifs_property}:template ${zfs_folder}`
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
            #template_config_file="/${pool}/zfs_tools/etc/samba/${dataset_name}/${conf_name}"
            template_config_file="${dataset_mountpoint}/${conf_name}"
            ;;
        'pool')
            template_config_file="/${pool}/${conf_name}"
            ;;
        'system')
            template_config_file="${conf_name}"
            ;;
    esac
    if [ ! -f ${template_config_file} ]; then
        error "Missing cifs config file ${template_config_file} for dataset ${dataset_name}"
        continue
    fi

    smb_inherit_owner=`zfs get -H -o value -s local,received ${zfs_cifs_property}:inheritowner ${zfs_folder}`
    if [ "$smb_inherit_owner" == '' ]; then
        smb_inherit_owner='yes'
    fi
    smb_log_level=`zfs get -H -o value -s local,received ${zfs_cifs_property}:loglevel ${zfs_folder}`
    if [ "$smb_log_level" == '' ]; then
        smb_log_level='3'
    fi
    smb_admin_users=`zfs get -H -o value -s local,received ${zfs_cifs_property}:adminusers ${zfs_folder}`
    if [ "$smb_admin_users" == '-' ]; then
        smb_admin_users="$samba_admin_users"
    fi
    keytab_file=`zfs get -H -o value -s local,received ${zfs_cifs_property}:keytab ${zfs_folder}`
    if [ "$keytab_file"  == '' ]; then
        keytab_file="${dataset_mountpoint}/samba/etc/krb5.keytab"
    fi

    mountpoint=`zfs get -H -o value mountpoint ${zfs_folder}`
    


    if [[ "${template_config_file}" == *".template" ]]; then
        debug "template: ${template_config_file}"

        ${SED} s,#ZFS_FOLDER#,${zfs_folder},g "${template_config_file}" | \
            ${SED} s,#SERVER_NAME#,${server_name},g | \
            ${SED} s,#ADMIN_USERS#,${smb_admin_users},g | \
            ${SED} s,#INHERIT_OWNER#,${smb_inherit_owner},g | \
            ${SED} s,#LOG_LEVEL#,${smb_log_level},g | \
            ${SED} s,#KEYTAB#,${keytab_file},g | \
            ${SED} s,#MOUNTPOINT#,${mountpoint},g > \
            "${smb_conf_dir}/smb_${dataset_name}.conf"

    else
        cp "$template_config_file" "${smb_conf_dir}/smb_${dataset_name}.conf"
    fi

    # If no smb.conf for the dataset exists create an empty file
    if [ ! -f /${smb_conf_dir}/smb.conf ]; then
        touch /${smb_conf_dir}/smb.conf
    fi

    # Make sure template config line is in smb.conf
    cat ${smb_conf_dir}/smb.conf | ${GREP} "include =" | ${GREP} -q "smb_${dataset_name}.conf"
    if [ $? -ne 0 ]; then
        echo "    include = ${smb_conf_dir}/smb_${dataset_name}.conf" >> /${smb_conf_dir}/smb.conf
    fi

    # Make sure server config line is in smb.conf
    cat ${smb_conf_dir}/smb.conf | ${GREP} "include =" | ${GREP} -q "smb_server.conf"
    if [ $? -ne 0 ]; then
        echo "    include = ${smb_conf_dir}/smb_server.conf" >> /${smb_conf_dir}/smb.conf
    fi

    # Make sure share include line is in smb.conf
    cat ${smb_conf_dir}/smb.conf | ${GREP} "include =" | ${GREP} -q "smb_shares.conf"
    if [ $? -ne 0 ]; then
        echo "    include = ${smb_conf_dir}/smb_shares.conf" >> /${smb_conf_dir}/smb.conf
    fi

    # remove and rebuild share defintions
    rm -f /${smb_conf_dir}/smb_share*.conf



    ##
    # Construct shares config
    ##

    build_share_config () {

        debug "Adding share $cifs_share to $server_name for $mountpoint"
        IFS=':'
        read -r conf_type conf_name <<< "$share_config"
        unset IFS
        case $conf_type in
            'dataset')
                share_config_file="/${dataset_mountpoint}/${conf_name}"
                ;;
            'pool')
                share_config_file="/${pool}/${conf_name}"
                ;;
            'system')
                share_config_file="${conf_name}"
                ;;
            *)
                error "Invalid share config specified: $share_config"
                continue
                ;;
        esac
        if [ ! -f ${share_config_file} ]; then
            error "Missing cifs config file ${share_config_file} for dataset ${dataset_name} share ${cifs_share}"
            continue
        fi

        if [[ "${share_config_file}" == *".template" ]]; then
            debug "template: ${share_config_file}"

            smb_valid_users="$(echo -E $smb_valid_users | ${SED} -e 's/[\/&]/\\&/g')"
            smb_admin_users="$(echo -E $smb_admin_users | ${SED} -e 's/[\/&]/\\&/g')"

            #echo "validusers = $smb_valid_users"

            ${SED} s,#CIFS_SHARE#,${cifs_share},g "${share_config_file}" | \
                ${SED} s,#ZFS_FOLDER#,${zfs_folder},g | \
                ${SED} s,#SERVER_NAME#,${server_name},g | \
                ${SED} s,#MOUNTPOINT#,${mountpoint},g | \
                ${SED} "s%#VALID_USERS#%${smb_valid_users}%g" | \
                ${SED} "s%#ADMIN_USERS#%${smb_admin_users}%g" > \
                "${smb_conf_dir}/smb_share_${cifs_share}.conf"

        else
            cp "$share_config_file" "${smb_conf_dir}/smb_share_${cifs_share}.conf"
        fi
        echo "include = ${smb_conf_dir}/smb_share_${cifs_share}.conf" >> "${smb_conf_dir}/smb_shares.conf"


    }

    # New format all shares defined at the dataset level

    shares=`zfs get -H -o value -s local,received ${zfs_cifs_property}:shares ${zfs_folder}`

    if [ "$shares" != '-' ]; then
        x=1
        while [ $x -le $shares ]; do
    
            cifs_share=`zfs get -H -o value -s local,received ${zfs_cifs_property}:share:${x}:sharename ${zfs_folder}`
            mountpoint="$(zfs get -H -o value mountpoint ${zfs_folder})/$(zfs get -H -o value ${zfs_cifs_property}:share:${x}:path ${zfs_folder})"
            share_config=`zfs get -H -o value -s local,received ${zfs_cifs_property}:share:${x}:config ${zfs_folder}`
            smb_valid_users=`zfs get -H -o value -s local,received ${zfs_cifs_property}:share:${x}:validusers ${zfs_folder}`
            if [ "$smb_valid_users" == '-' ]; then
                smb_valid_users=''
            fi
            smb_admin_users=`zfs get -H -o value -s local,received ${zfs_cifs_property}:share:${x}:adminusers ${zfs_folder}`
            if [ "$smb_admin_users" == '-' ]; then
                smb_admin_users=''
            fi

            if [ "$cifs_share" != '-' ]; then
                debug "Using new share config"
                build_share_config
            fi
        
            x=$(( x + 1 ))
    
        done
    fi
        

    # Old format shares defined at zfs folder level.   This doesn't allow for shares on non-zfs folders.

    shared_folders=`zfs get -H -o name -s local,received -r ${zfs_cifs_property}:share ${zfs_folder}`
    debug "Shared folders: $shared_folders"
    for shared_folder in $shared_folders; do
        cifs_share=`echo "$shared_folder" | ${AWK} -F '/' '{print $NF}'`
        mountpoint=`zfs get -H -o value mountpoint ${shared_folder}`
        share_config=`zfs get -H -o value -s local,received ${zfs_cifs_property}:share ${shared_folder}`
        smb_valid_users=`zfs get -H -o value -s local,received ${zfs_cifs_property}:users ${shared_folder}`
        if [ "$smb_valid_users" == '-' ]; then
            smb_valid_users=''
        fi
        warning "Using old share config"
        build_share_config

    done

    ##
    # Build the smb_server.conf
    ##

    echo "private dir = ${dataset_mountpoint}/samba/var" > $server_conf
    echo "pid directory = /var/zfs_tools/samba/${dataset_name}/run" >> $server_conf
    echo "lock directory = ${dataset_mountpoint}/samba/var" >> $server_conf

    mkdir -p "${dataset_mountpoint}/samba/var/run"

    # Collect vIPs
    vip_count=`zfs_cache get -H -o value $zfs_vip_property ${zfs_folder} 3>/dev/null`
    interfaces=
    x=1
    while [ $x -le $vip_count ]; do
        ip=
        vip_host=`zfs_cache get -H -o value ${zfs_vip_property}:${x} ${zfs_folder} 3>/dev/null | ${CUT} -d '/' -f 1 `
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
            if ! islocal $ip; then
                error "vIP: $ip is not on this host.  Cannot start Samba for $dataset_name"
                exit 1
            fi
        fi
        x=$(( x + 1 ))
    done

    echo "interfaces =$interfaces" >> $server_conf
    echo "bind interfaces only = yes" >> $server_conf
    echo "netbios name = ${server_name}" >> $server_conf


}
