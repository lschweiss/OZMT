#! /bin/bash 

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

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

if [ "x$replication_logfile" != "x" ]; then
    logfile="$replication_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$replication_report" != "x" ]; then
    report_name="$replication_report"
else
    report_name="$default_report_name"
fi

if [ -f ${TOOLS_ROOT}/network/$os/interface-functions.sh ]; then
    source ${TOOLS_ROOT}/network/$os/interface-functions.sh
else
    error "vip-trigger.sh: unsupported OS: $os Need: ${TOOLS_ROOT}/network/$os/interface-functions.sh" 
    exit 1
fi

pools="$(pools)"

active_ip_dir="/var/zfs_tools/vip/active"

get_ip () {

    local ip_host="$1"
    local ip=

    if ! valid_ip $ip_host; then
        getent hosts $ip_hosts | ${AWK} -F " " '{print $1}' > ${TMP}/get_ip_$$
        if [ $? -eq 0 ]; then
            ip=`cat ${TMP}/get_ip_$$`
        else
            # Try DNS
            dig +short $host > ${TMP}/get_ip_$$
            if [ $? -eq 0 ]; then
                ip=`cat ${TMP}/get_ip_$$`
            else
                rm ${TMP}/get_ip_$$ 2> /dev/null
                echo "0"
                return 1
            fi
        fi
    else
        ip="$ip_host"
    fi

    rm ${TMP}/get_ip_$$ 2> /dev/null
    echo "$ip"

}

activate_vip () {

    local vIP_full="$1"
    local vIP=
    local netmask=
    local routes="$2"
    local ipifs="$3"
    local ipifs_list=
    local ipif=
    local vIP_dataset="$4"
    local ip_host=
    local ip=
    local alias=
    local available=
    local route=
    local routes=
    local host=
    local net=
    local mask=
    local gateway=
    local result=

    debug "activate_vip $1 $2 $3 $4"

    # TODO: Break out vIP / netmask

    IFS='/'
    read vIP netmask <<< "$vIP_full"
    unset IFS

   
    ip=`get_ip $vIP`

    if [ "$ip" == "0" ]; then
        error "vIP $vIP is not valid.  It is not an raw IP, in /etc/host or DNS resolvable."
        return 1
    fi

    if [ -f "${active_ip_dir}/${ip}" ]; then
        # vIP is already active
        if islocal $vIP; then
            debug "vIP already configured, doing nothing"
            return 0
        else
            warning "vIP already marked as active, but not configured. Activating vIP ${vIP}.  "
        fi
    fi

    # Make sure it is not already active elsewhere 

    # TODO:  Ping is not reliable.  We may not have an interface that can talk to it yet.
    #        Possibly replace with arping.   

    case $os in 
        'Linux')
            ping -c 1 -q -W 1 $vIP 1>/dev/null 2>/dev/null
            result=$?
            ;;
        'SunOS')
            ping $vIP 1>/dev/null 2>/dev/null
            result=$?
            ;;
        *)
            error "Unsupported OS, $os"
            return 1
            ;;      
    esac

    if [ $result -eq 0 ]; then
        # Make sure it is not local
        if islocal $vIP; then
            warning "Activating vIP ${vIP}, however, it is already active on this host."
        else
            error "Attempted to activate vIP ${vIP}, however, it is already active elsewhere."
            return 1
        fi
    fi

    # Split ipifs into newline separated list, so IFS switching isn't a problem in a loop

    ipifs_list=`echo "$ipifs" | sed 's/,/\n/g'`

    for ipif in $ipifs_list; do
        ip_host=`echo "$ipif" | cut -d '/' -f 1`
        ip_if=`echo "$ipif" | cut -d '/' -f 2`
        ifconfig ${ip_if} 1> /dev/null 2> /dev/null
        if [ $? -ne 0 ]; then
            activate_if $ip_if
        fi
        if [[ "$ip_host" == "$HOSTNAME" || "$ip_host" == '*' ]]; then
            alias=1
            available='false'
            while [ "$available" == 'false' ]; do
                # Find next IP alias
                case $os in
                    'Linux')
                        ifconfig ${ip_if}:${alias} | ${GREP} -q "inet addr:" 1>/dev/null 2>/dev/null
                        result=$?
                        ;;
                    'SunOS')
                        ifconfig ${ip_if}:${alias} 1>/dev/null 2>/dev/null
                        result=$?
                        ;;
                    *)
                        error "Unsupported OS, $os"
                        return 0
                        ;;
                esac
    
                if [ $result -eq 0 ]; then
                    alias=$(( alias + 1 ))
                else
                    available='true'
                fi
            done

            if valid_ip $netmask; then
                nm_def=" netmask $netmask"
            else
                nm_def="/${netmask}"
            fi
            
            # Assign the ip

            case $os in
                'Linux')
                    ifconfig ${ip_if}:${alias} ${ip}${nm_def} up
                    ;;
                'SunOS')
                    ifconfig ${ip_if}:${alias} plumb
                    ifconfig ${ip_if}:${alias} ${ip}${nm_def} up
                    ;;
            esac


        fi # if $ip_host

    done # for ipif

    # Set static routes
    IFS=','
    for route in $routes; do
        if [ "${route:0:1}" == "H" ]; then
            # Host route
            route="${route:1}"
            IFS='/'
            read -r host gateway <<< "$route"
            IFS=','
            case $os in
                'Linux')
                    route add -host ${host} $gateway dev ${ip_if}
                    ;;
                'SunOS')
                    route add -host $host $gateway -ifp ${ip_if} 
                    ;;
            esac
        else
            # Net route
            IFS='/'
            read -r net mask gateway <<< "$route"
            IFS=',' 
            case $os in
                'Linux')
                    route add -net ${net}/${mask} $gateway dev ${ip_if}
                    ;;
                'SunOS')
                    route add -net ${net}/${mask} $gateway -ifp ${ip_if}
                    ;;
            esac

        fi
    done  
    unset IFS 

    mkdir -p ${active_ip_dir}

    echo "${pool}|${vIP_dataset}|${vIP}/${netmask}|${routes}|${ipifs}" > "${active_ip_dir}/${ip}"

    return 0

}

