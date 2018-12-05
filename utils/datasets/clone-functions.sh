# Find all dataset sources

if [ "$ozmt_datasets" != '' ]; then
    for ozmt_dataset in $ozmt_datasets; do
        debug "Finding dataset source for $ozmt_dataset"
        this_source=`dataset_source $ozmt_dataset`
        debug "Found source as: $this_source"
        o_source["$ozmt_dataset"]="$this_source"
    done
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


# Wait for all datasets to finish any running jobs
flushed='false'
debug "Waiting for any running jobs to complete"

while [ "$flushed" == 'false' ]; do

    for ozmt_dataset in $ozmt_datasets; do
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

        echo $state | ${GREP} -q 'RUNNING\|SYNC\|CLEAN'
        if [ $? -eq 0 ]; then
            flushed='false'
            sleep 30
        fi

    done

done

debug "All jobs fully paused"

