#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2018  Chip Schweiss

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


vip_usage () {
    local snap=
    if [ -t 1 ]; then
        cat ${TOOLS_ROOT}/vip/USAGE
    fi
}

interface_to_vlan () {
    local i="$1"
    
    if [[ "$i" == *"vlan"* ]]; then
        # Strip everything but the vlan #
        echo "$i" | ${AWK} -F 'vlan' '{print $2}' | ${AWK} -F 'i' '{print $1}'
    elif [[ "$i" == *"/"* ]]; then
        # Strip host portion
        echo "$i" | ${AWK} -F '/' '{print $2}'
    else
        echo $i
    fi

}
    
show_vip () {

    local zfs_folder="$1"
    local folder=
    local folders=
    local recursive="$2"
    local result=
    local has_vip=
    local count=
    local vip_data=
    local vip=
    local routes=
    local interfaces=


    # Test folder exists
    zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        warning "show_vip called on non-existant zfs folder $zfs_folder"
        vip_usage
        return 1
    fi

    if [[ "$recursive" != "" && "$recursive" != "-r" ]]; then
        warning "show_vip called with invalid parameter $recursive"
        vip_usage
        return 1
    fi
    
    folders=`zfs list -o name -H ${recursive} ${zfs_folder}`

    for folder in $folders; do
        has_vip='false'
        count=`zfs get -o value -H -s local,received ${zfs_vip_property} $folder`
        if [ "$count" != '' ]; then
            has_vip='true'
            printf '%-50s | %-10s | %5s\n'  ${folder} "${count} vIPs" ""
            x=1
            while [ $x -le $count ]; do
                vip_data=`zfs get -o value -H -s local,received ${zfs_vip_property}:${x} $folder`
                vip=`echo $vip_data | ${AWK} -F '|' '{print $1}'`
                routes=`echo $vip_data | ${AWK} -F '|' '{print $2}'`
                interfaces=`echo $vip_data | ${AWK} -F '|' '{print $3}'`
                
                printf '%28s  %-20s | %-10s | %-50s\n' "$x" "$vip" "VLAN $(interface_to_vlan "${interfaces}")"
                if [ "$routes" != '' ]; then
                    r=1
                    IFS=','
                    for route in $routes; do
                        if [ $r -eq 1 ]; then
                            printf '%50s | %-50s \n' "Routes: " "$route"
                        else
                            printf '%-50s | %-50s \n' "" "$route"
                        fi
                        r=$(( r + 1 ))
                    done
                    unset IFS
                fi
                
                x=$(( x  + 1 ))
            done
            echo
        fi
    done 


}

add_mod_vip () {

    local zfs_folder="$1"
    shift 
    local vip=
    local vips=0
    local routes=0

    zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null 
    if [ $? -ne 0 ]; then
        warning "add_mod_vip called on non-existant ZFS folder $zfs_folder"
        vip_usage
        return 1
    fi
    
    declare -A vip
    
    while getopts v:r:g:i: opt; do
        case $opt in
            v)  # vIP
                vips=$(( vips + 1 ))
                routes=0
                vip[${vips},addr]="$OPTARG"
                debug "vIP #${vips}: ${vip[${vips},addr]}"
                ;;
            r)  # route
                routes=$(( routes + 1 ))
                vip[${vips},route,${routes}]="$OPTARG"
                vip[${vips},routes]=$routes
                debug "vIP #${vips} route #${routes}: ${vip[${vips},route,${routes}]}"
                ;;
            g)  # gateway
                vip[${vips},gw,${routes}]="$OPTARG"
                debug "vIP #${vips} gateway #${routes}: ${vip[${vips},gw,${routes}]}"
                ;;
            i)  # interface VLAN
                vip[${vips},vlan]="$OPTARG"
                debug "vIP #${vips} interface VLAN: ${OPTARG}"
                ;;
    
            ?)  # Show program usage and exit
                vip_usage
                exit 0
                ;;
            :)  # Mandatory arguments not specified
                die "${job_name}: Option -$OPTARG requires an argument."
                ;;
        esac
    done

    current_vips=`zfs get -o value -H -s local,received ${zfs_vip_property} $zfs_folder`
    [ "$current_vips" == '' ] && current_vips=0
    



    # Cycle through each provided vIP and add or modify
    vip=1
    while [ $vip -le $vips ]; do
        routes=${vip[${vip},routes]}
        if [ "$routes" != '' ]; then
            route=1
            while [ $route -le $routes ]; do
                if [ -f "/etc/ozmt/network/${vip[${vip},route,${route}]}.routes" ]; then
                    route_prop="${vip[${vip},route,${route}]}"
                else
                    route_prop="${vip[${vip},route,${route}]}/${vip[${vip},gw,${route}]}"
                fi
                if [ $route -eq 1 ]; then
                    vip_property="${vip[${vip},addr]}|${route_prop}"
                else
                    vip_property="${vip_property},${route_prop}"
                fi
                route=$(( route + 1 ))
            done
        else
            vip_property="${vip[${vip},addr]}|"
        fi
        vip_property="${vip_property}|${vip[${vip},vlan]}"
        
        # See if this VIP exists 
        x=1
        new='true'
        while [ $x -le $current_vips ]; do
            this_vip_data=`zfs get -o value -H -s local,received ${zfs_vip_property}:${x} $zfs_folder`
            this_vip=`echo $this_vip_data | ${AWK} -F '|' '{print $1}'`
            if [ "${vip[${vip},addr]}" == "$this_vip" ]; then
                # We are modifying an existing vIP
                zfs set ${zfs_vip_property}:${x}="$vip_property" $zfs_folder
                debug "Modified ${x}: $this_vip on $zfs_folder: $vip_property"
                new='false'
                break
            fi
            x=$(( x + 1 ))
        done
        if [ "$new" == 'true' ]; then
            # We are adding a new vIP
            zfs set ${zfs_vip_property}:${x}="$vip_property" $zfs_folder
            zfs set ${zfs_vip_property}=$x $zfs_folder
            debug "Added vIP ${x}: ${vip[${vip},addr]} on $zfs_folder: $vip_property"
            current_vips=$(( current_vips + 1 ))
        fi

        
        vip=$(( vip + 1 ))
    done

    

}


