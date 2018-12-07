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
    postgres="$pg_only"
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

if [ "$reparse" != '' ]; then
    data_dataset=`echo $reparse | ${CUT} -d ':' -f 1`
    pg_dev_folder=`echo $reparse | ${CUT} -d ':' -f 2`
    data_source=`dataset_source $data_dataset`
    data_pool=`echo $data_source | $CUT -d ':' -f 1`
    data_folder=`echo $data_source | $CUT -d ':' -f 2`
    debug "Found Postgres dev path at ${data_source}:/${data_folder}/${pg_dev_folder}"
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
            set -x
            flushed='true'
            this_source="${o_source[$ozmt_dataset]}"
            o_pool=`echo $this_source | $CUT -d ':' -f 1`
            o_folder=`echo $this_source | $CUT -d ':' -f 2`
            state=`$SSH $o_pool /opt/ozmt/replication/replication-state.sh -d $ozmt_dataset -r 2> /dev/null`

            echo $state | ${GREP} -q 'FAIL'
            if [ $? -eq 0 ]; then
                error "Dataset $ozmt_dataset replication in failed state.  Must fix before cloning."
                die "Dataset $ozmt_dataset replication in failed state.  Must fix before cloning." 1
            fi
            set +x

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

