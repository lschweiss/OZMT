# Find all dataset sources

if [ "$pg_only" == '' ]; then
    if [ "$ozmt_datasets" != '' ]; then
        for ozmt_dataset in $ozmt_datasets; do
            this_source=`dataset_source $ozmt_dataset`
            debug "Found dataset $ozmt_dataset at: $this_source"
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

if [ "$dataset_reparse" != '-' ]; then
    dataset_data_dataset=`echo $dataset_reparse | ${CUT} -d ':' -f 1`
    dataset_dev_folder=`echo $dataset_reparse | ${CUT} -d ':' -f 2`
    dataset_app_folder=`echo $dataset_reparse | ${CUT} -d ':' -f 3`
    dataset_data_source=`dataset_source $dataset_data_dataset`
    dataset_data_pool=`echo $dataset_data_source | $CUT -d ':' -f 1`
    dataset_data_folder=`echo $dataset_data_source | $CUT -d ':' -f 2`
    dataset_data_mountpoint=`$SSH $dataset_data_pool zfs get -H -o value mountpoint ${dataset_data_pool}/${dataset_data_dataset}`
    debug "Found Postgres dev path at ${dataset_data_source}:/${dataset_data_folder}/${dataset_dev_folder}"


fi

# Pause all related datasets replication
if [ "$ozmt_datasets" != '' ]; then
    for ozmt_dataset in $ozmt_datasets; do
        this_source="${o_source[$ozmt_dataset]}"
        o_pool=`echo $this_source | $CUT -d ':' -f 1`
        o_folder=`echo $this_source | $CUT -d ':' -f 2`
        # Pause it
        notice "Pausing $ozmt_dataset replication"
        $SSH $o_pool /opt/ozmt/replication/replication-state.sh -d $ozmt_dataset -s pause -i $pause
        o_paused["$ozmt_dataset"]='true'
        paused='true'
    done
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