del_vip () {

    if [ "$1" == '-h' ]; then
        vip_usage
    fi

    local zfs_folder="$1"
    shift
    local vip="$1"

    while [ "$vip" != '' ]; do

        zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
        if [ $? -ne 0 ]; then
            warning "add_mod_vip called on non-existant ZFS folder $zfs_folder"
            vip_usage
            return 1
        fi
        
        if [ "$vip" == 'all' ]; then
            vips=`zfs get -o value -H -s local,received ${zfs_vip_property} $zfs_folder`
            if [ "$vips" != '' ]; then
                zfs inherit ${zfs_vip_property} $zfs_folder
                x=1
                while [ $x -le $vips ]; do
                    vip_data=`zfs get -o value -H -s local,received ${zfs_vip_property}:${x} $zfs_folder`
                    debug "Removing VIP ${x} on ${zfs_folder}: $vip_data"
                    zfs inherit ${zfs_vip_property}:${x} $zfs_folder
                    x=$(( x + 1 ))
                done
            fi
                
        else
            vips=`zfs get -o value -H -s local,received ${zfs_vip_property} $zfs_folder`
            if is_numeric $vip; then
                numeric='true'
            else
                numeric='false'
            fi
            if [ "$vips" != '' ]; then
                x=1
                shifting='false'
                while [ $x -le $vips ]; do
                    this_vip=`zfs get -o value -H -s local,received ${zfs_vip_property}:${x} $zfs_folder | ${AWK} -F '|' '{print $1}'`
                    if [ "$numeric" == 'true' ]; then
                        if [ $vip -eq $x ]; then
                            shifting='true'
                            vip_data=`zfs get -o value -H -s local,received ${zfs_vip_property}:${x} $zfs_folder`
                            debug "Removing VIP ${x} on ${zfs_folder}: $vip_data"
                        fi
                    else
                        if [ "$vip" == "$this_vip" ]; then
                            shifting='true'
                            vip_data=`zfs get -o value -H -s local,received ${zfs_vip_property}:${x} $zfs_folder`
                            debug "Removing VIP ${x} on ${zfs_folder}: $vip_data"
                        fi
                    fi 
                    if [ "$shifting" == 'true' ]; then
                        if [ $x -eq $vips ]; then
                            # Deleting the last one
                            zfs inherit ${zfs_vip_property}:${x} $zfs_folder
                            if [ $vips -eq 1 ]; then
                                zfs inherit ${zfs_vip_property} $zfs_folder
                            else
                                zfs set ${zfs_vip_property}="$(( vips - 1 ))" $zfs_folder
                            fi
                        else
                            next_vip_data=`zfs get -o value -H -s local,received ${zfs_vip_property}:$(( x + 1 )) $zfs_folder`
                            zfs set ${zfs_vip_property}:${x}="${next_vip_data}" $zfs_folder
                        fi
                    fi

                    x=$(( x + 1 ))
                done
            fi
        fi
                
        shift
        vip="$1"            
    done        
    
}
        