deactivate_vip () {

    local vIP_full=
    local vIP_file=
    local vIP_dataset=
    local netmask=
    local routes=
    local ipifs=
    local ipif=
    local ip_host=
    local ip="$1"
    local alias=
    local available=
    local route=
    local routes=
    local host=
    local net=
    local mask=
    local gateway=

    debug "deactivate_vip $1"

    if [ ! -f "${active_ip_dir}/${ip}" ]; then
        # deactivating non active vIP 
        debug "vIP not active, doing nothing"
        return 0
    fi

    IFS='|'
    read -r pool vIP_dataset vIP_full routes ipifs < "${active_ip_dir}/${ip}"
    unset IFS

    IFS='/'
    read -r vIP netmask <<< "$vIP_full"
    unset IFS


    # Get the alias interface and shut it down
    case $os in
        'Linux')
            ipif=`ifconfig | ${GREP} -B 1 -F "inet addr:${ip}"|head -1|${AWK} -F ": " '{print $1}'`
            debug "Shutting down $ipif"
            ifconfig $ipif down
            ;;
        'SunOS')
            ipif=`ifconfig -a | ${GREP} -B 1 -F "inet ${ip}"|head -1|${AWK} -F ": " '{print $1}'`
            debug "Shutting down $ipif"
            ifconfig $ipif unplumb
            ;;
    esac

    rm -f "${active_ip_dir}/${ip}"

    # Remove the static routes
    IFS=','
    for route in $routes; do
        if [ "${route:0:1}" == "H" ]; then
            # Host route
            route="${route:1}"
            IFS='/'
            read -r host gateway <<< "$route"
            IFS=','
            case $os in
                'Linux')
                    route delete ${host} $gateway
                    ;;
                'SunOS')
                    route delete $host $gateway
                    ;;
            esac
        else
            # Net route
            IFS='/'
            read -r net mask gateway <<< "$route"
            IFS=','
            case $os in
                'Linux')
                    route delete ${net}/${mask} $gateway
                    ;;
                'SunOS')
                    route delete ${net}/${mask} $gateway 
                    ;;
            esac

        fi
    done
    unset IFS

}


