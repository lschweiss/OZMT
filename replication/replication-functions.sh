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


# Assumes zfs_init has already been sourced

RCACHE=/var/zfs_tools/replication/cache

MKDIR ${RCACHE}

load_replication_data () {

    # Takes one input {zfs_folder}

    local zfs_folder="$1"
    local z_folder=`echo $zfs_folder | ${SED} 's,/,%,g'`
    local z_cache=
    local count=
    local pool=`echo $zfs_folder | ${CUT} -d '/' -f 1`

    # Reset global variables that will receive data
    replication=
    replication_source=
    replication_source_local=
    replication_endpoints=
    replication_jobs=
    replication_suspended=
    unset replication_endpoint
    unset replication_job_endpointA
    unset replication_job_endpointB
    unset replication_job_frequency
    unset replication_job_mode
    unset replication_job_options
    unset replication_job_queued_jobs
    unset replication_job_last_run
    unset replication_job_last_complete
    unset replication_job_failures
    unset replication_job_suspended

    # Test if zfs_folder exists
    ssh $pool zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        debug "get_replication_data called for unknown zfs_folder $zfs_folder"
        return 1
    fi

    z_cache="${RCACHE}/${z_folder}"
    MKDIR ${z_cache}

    replication=`ssh $pool zfs get -s local,received -o value -H ${zfs_replication_property} ${zfs_folder}`
    if [ "$replication" == 'on' ]; then
        # Get the source, strip the timestamp
        replication_source=`ssh $pool zfs get -s local,received -o value -H ${zfs_replication_property}:source ${zfs_folder} | \
            ${CUT} -d '|' -f 1`
        if [ "$replication_source" == "$zfs_folder" ]; then
            replication_source_local='true'
        else
            replication_source_local='false'
        fi

        if [ "$replication_source_local" == 'true' ]; then

            # It is up to consumer processes of this data to determine if this is truely the source
            # or if there is a conflict, or simply out of date.

            # Replication suspended
            replication_suspended=`ssh $pool zfs get -s local,inherited -o value \
                -H ${zfs_replication_property}:suspended ${zfs_folder}`


            # Find replication endpoints for this dataset
            replication_endpoints=`remote_zfs_cache get -s local,received -o value -H ${zfs_replication_property}:endpoints ${zfs_folder} \
                3> ${z_cache}/replication_endpoints`

            if [[ $replication_endpoints =~ ^-?[0-9]+$ ]]; then
                count=1
                while [ $count -le $replication_endpoints ]; do
                    replication_endpoint[$count]=`remote_zfs_cache get -s local,received -o value \
                        -H ${zfs_replication_property}:endpoint:${count} ${zfs_folder} \
                        3> ${z_cache}/replication_endpoint_${count}`
                    count=$(( count + 1 ))
                done
            fi


            # Find replication jobs for this dataset
            
            replication_jobs=`remote_zfs_cache get -s local,received -o value -H ${zfs_replication_property}:jobs ${zfs_folder} \
                3> ${z_cache}/replication_jobs`

            if [[ $replication_jobs =~ ^-?[0-9]+$ ]]; then
                count=1
                while [ $count -le $replication_jobs ]; do
                    # Endpoint A
                    replication_job_endpointA[$count]=`remote_zfs_cache get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:end:a ${zfs_folder} \
                        3> ${z_cache}/replication_job_${count}_endA`
                    # Endpoint B
                    replication_job_endpointB[$count]=`remote_zfs_cache get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:end:b ${zfs_folder} \
                        3> ${z_cache}/replication_job_${count}_endB`
                    # Frequency
                    replication_job_frequency[$count]=`remote_zfs_cache get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:frequency ${zfs_folder} \
                        3> ${z_cache}/replication_job_${count}_frequency`
                    # Mode
                    replication_job_mode[$count]=`remote_zfs_cache get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:mode ${zfs_folder} \
                        3> ${z_cache}/replication_job_${count}_mode`
                    # Options
                    replication_job_options[$count]=`remote_zfs_cache get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:options ${zfs_folder} \
                        3> ${z_cache}/replication_job_${count}_options`
                    # Failure limit
                    replication_job_fail_limit[$count]=`remote_zfs_cache get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:fail_limit ${zfs_folder} \
                        3> ${z_cache}/replication_job_${count}_fail_limit`
                            
                    # Realtime status, no caching
                    # Queued jobs
                    replication_job_queued_jobs[$count]=`ssh $pool zfs get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:queued_jobs ${zfs_folder}`
                    # Last run time
                    replication_job_last_run[$count]=`ssh $pool zfs get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:last_run ${zfs_folder}`
                    # Last completion time
                    replication_job_last_complete[$count]=`ssh $pool zfs get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:last_complete ${zfs_folder}`
                    # Job failures
                    replication_job_failures[$count]=`ssh $pool zfs get -s local,received -o value \
                        -H ${zfs_replication_property}:job:${count}:failures ${zfs_folder}`
                    # Job suspended
                    replication_job_suspended[$count]=`ssh $pool zfs get -s local,inherited -o value \
                        -H ${zfs_replication_property}:job:${count}:suspended ${zfs_folder}`

                    count=$(( count + 1 ))
                done
            fi # $replication_jobs

        fi # $replication_source_local

    fi # $replicaiton == on

}

