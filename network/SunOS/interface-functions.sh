#! /bin/bash

# interface-functions.sh
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

# sourced by network scripts

physical_if () {
    # Tests if an interface is physical.
    # Returns 0 if physical, 0 otherwise
    dladm show-phys -p -o LINK | grep -q $1
    if [ $? -eq 0 ]; then
        debug "interface-functions.sh: physical_if interface $1 is physical"
        return 0
    else
        debug "interface-functions.sh: physical_if interface $1 is NOT physical"
        return 1
    fi  
}

set_mtu () {
    local interface="$1"
    local mtu="$2"
    local override="$3"
    local current_mtu=
    local temp=

    # Set and mtu on an interface to a higher value.  Only lowers the mtu if override='true'
    # MTU is a number, if prefixed with 'p' it will be set persistently over reboots.

    if [ "${mtu:0:1}" == 'p' ]; then
        temp=''
        mtu="${mtu:1}"
    else
        temp='-t'
    fi

    current_mtu=`dladm show-linkprop -c -o value -p mtu $interface`
    if [[ "$override" == 'true' || $mtu -gt $current_mtu ]]; then
        debug "Setting MTU to $mtu on $interface"
        dladm set-linkprop $temp -p mtu=$mtu $interface
    fi
    
}

activate_if () {
    local interface="$1"
    local if_def=
    local if_type=
    local if_name=
    local override_persistent="$2"

    debug "interface-functions.sh: activate_if $interface $override_persistent"

    if physical_if $interface; then
        ifconfig $interface 1>/dev/null 2>/dev/null
        if [ $? -eq 0 ]; then
            debug "interface-functions.sh: Physical network interface $interface already active"
        else
            ifconfig $interface plumb up
        fi
    else
        if_def="${interface_definition["$interface"]}"
        if [ "${if_def}" != "" ]; then
            if_type=`echo $if_def| ${CUT} -d ' ' -f 1`
            if_name=`echo $if_def| ${CUT} -d ' ' -f 2`
            case $if_type in 
                'vlan') 
                    activate_vlan $if_name $override_persistent
                    ;;
                'ipmp')
                    activate_ipmp $if_name $override_persistent
                    ;;
                'aggr')
                    activate_aggr $if_name $override_persistent
                    ;;
            esac
        else
            error "interface-functions.sh: Interface $interface not physical or defined in \$interface_definition"
        fi
    fi
}

deactivate_if () {
    local interface="$1"
    local if_def=
    local if_type=
    local if_name=
    local override_persistent="$2"

    debug "interface-functions.sh: activate_if $interface $override_persistent"

    if physical_if $interface; then
        ifconfig $interface 1>/dev/null 2>/dev/null
        if [ $? -eq 0 ]; then
            ifconfig $interface unplumb
        else
            debug "interface-functions.sh: Physical network interface $interface already inactive"
        fi
    else
        if_def="${interface_definition["$interface"]}"
        if [ "${if_def}" != "" ]; then
            if_type=`echo $if_def| ${CUT} -d ' ' -f 1`
            if_name=`echo $if_def| ${CUT} -d ' ' -f 2`
            case $if_type in
                'vlan')
                    deactivate_vlan $if_name $override_persistent
                    ;;
                'ipmp')
                    deactivate_ipmp $if_name $override_persistent
                    ;;
                'aggr')
                    deactivate_aggr $if_name $override_persistent
                    ;;
            esac
        else
            error "interface-functions.sh: Interface $interface not physical or defined in \$interface_definition"
        fi
    fi

}