process_vip () {

    local vip_file="$1"
    local pool=
    local dataset_name=
    local folder=
    local vip=
    local vIP=
    local routes=
    local ipifs=
    local t_vIP=
    local t_pool=
    local active_pool=
    local active_folder=

    debug "Processing: $vip_file"

    while read vip; do
        # Break down the vIP definition
        IFS='|'
        read -r pool dataset_name vIP routes ipifs <<< "${vip}"
        unset IFS

        debug "pool: $pool dataset: $dataset_name vIP: $vIP routes: $routes ipifs: $ipifs"
        if [[ $vIP == *","* ]]; then
            # vIP is pool attached
            IFS='/'
            read -r t_vIP t_pool <<< "$vIP"
            unset IFS
            debug "t_vIP: $t_vIP t_pool: $t_pool"
            echo "t_pool: $t_pool"
            echo "pools: $pools"
            if [[ $t_pool == *"$pools"* ]]; then
                activate_vip "$t_vIP" "$routes" "$ipifs" "$t_pool"
            else
                deactivate_vip "$t_vIP" "$t_pool"
            fi
        else
            # vIP is attached to the active dataset
            debug "vIP is attached to the dataset: $dataset_name"
            if [ -f "/${pool}/zfs_tools/var/replication/source/${dataset_name}" ]; then
                active_source=`cat /${pool}/zfs_tools/var/replication/source/${dataset_name}`
                IFS=':'
                read -r active_pool active_folder <<< "$active_source"
                unset IFS
                debug "active_pool: $active_pool active_folder: $active_folder"
                zfs get name ${active_pool}/${active_folder} 1> /dev/null 2> /dev/null
                if [ $? -eq 0 ]; then
                    debug "pool $pool is the active pool, activating vIP: $vIP"
                    activate_vip "$vIP" "$routes" "$ipifs" "$dataset_name"
                else
                    debug "pool $pool is NOT the active pool, deactivating vIP: $vIP"
                    deactivate_vip "$vIP"
                fi
            else
                debug "No source reference for dataset ${folder}  Deactivating vIP: $vIP"
                deactivate_vip "$vIP"
            fi
        fi
    done < "$vip_file"  # while read vip
    



}

###
###
##
## Main loop which checks the status of all vIPs and triggers changes
##
###
###

case $1 in
    "deactivate")
        # Deactive all vIPs on a specified pool or dataset
        active_vips=`ls -1 ${active_ip_dir} | sort `
        for vip in $active_vips; do
            debug "Deactivate: testing vIP $vip"
            IFS='|'
            read -r pool vIP_dataset vIP_full routes ipifs < "${active_ip_dir}/${vip}"
            unset IFS
            if [[ "$2" == "$pool" || "$2" == "$vIP_dataset" ]]; then
                deactivate_vip "${vip}"
            fi
        done
    ;;

    "activate")
        activate_vip "$2"
    ;;

    *)
        for pool in $pools; do
            vip_dir="/${pool}/zfs_tools/var/vip"
            if [ -d "$vip_dir" ]; then
                folders=`ls -1 "${vip_dir}" | sort`
                for folder in $folders; do
                    launch process_vip "${vip_dir}/${folder}" 
                done # for folder in $folders
            fi # if $vip_dir
        done # for pool in $pools
        
        debug "Processing active vIPs"
        
        active_vips=`ls -1 ${active_ip_dir} | sort `
        
        for vip in $active_vips; do
            launch process_vip "${active_ip_dir}/${vip}"
        done
    ;;

esac    