reload_replication_data () {

    # Clears cached replication data for a zfs_folder and loads data fresh

    # Takes one input {zfs_folder}

    local zfs_folder="$1"
    local z_folder=`echo $zfs_folder | ${SED} 's,/,%,g'`
    local z_cache=
    local caches=
    local cache=

    z_cache="${RCACHE}/${z_folder}"

    if [ -d $z_cache ]; then
        caches=`ls -1 $z_cache`
        for cache in $caches; do
            rm -f "$( cat ${z_cache}/${cache} )"
            rm -f ${z_cache}/${cache}
        done
    fi

    load_replication_data $zfs_folder

}
   

select_zfs_folder () {

    if [ "$dialog_out" == '' ]; then
        local tempfile=${TMP}/dialog.out
    else
        local tempfile="$dialog_out"
    fi
    rm -f $tempfile
    local ar=()
    local pool=
    local back_title=
    local retval=
    local folder=
    local count=0
    local scratch="${TMP}/dialog_scratch"

    if [ "$1" != '' ]; then
        back_title="$1"
    else 
        back_title="OZMT - Select ZFS folder"
    fi

    rm -f $tempfile

    for pool in $(cluster_pools) ; do
        count=$(( count + 1 ))
        ar+=( "$count" "$pool" )
        echo "$pool" >> $scratch
        #ar+=( "$pool" "." )
    done 

    $DIALOG --colors --backtitle "$back_title" \
        --title "Select Pool" --clear \
        --menu "You can use the UP/DOWN arrow keys, the first letter of the choice as a hot key.
Press SPACE to toggle an option on/off. \n\n\
  Please select the ZFS pool:" $height $width $select_lines \
        "${ar[@]}" 2> $tempfile

    retval=$?

    count=`cat $tempfile`
    pool=`cat $scratch | ${HEAD} -n ${count} | ${TAIL} -n 1`
    rm -f $scratch

    echo "pool: $pool"

    if [ $retval -ne 0 ]; then
        return $retval
    fi

    ar=()
    count=0
    
    while read folder; do
        count=$(( count + 1 ))
        ar+=( "$count" "$folder" )
        echo "$folder" >> $scratch
    done < <(ssh $pool zfs list -t filesystem -o name -H -r $pool |tail -n+2 | sed 's,^\w*/,,g')

    $DIALOG --colors --backtitle "$back_title" \
        --title "Select folder on pool $pool" --clear \
        --menu "You can use the UP/DOWN arrow keys, the first letter of the choice as a hot key.
Press SPACE to toggle an option on/off. \n\n\
  Please select the ZFS folder:" $height $width $select_lines \
        "${ar[@]}" 2> $tempfile
    retval=$?

    count=`cat $tempfile`
    folder=`cat $scratch | ${HEAD} -n ${count} | ${TAIL} -n 1`
    rm -f $scratch

    echo "$pool/$folder" > $tempfile

    if [ $retval -ne 0 ]; then
        return $retval
    fi


    
}

select_dataset () {

    # Output is the name of a dataset or '{new}' and will be placed
    # in file specified by the global variable $dialog_out

    if [ "$dialog_out" == '' ]; then
        local tempfile=${TMP}/dialog.out
    else
        local tempfile="$dialog_out"
    fi
    rm -f $tempfile
    local ar=()
    local pool=
    local back_title=
    local retval=
    local folder=
    local dataset=
    local datasets=
    local dataset_list="$1"
    local new_dataset_option="$2"
    local count=0
    local selection=0
    

    if [ ! -f $dataset_list ]; then
        echo "select_dataset: Invalid dataset list file given: $dataset_list"
        return 1
    fi

    datasets=`cat ${dataset_list} | ${CUT} -f 1 | ${SORT} -u`

    for dataset in $datasets; do
        count=$(( count + 1 ))
        ar+=( $count $dataset )
    done

    if [ "$new_dataset_option" == 'true' ]; then
        ar+=( "new" "New dataset" )
    fi

    $DIALOG --colors --backtitle "OZMT - Select Dataset" \
        --title "Select dataset" --clear \
        --menu "You can use the UP/DOWN arrow keys, the first letter of the choice as a hot key.
Press SPACE to toggle an option on/off. \n\n\
  Please select the dataset:" $height $width $select_lines \
        "${ar[@]}" 2> $tempfile
    retval=$?

    selection=`cat $tempfile`

    if [ "$selection" == 'new' ]; then
        echo '{new}' > $tempfile
    else    
        dataset=`echo $datasets | ${CUT} -d ' ' -f ${selection} `
        echo $dataset > $tempfile
    fi

    return $retval


} 

dataset_source_folder () {

    # Given the input of a dataset name output the zfs folder that is considered the source folder

    local folder=
    local folders=
    local pool=
    local dataset="$1"

    folders=`cat $dataset_list | ${GREP} -P "^${dataset}\t" | ${CUT} -f 2`

    for folder in $folders; do
        pool=`echo $folder | ${CUT} -d '/' -f 1`
        replication=`ssh $pool zfs get -s local,received -o value -H ${zfs_replication_property} ${folder}`
        if [ "$replication" == 'on' ]; then
            # Find all endpoints and determine the source
            

        fi
    done
















}
