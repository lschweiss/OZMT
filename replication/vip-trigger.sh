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

pools="$(pools)"

activate_vip () {

    local vIP_full="$1"
    local vIP=
    local netmask=
    local routes="$2"
    local ipifs="$3"
    local ipif=
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

    # TODO: Break out vIP / netmask

    IFS='/'
    read vIP netmask <<< "$vIP_full"
    unset IFS


    if [ -f "/var/zfs_tools/vip/active/${vIP}" ]; then
        # vIP is already active
        return 0
    fi

    # Make sure it is not already active elsewhere 

    case $os in 
        'Linux')
            ping -c 1 -q -W 1 $vIP 1>/dev/null 2>/dev/null
            ;;
        'SunOS')
            ping $vIP 1>/dev/null 2>/dev/null
            ;;
        *)
            error "Unsupported OS, $os"
            return 1
            ;;      
    esac

    if [ $? -eq 0 ]; then
        # Make sure it is not local
        if islocal $vIP; then
            warning "Activating vIP ${vIP}, however, it is already active on this host."
        else
            error "Attempted to activate vIP ${vIP}, however, it is already active elsewhere."
            return 1
        fi
    fi

    IFS=','
    for ipif in $ipifs; do
        ip_host=`echo "$ipif" | cut -d '/' -f 1`
        ip_if=`echo "$ipif" | cut -d '/' -f 2`
        if [[ "$ip_host" == "$HOSTNAME" || "$ip_host" == '*' ]]; then
            # Validate the vIP
            if ! valid_ip $vIP; then
                getent hosts $vIP | ${AWK} -F " " '{print $1}' > ${TMP}/islocal_host_$$
                if [ $? -eq 0 ]; then
                    ip=`cat ${TMP}/islocal_host_$$`
                else
                    # Try DNS
                    dig +short $host > ${TMP}/islocal_host_$$
                    if [ $? -eq 0 ]; then
                        ip=`cat ${TMP}/islocal_host_$$`
                    else
                        error "vIP $vIP is not valid.  It is not an raw IP, in /etc/host or DNS resolvable."
                        return 1
                    fi
                fi
            else
                ip="$vIP"
            fi
            alias=1
            available='false'
            while [ "$available" == 'false' ]; do
                # Find next IP alias
                case $os in
                    'Linux')
                        ifconfig ${ip_if}:${alias} | ${GREP} -q "inet addr:"
                        ;;
                    'SunOS')
                        ifconfig ${ip_if}:${alias} 1>/dev/null 2>/dev/null
                        ;;
                    *)
                        error "Unsupported OS, $os"
                        return 0
                        ;;
                esac
    
                if [ $? -eq 0 ]; then
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
    unset IFS

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

    mkdir -p /var/zfs_tools/vip/active

    echo "${routes}|${ipifs}" > "/var/zfs_tools/vip/active/${vIP}"

    return 0

}

deactivate_vip () {

    local vIP_full="$1"
    local vIP=
    local netmask=
    local routes=
    local ipifs=
    local ipif=
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

    # TODO: Break out vIP / netmask

    IFS='/'
    read -r vIP netmask <<< "$vIP_full"
    unset IFS

    if [ ! -f "/var/zfs_tools/vip/active/${vIP}" ]; then
        # deactivating non active vIP 
        return 0
    fi

    IFS='|'
    read -r routes ipifs < "/var/zfs_tools/vip/active/${vIP}"
    unset IFS

    # Validate the vIP
    if ! valid_ip $vIP; then
        getent hosts $vIP | ${AWK} -F " " '{print $1}' > ${TMP}/islocal_host_$$
        if [ $? -eq 0 ]; then
            ip=`cat ${TMP}/islocal_host_$$`
        else
            # Try DNS
            dig +short $host > ${TMP}/islocal_host_$$
            if [ $? -eq 0 ]; then
                ip=`cat ${TMP}/islocal_host_$$`
            else
                error "vIP $vIP is not valid.  It is not an raw IP, in /etc/host or DNS resolvable."
                return 1
            fi
        fi
    else
        ip="$vIP"
    fi

    # Get the alias interface and shut it down
    case $os in
        'Linux')
            ipif=`ifconfig | ${GREP} -B 1 -F "inet addr:${ip}"|head -1|${AWK} -F ": " '{print $1}'`
            ifconfig $ipif down
            ;;
        'SunOS')
            ipif=`ifconfig -a | ${GREP} -B 1 -F "inet ${ip}"|head -1|${AWK} -F ": " '{print $1}'`
            ifconfig $ipif unplumb
            ;;
    esac

    rm -f "/var/zfs_tools/vip/active/${vIP}"

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

###
###
##
## Main loop which checks the status of all vIPs and triggers changes
##
###
###

for pool in $pools; do
    vip_dir="/${pool}/zfs_tools/var/replication/vip"
    folders=`ls -1 "${vip_dir}" | sort`
    for folder in $folders; do
        while read vip; do
            # Break down the vIP definition
            IFS='|'
            read -r vIP routes ipifs <<< "${vip}"
            unset IFS
            if [[ $vIP == *","* ]];then
                # vIP is pool attached
                IFS='/'
                read -r t_vIP t_pool <<< "$vIP"
                unset IFS
                if [[ $t_pool == *"$pools"* ]]; then 
                    activate_vip "$t_vIP" "$routes" "$ipifs"
                else
                    deactivate_vip "$t_vIP"
                fi
            else
                # vIP is attached to the active dataset
                if [ -f "/${pool}/zfs_tools/var/replication/source/${folder}" ]; then
                    # Get the dataset name
                    zfs get -H -o value $zfs_replication_dataset_property ${pool}/$(jobtofolder ${folder}) > ${TMP}/vip_dataset_$$ 2> /dev/null
                    if [ $? -ne 0 ]; then
                        # This is not the active dataset, we don't even have the dataset yet.
                        rm ${TMP}/vip_dataset_$$ 2> /dev/null
                        deactivate_vip "$vIP"
                        continue
                    else
                        dataset_name=`cat ${TMP}/vip_dataset_$$`
                        rm ${TMP}/vip_dataset_$$
                    fi
                    active_source=`cat /${pool}/zfs_tools/var/replication/source/${dataset_name}`
                    IFS='/'
                    read -r active_pool active_folder <<< "$active_source"
                    unset IFS
                    if [[ "$pool" == "$active_pool" && "$folder" == "$(jobtofolder $active_folder)" ]]; then
                        activate_vip "$vIP" "$routes" "$ipifs"
                    else
                        deactivate_vip "$vIP"
                    fi
                else
                    activate_vip "$vIP" "$routes" "$ipifs"
                fi
            fi
        done < "${vip_dir}/${folder}"  # while read vip
    done # for folder in $folders
done # for pool in $pools



