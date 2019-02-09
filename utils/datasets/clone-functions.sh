if [ "$pg_only" == '' ]; then
    # Locate dataset info
    clone_pool=
    debug "Finding dataset source for $clone_dataset"
    dataset_source=`dataset_source $clone_dataset`
    o_source["${clone_dataset}"]="$dataset_source"
    if [ "$dataset_source" == '' ]; then
        error "Cannot locate source for $clone_dataset"
        die "Cannot locate source for $clone_dataset" 1
    fi
    debug "Found source at $dataset_source"
    clone_pool=`echo $dataset_source | $CUT -d ':' -f 1`

    if [ "$mode" == 'create' ]; then
        # Check if clone already exists
        $SSH ${clone_pool} zfs list ${clone_pool}/${clone_dataset}/dev/${dev_name}  1>/dev/null 2>/dev/null
        if [ $? -eq 0 ]; then
            error "Clone already exists for $dev_name"
            die "Cannot locate source for $clone_dataset" 1
        else
            debug "Safe to create ${clone_pool}/dev/${dev_name}"
        fi
    
        # TODO: Check if clones exist in all additional folders and datasets
    fi


    # Collect folders
    rm -f ${myTMP}/dataset_folders_$$
    x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:folders ${clone_pool}/${clone_dataset}`
    folders="$(echo -e "$x" | $TR -d '[:space:]')"
    if [ "$folders" != '-' ]; then
        NUM=1
        while [ $NUM -le $folders ]; do
            folder_prop=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:folder:${NUM} ${clone_pool}/${clone_dataset} 2>/dev/null`
            folder="$(echo -e "$folder_prop" | $TR -d '[:space:]')"
            if [ "$folder" == '-' ]; then
                die "Folder #${NUM} not defined at ${clone_pool}/${clone_dataset}"
            else
                echo "$folder_prop" >>${myTMP}/dataset_folders_$$
            fi
            NUM=$(( NUM + 1 ))
        done
    fi

    rm -f ${myTMP}/dataset_datasets_$$
    x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:datasets ${clone_pool}/${clone_dataset}`
    datasets="$(echo -e "$x" | $TR -d '[:space:]')"
    if [ "$datasets" != '-' ]; then
        NUM=1
        while [ $NUM -le $datasets ]; do
            $SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:dataset:${NUM} ${clone_pool}/${clone_dataset} 2>/dev/null >>${myTMP}/dataset_datasets_$$
            NUM=$(( NUM + 1 ))
        done
    fi


    # Collect additional cloning information
    dataset_mountpoint=`$SSH $clone_pool zfs get -H -o value mountpoint ${clone_pool}/${clone_dataset}`

    x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:postgres ${clone_pool}/${clone_dataset}`
    postgres="$(echo -e "$x" | $TR -d '[:space:]')"
    x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:postgresdev ${clone_pool}/${clone_dataset}`
    postgres_dev="$(echo -e "$x" | $TR -d '[:space:]')"
    x=`$SSH $clone_pool zfs get -H -o value ${zfs_property_tag}:postgres:reparse ${clone_pool}/${clone_dataset}`
    postgres_reparse="$(echo -e "$x" | $TR -d '[:space:]')"
    if [ "$postgres_reparse" == '-' ]; then
        postgres_reparse="$postgres_reparse_default"
    fi
    postgres_reparse_dataset=`echo $postgres_reparse | ${CUT} -d ':' -f 1`
    postgres_reparse_source=`dataset_source $postgres_reparse_dataset`
    postgres_reparse_pool=`echo $postgres_reparse_source | ${CUT} -d ':' -f 1`
    postgres_reparse_path=`echo $postgres_reparse | ${CUT} -d ':' -f 2`
    postgres_reparse_mountpoint=`$SSH $postgres_reparse_pool zfs get -H -o value mountpoint ${postgres_reparse_pool}/${postgres_reparse_dataset}`

    if [ "$mode" == 'create' ]; then
        debug "Cloning the following folders: $(cat ${myTMP}/dataset_folders_$$)"

        snap=`find_snap "${clone_pool}/${clone_dataset}" "$snap_name"`
        if [ "$snap" == '' ]; then
            error "Could not find snapshot: $snap_name"
            die "Cannot locate source for $clone_dataset" 1
        else
            debug "Found snapshot $snap"
        fi
    fi

    ozmt_datasets=`cat ${myTMP}/dataset_datasets_$$ 2>/dev/null`

fi



# Find all dataset sources

if [ "$pg_only" == '' ]; then
    if [ "$ozmt_datasets" != '' ]; then
        for ozmt_dataset in $ozmt_datasets; do
            this_source=`dataset_source $ozmt_dataset`
            notice "Found dataset $ozmt_dataset at: $this_source"
            o_source["$ozmt_dataset"]="$this_source"
        done
    fi
else
    postgres="$(echo "$pg_only" | ${CUT} -d ':' -f 1):$(echo "$pg_only" | ${CUT} -d ':' -f 2)"
    postgres_data_pool="$(echo "$pg_only" | ${CUT} -d ':' -f 1)"
    # Check for optional root reparse location
    postgres_reparse="$(echo "$pg_only" | ${CUT} -d ':' -f 3):$(echo "$pg_only" | ${CUT} -d ':' -f 4)"
    postgres_data_dataset="$(echo "$pg_only" | ${CUT} -d ':' -f 3)"
    postgres_data_source=`dataset_source $postgres_data_dataset`
    postgres_data_folder=`echo $postgres_data_source | $CUT -d ':' -f 2`
    postgres_dev_folder="$(echo "$pg_only" | ${CUT} -d ':' -f 4)"
    if [ "$postgres_reparse" == ':' ]; then
        postgres_reparse='-'
    fi
    postgres_dev='-'
fi
    
x="$(echo -e "$postgres" | $TR -d '[:space:]')"
postgres="$x"
if [ "$postgres" != '-' ]; then
    p_dataset=`echo $postgres | ${CUT} -d ':' -f 1`
    p_name=`echo $postgres | ${CUT} -d ':' -f 2`
    p_source=`dataset_source $p_dataset`
    debug "Found postgres source at: $p_source"
    p_pool=`echo $p_source | $CUT -d ':' -f 1`
    p_folder=`echo $p_source | $CUT -d ':' -f 2`
fi

if [ "$postgres_dev" != '-' ]; then
    pdev_folder="$postgres_dev"
else
    pdev_folder="dev"
fi

# Pause all related datasets replication
if [ "$ozmt_datasets" != '' ]; then
    for ozmt_dataset in $ozmt_datasets; do
        this_source="${o_source[$ozmt_dataset]}"
        o_pool=`echo $this_source | $CUT -d ':' -f 1`
        o_folder=`echo $this_source | $CUT -d ':' -f 2`
        # Pause it
        notice "Pausing $ozmt_dataset replication"
        $SSH $o_pool /opt/ozmt/replication/replication-state.sh -d $ozmt_dataset -s pause -i $pause &
        o_paused["$ozmt_dataset"]='true'
        paused='true'
    done
    wait
fi

if [ "$postgres" != '-' ]; then
    notice "Pausing $p_dataset replication"
    $SSH $p_pool /opt/ozmt/replication/replication-state.sh -d $p_dataset -s pause -i $pause
    p_paused='true'
fi


# Wait for all datasets to finish any running jobs
flushed='false'
debug "Waiting for any running jobs to complete"

while [ "$flushed" == 'false' ]; do
    flushed='true'

    if [ "$pg_only" == '' ]; then
        for ozmt_dataset in $ozmt_datasets; do
            this_source="${o_source[$ozmt_dataset]}"
            o_pool=`echo $this_source | $CUT -d ':' -f 1`
            o_folder=`echo $this_source | $CUT -d ':' -f 2`
            state=`$SSH $o_pool /opt/ozmt/replication/replication-state.sh -d $ozmt_dataset -r 2> /dev/null`

            echo $state | ${GREP} -q 'FAIL'
            if [ $? -eq 0 ]; then
                error "Dataset $ozmt_dataset replication in failed state.  Must fix before cloning."
                die "Dataset $ozmt_dataset replication in failed state.  Must fix before cloning." 1
            fi

            echo $state | ${GREP} -q 'RUNNING\|SYNC\|CLEAN'
            if [ $? -eq 0 ]; then
                debug "Dataset $ozmt_dataset not flushed.  Pausing 30 seconds."
                flushed='false'
                sleep 30
            fi
        done
    fi

    if [ "$postgres" != '-' ]; then
        state=`$SSH $p_pool /opt/ozmt/replication/replication-state.sh -d $p_dataset -r 2> /dev/null`
        echo $state | ${GREP} -q 'FAIL'
        if [ $? -eq 0 ]; then
            error "Dataset $p_dataset replication in failed state.  Must fix before cloning."
            die "Dataset $p_dataset replication in failed state.  Must fix before cloning." 1
        fi

        echo $state | ${GREP} -q 'RUNNING\|SYNC\|CLEAN'
        if [ $? -eq 0 ]; then
            debug "Dataset $p_dataset not flushed.  Pausing 30 seconds."
            flushed='false'
            sleep 30
        fi
    fi

done


debug "All jobs fully paused"

