#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2016  Chip Schweiss

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

locate_snap () {
    EXPECTED_ARGS=2
    if [ "$#" -lt "$EXPECTED_ARGS" ]; then
        echo "Usage: `basename $0` {snapshot_dir} {date} [preferred_tag]"
        echo "  {date} must be of the same format as in snapshot folder name"
        echo "  [preferred_tag] will be a text match"
        return 1
    fi

    snap=""
    path=$1
    date=$2
    preferred_tag=$3

    if [ -d $path ]; then
        if [ "$#" -eq "3" ]; then
            snap=`ls -1 $path|${GREP} $date|${GREP} $preferred_tag`
        fi
        if [ "$snap" == "" ]; then
            snap=`ls -1 $path|${GREP} $date`
        fi
    else
        warning "locate_snap: Directory $path not found."
        return 1
    fi

    if [ "${snap}" == "" ]; then
        warning "locate_snap: Snapshot for $date on path $path not found."
        return 1
    fi

    echo $snap
    return 0
}

snap_job_usage () {
    local snap=
    if [ -t 1 ]; then
        cat ${TOOLS_ROOT}/snapshots/USAGE
        for snap in $snaptypes; do
            echo "      $snap"
        done
    fi
}
    
show_snap_job () {

    local zfs_folder="$1"
    local folder=
    local folders=
    local recursive="$2"
    local result=
    local snaptype=
    local has_snaps=

    # Test folder exists
    zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        warning "show_snap_job called on non-existant zfs folder $zfs_folder"
        snap_job_usage
        return 1
    fi

    if [[ "$recursive" != "" && "$recursive" != "-r" ]]; then
        warning "show_snap_job called with invalid parameter $recursive"
        snap_job_usage
        return 1
    fi
    
    folders=`zfs list -o name -H ${recursive} ${zfs_folder}`

    for folder in $folders; do
        has_snaps='false'
        for snaptype in $snaptypes; do
            existing=`zfs get -o value -H -s local,received ${zfs_snapshot_property}:${snaptype} $folder`
            if [ "$existing" != '' ]; then
                has_snaps='true'
                echo -E "${folder} ${snaptype} ${existing}" >> ${TMP}/snapjobs_$$
            fi
        done
        if [ "$has_snaps" == 'false' ]; then
            echo -E "${folder} no snapshots" >> ${TMP}/snapjobs_$$
        fi
    done 

    column -t ${TMP}/snapjobs_$$
    rm ${TMP}/snapjobs_$$    

}

add_mod_snap_job () {

    local zfs_folder="$1"
    local snap_job="$2"
    local snap_job_type=
    local snap_job_keep=
    local result=
    local fixed_folder=`foldertojob $zfs_folder`
    local pool=`echo $zfs_folder | ${CUT} -f 1 -d '/'`
    local existing=

    if [ $# -lt 2 ]; then
        warning "add_mod_snap_job called with too few arguements"
        snap_job_usage
        return 1
    fi


    # Test folder exists
    zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        warning "add_mod_snap_job called on non-existant zfs folder $zfs_folder"
        snap_job_usage
        return 1
    fi

    while [ "$snap_job" != "" ]; do

        snap_job_type=`echo $snap_job | ${CUT} -f 1 -d '/'`
        snap_job_keep=`echo $snap_job | ${CUT} -f 2 -d '/'`

        # Test valid snap_job
        echo $snaptypes | ${GREP} -q "\b${snap_job_type}\b"
        result=$?
        if [ $result -ne 0 ]; then
            warning "add_mod_snap_job: invalid snap type specified: $snap_job_type"
            snap_job_usage
        fi
    
        notice "add_mod_snap_job: updating $zfs_folder job $snap_job"
        # Update the job
        zfs set ${zfs_snapshot_property}:${snap_job_type}="$snap_job_keep" $zfs_folder
        
        # Flush appropriate caches
        # TODO: Don't just flush but reload the cache, so next job executes quickly

        # Flush cache for the job type
        rm -fv /${pool}/zfs_tools/var/cache/zfs_cache/*${zfs_snapshot_property}:${snap_job_type}_${pool} \
            2>&1 1>${TMP}/clean_snap_cache_$$.txt 
        #debug "Cleaned cache for ${snap_job_type} on ${pool}" ${TMP}/clean_snap_cache_$$.txt
        rm ${TMP}/clean_snap_cache_$$.txt 2>/dev/null

        # Flush the cache for the folder
        rm -fv /${pool}/zfs_tools/var/cache/zfs_cache/*${zfs_snapshot_property}:${snap_job_type}_${fixed_folder} \
            2>&1 1>${TMP}/clean_snap_cache_$$.txt
        #debug "Cleaned cache for ${snap_job_type} on ${fixed_folder}" ${TMP}/clean_snap_cache_$$.txt
        rm ${TMP}/clean_snap_cache_$$.txt 2>/dev/null
    
        shift
        snap_job="$2"

    done
            
}
        
del_snap_job () {

    local zfs_folder="$1"
    local snap_job="$2"
    local result=
    local fixed_folder=`foldertojob $zfs_folder`
    local pool=`echo $zfs_folder | ${CUT} -f 1 -d '/'`
    
    if [ $# -lt 2 ]; then
        warning "del_snap_job called with too few arguements"
        snap_job_usage
        return 1
    fi

    # Test folder exists
    zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        warning "del_snap_job called on non-existant zfs folder $zfs_folder"
        snap_job_usage
        return 1
    fi

    while [ "$snap_job" != "" ]; do
        # Test valid snap_job
        echo $snaptypes | ${GREP} -q "\b${snap_job}\b"
        result=$?
        if [ $result -ne 0 ]; then
            warning "del_snap_job: invalid snap type specified: $snap_job"
            snap_job_usage
            return 1
        fi

        zfs inherit ${zfs_snapshot_property}:${snap_job} $zfs_folder
        # flush cache for the job type and folder
        rm -f /${pool}/zfs_tools/var/cache/zfs_cache/*${zfs_snapshot_property}:${snap_job}_${pool} 2>/dev/null
        rm -f /${pool}/zfs_tools/var/cache/zfs_cache/*${zfs_snapshot_property}:${snap_job}_${fixed_folder} 2>/dev/null

        shift
        snap_job="$2"
    done


}    