activate_vlan () {
    local vlan_name="$1"
    local vlan_def=
    local vlan_interface=
    local vlan_tag=
    local vlan_mtu=
    local vlan_persistent=
    local persistent_set=
    local override_persistent="$2"

    debug "interface-functions.sh: activate_vlan $vlan_name $override_persistent"

    vlan_def="${vlan_definition["$vlan_name"]}"
    if [ "$vlan_def" != "" ]; then
        vlan_interface=`echo $vlan_def| ${CUT} -d ' ' -f 1`
        vlan_tag=`echo $vlan_def| ${CUT} -d ' ' -f 2`
        vlan_mtu=`echo $vlan_def| ${CUT} -d ' ' -f 3`
        if [ "$vlan_mtu" == "" ]; then
            vlan_mtu='1500'
        fi
        vlan_persistent="${vlan_definition["${vlan_name}_persistent"]}"
        if [ "$override_persistent" != "" ]; then
            vlan_persistent="$override_persistent"
        fi
        if [ "$vlan_persistent" == 'true' ]; then
            dladm show-vlan -P -p -o VID $vlan_name 1>${TMP}/persitent_vid_$$ 2>/dev/null 
            if [ $? -eq 0 ]; then
                if [ "$(cat ${TMP}/persitent_vid_$$)" != "$vlan_tag" ]; then
                    debug "interface-functions.sh: vlan $vlan_name is not persitently set to VID $vlan_tag, resetting"
                    dladm delete-vlan $vlan_name
                else
                    debug "interface-functions.sh: vlan $vlan_name is already set persistently to VID $vlan_tag, doing nothing"
                    persistent_set='true'
                    rm ${TMP}/persitent_vid_$$ 2>/dev/null
                fi
            fi
            rm ${TMP}/persitent_vid_$$ 2>/dev/null
        fi

        # Check current settings
        dladm show-vlan -p -o VID $vlan_name 1>${TMP}/current_vid_$$ 2>/dev/null
        if [ $? -eq 0 ]; then
            if [ "$(cat ${TMP}/current_vid_$$)" != "$vlan_tag" ]; then
                debug "interface-functions.sh: vlan $vlan_name is not set to VID $vlan_tag, resetting"
                dladm delete-vlan $vlan_name
            else
                debug "interface-functions.sh: vlan $vlan_name is already set to VID $vlan_tag, doing nothing"
                rm ${TMP}/current_vid_$$ 2>/dev/null
            fi
        fi
        rm ${TMP}/current_vid_$$ 2>/dev/null

        if [ "$(dladm show-vlan -p -o VID $vlan_name 2>/dev/null)" != "$vlan_tag" ]; then
            if [ $vlan_mtu -ne 1500 ]; then
                dladm set-linkprop -p mtu=$vlan_mtu $vlan_interface
            fi
            if [[ "$vlan_persistent" == 'true' ]]; then
                if [ "$persistent_set" == 'true' ]; then
                    # VLAN has been deleted temporarily, must destroy persistent record and recreate
                    dladm delete-vlan $vlan_name
                fi
                set_mtu "$vlan_interface" "p${vlan_mtu}"
                dladm create-vlan -l $vlan_interface -v $vlan_tag $vlan_name
                #ipadm create-ip $vlan_name
                #ipadm create-addr -T static -a 0.0.0.0/8 ${vlan_name}/v4
                #ipadm set-ifprop -p mtu=$(( $vlan_mtu - 8 )) -m ipv4 $vlan_name
            else
                set_mtu "$vlan_interface" "${vlan_mtu}"
                dladm create-vlan -t -l $vlan_interface -v $vlan_tag $vlan_name
                #ipadm create-ip $vlan_name
                #ipadm create-addr -t -T static -a 0.0.0.0/8 ${vlan_name}/v4
                #ipadm set-ifprop -t -p mtu=$(( $vlan_mtu - 8 )) -m ipv4 $vlan_name
            fi
        fi
        
    else
        error "interface-functions.sh: vlan definition not defined for $vlan_name"
        return 1
    fi
}

deactivate_vlan () {
    local vlan_name="$1"
    local vlan_def=
    local vlan_interface=
    local vlan_tag=
    local vlan_mtu=
    local vlan_persistent=
    local override_persistent="$2"

    debug "interface-functions.sh: dactivate_vlan $vlan_name $override_persistent"

    vlan_def="${vlan_definition["$vlan_name"]}"
    if [ "$vlan_def" != "" ]; then
        vlan_interface=`echo $vlan_def| ${CUT} -d ' ' -f 1`
        vlan_tag=`echo $vlan_def| ${CUT} -d ' ' -f 2`
        vlan_mtu=`echo $vlan_def| ${CUT} -d ' ' -f 3`
        if [ "$vlan_mtu" == "" ]; then
            vlan_mtu='1500'
        fi
        vlan_persistent="${vlan_definition["${vlan_name}_persistent"]}"
        if [ "$override_persistent" != "" ]; then
            vlan_persistent="$override_persistent"
        fi

        case $vlan_persistent in
            'remove')
                dladm show-vlan -P -p -o VID $vlan_name 1>${TMP}/current_vid_$$ 2>/dev/null
                if [ $? -eq 0 ]; then
                    ifconfig $vlan_name unplumb 2>/dev/null
                    dladm delete-vlan $vlan_name
                    return $?
                else
                    debug "interface-functions.sh: vlan $vlan_name is not active, doing nothing"
                    return 0
                fi
                ;;
            *)
                dladm show-vlan -p -o VID $vlan_name 1>${TMP}/current_vid_$$ 2>/dev/null
                if [ $? -eq 0 ]; then
                    ifconfig $vlan_name unplumb 2>/dev/null
                    dladm delete-vlan -t $vlan_name
                    return $?
                else
                    debug "interface-functions.sh: vlan $vlan_name is not active, doing nothing"
                    return 0
                fi
                ;;
        esac
    else
        error "interface-functions.sh: deactivate_vlan: definition not defined for $vlan_name"
        return 1
    fi
}

