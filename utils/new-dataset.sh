#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2017  Chip Schweiss

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

. /opt/ozmt/zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

now=`${DATE} +"%F %H:%M:%S%z"`

local_pools="zpool list -H -o name"

# show function usage
show_usage() {
    echo
    echo "Usage: $0 -p {pool} -d {dataset_name}"
    echo "  These options can be repeated, but must be in order:"
    echo "    [-v {vip}]                   vIP in x.x.x.x/x format"
    echo
    echo "    [-r {network/mask}]          Route for vIP"
    echo "                                 x.x.x.x/x format"
    echo "                                 optional: list a named route group defined in"
    echo "                                           /etc/ozmt/network/{template}.routes"
    echo "                                 (repeatable for each vIP)"
    echo "        -g {gateway}             Gateway for specified route"
    echo "                                 (Manditory for each route, unless a template is used)"
    echo
    echo "    [-i {hostname}/{interface}]  {interface} to attach vIP while on {hostname}"
    echo "                                   {hostname} can be '*' for any host"
    echo "                                   (repeatable for each vIP)"
}

vips=0
routes=0
interfaces=0

declare -A vip

while getopts p:f:d:v:r:g:i:R:T: opt; do
    case $opt in
        p)  # Pool
            pool="$OPTARG"
            debug "pool: $pool"
            ;;
        d)  # Dataset name
            dataset="$OPTARG"
            debug "dataset name: $dataset"
            ;;
        v)  # vIP
            vips=$(( vips + 1 ))
            routes=0
            interfaces=0
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
        i)  # interface
            if [ $interfaces -eq 0 ]; then
                vip[${vips},interfaces]="$OPTARG"
            else
                vip[${vips},interfaces]="${vip[${vips},interfaces]}|${OPTARG}"
            fi
            interfaces=$(( interfaces + 1 ))
            debug "vIP #${vips} interface: ${OPTARG}"
            ;;

        R)  # Replication template
            replication="$OPTARG"
            debug "Replication enabled with ${replication}.template"
            ;;
        T)  # Replication target
            target_pool="$OPTARG"
            debug "Replication target set to: $target_pool"
            ;;
        S)  # Don't leave replication suspended
            suspend='false'
            debug "Replication will be resumed after setup."
            ;;

        ?)  # Show program usage and exit
            show_usage
            exit 0
            ;;
        :)  # Mandatory arguments not specified
            die "${job_name}: Option -$OPTARG requires an argument."
            ;;
    esac
done

# TODO: Validate all input

folder="$dataset"

zfs list $pool/$folder 2>/dev/null 1>/dev/null
if [ $? -ne 0 ]; then
    zfs create -o mountpoint=/${dataset} $pool/$folder
else
    echo
    echo "ZFS folder $pool/$folder already exists."
    echo -n "Press enter to continue with reconfigure...."
    read nothing
fi

zfs set ${zfs_dataset_property}=${dataset} $pool/$folder

vip=1
while [ $vip -le $vips ]; do
    zfs set ${zfs_vip_property}=$vips $pool/$folder
    routes=${vip[${vip},routes]}
    if [ "$routes" != '' ]; then
        route=1
        while [ $route -le $routes ]; do
            route_prop="${vip[${vip},route,${route}]}/${vip[${vip},gw,${route}]}"
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
    vip_property="${vip_property}|${vip[${vip},interfaces]}"
    zfs set ${zfs_vip_property}:${vip}="$vip_property" $pool/$folder
    vip=$(( vip + 1 ))
done

template="/etc/ozmt/replication/${replication}.template"

if [ -f "$template" ]; then
    ssh $target_pool "echo Verified pool $target_pool" 
    if [ $? -ne 0 ]; then
        echo
        echo "Could not connect to $target_pool"
        echo "Aborting replication configuration"
        exit 1
    fi
    touch /$pool/zfs_tools/var/replication/jobs/suspend_all_jobs
    mkdir -p "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset"
    cp "$template" "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset/targetpool"
        ${SED} "s,#SOURCEPOOL#,${pool},g" --in-place "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset/targetpool"
        ${SED} "s,#TARGETPOOL#,${target_pool},g" --in-place "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset/targetpool"
        ${SED} "s,#DATASET#,${dataset},g" --in-place "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset/targetpool"

    cat "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset/targetpool"
    source "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset/targetpool"
    touch $job_status
    mv "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset/targetpool" \
        "/$pool/zfs_tools/var/replication/jobs/definitions/$dataset/$target_pool"
    zfs set ${zfs_replication_property}="on" $pool/$folder
    echo "${pool}:${folder}" > $source_tracker
    echo "${pool}:${folder}" > $dataset_targets
    echo "${target_pool}:${folder}" >> $dataset_targets 
    zfs set ${zfs_replication_property}:endpoints="2" $pool/$folder
    zfs set ${zfs_replication_property}:endpoint:1="${pool}:${folder}" $pool/$folder
    zfs set ${zfs_replication_property}:endpoint:2="${target_pool}:${folder}" $pool/$folder
    ssh $target_pool "echo ${pool}:${folder} > /${target_pool}/zfs_tools/var/replication/source/${dataset}"
    ssh $target_pool "echo ${pool}:${folder} > /${target_pool}/zfs_tools/var/replication/targets/${dataset}"
    ssh $target_pool "echo ${target_pool}:${folder} >> /${target_pool}/zfs_tools/var/replication/targets/${dataset}"
    ssh $target_pool "touch /${target_pool}/zfs_tools/var/replication/jobs/status/${dataset}#${pool}:${dataset}"
    ssh $target_pool "touch /${target_pool}/zfs_tools/var/replication/jobs/status/${dataset}#${pool}:${dataset}.unlock"
    ssh $target_pool "mkdir -p /${target_pool}/zfs_tools/var/replication/jobs/definitions/$dataset"
    #ssh $target_pool "zfs create ${target_pool}/${folder}"

    cp "$template" ${TMP}/${dataset}_target_definition
        ${SED} "s,#TARGETPOOL#,${pool},g" --in-place ${TMP}/${dataset}_target_definition
        ${SED} "s,#SOURCEPOOL#,${target_pool},g" --in-place ${TMP}/${dataset}_target_definition
        ${SED} "s,#DATASET#,${dataset},g" --in-place ${TMP}/${dataset}_target_definition

    scp ${TMP}/${dataset}_target_definition ${target_pool}:/${target_pool}/zfs_tools/var/replication/jobs/definitions/${dataset}/${pool}

    rm ${TMP}/${dataset}_target_definition
    
    # Start replication
    if [ "$suspend" == 'false' ]; then
        rm "/$pool/zfs_tools/var/replication/jobs/suspend_all_jobs"
    fi

fi

zfs get all $pool/$folder | sort