activate_ipmp () {
    local ipmp_name="$1"
    local ipmp_interfaces=
    local ipmp_persistent=
    local interface=
    local override_persistent="$2"

    debug "interface-functions.sh: activate_ipmp $ipmp_name $override_persistent"
    
    # This works for Illumos forks.  Under Oracle Solaris IPMP config was wrapped into crossbow and will be configured with dladm.

    ipmpstat -i -o GROUP -P 2>/dev/null | grep -q $ipmp_name
    if [ $? -eq 0 ]; then
        debug "interface-functions.sh: ipmp $ipmp_name already exists"
        return 1
    else
        ipmp_interfaces="${ipmp_definition["$ipmp_name"]}"
        ipmp_persistent="${ipmp_definition["${ipmp_name}_persistent"]}"
        if [ "$override_persistent" != "" ]; then
            debug "Overriding persistent from \"$ipmp_persistent\" to \"$override_persistent\""
            ipmp_persistent="$override_persistent"
        fi
        # Underlying interfaces need to be activated first
        for interface in $ipmp_interfaces; do
            activate_if "$interface" $ipmp_persistent
        done

        # Plumb the interface
        ifconfig $ipmp_name 2>/dev/null | grep -q "groupname $ipmp_name"
        if [ $? -ne 0 ]; then
            ifconfig $ipmp_name ipmp 0.0.0.0/0 up
        fi

        if [ "$ipmp_persistent" == 'true' ]; then
            echo "ipmp group ${ipmp_name} 0.0.0.0/0 up" > /etc/hostname.${ipmp_name}
        fi
        
        # Attach interfaces
        for interface in $ipmp_interfaces; do
            ifconfig $interface plumb
            ifconfig $interface -failover group $ipmp_name up
            if [ "$ipmp_persistent" == 'true' ]; then
                debug "setting interface $interface persitent in group $ipmp_name"
                echo "group $ipmp_name -failover up" > /etc/hostname.${interface}
            else
                rm /etc/hostname.${interface} 2>/dev/null
            fi
        done
    fi
}


deactivate_ipmp () {
    local ipmp_name="$1"
    local ipmp_interfaces=
    local ipmp_persistent=
    local interface=
    local override_persistent="$2"
    
    debug "interface-functions.sh: deactivate_ipmp $ipmp_name $override_persistent"
    
    ipmpstat -i -o GROUP -P 2>/dev/null | grep -q $ipmp_name
    if [ $? -eq 0 ]; then
        ipmp_interfaces="${ipmp_definition["$ipmp_name"]}"
        ipmp_persistent="${ipmp_definition["${ipmp_name}_persistent"]}"
        if [ "$override_persistent" != "" ]; then
            ipmp_persistent="$override_persistent"
        fi
        
        # Detach interfaces
        for interface in $ipmp_interfaces; do
            ifconfig $interface -failover group $ipmp_name unplumb
            if [ "$ipmp_persistent" == 'remove' ]; then
                rm /etc/hostname.${interface} 2>/dev/null
            fi
        done

        if [ "$ipmp_persistent" == 'remove' ]; then
            rm /etc/hostname.${ipmp_name} 2>/dev/null
        fi

        # Unplumb the interface
        ifconfig $ipmp_name unplumb

        # Deactivate underlying interfaces
        for interface in $ipmp_interfaces; do
            deactivate_if "$interface" "$ipmp_persistent"
        done
        
    else
        debug "interface-functions.sh: ipmp $ipmp_name does not exists"
        return 1
    fi
}   
