#! /bin/bash

locate_snap () {
    EXPECTED_ARGS=2
    if [ "$#" -lt "$EXPECTED_ARGS" ]; then
      	echo "Usage: `basename $0` {snapshot_dir} {date} [preferred_tag]"
    	echo "	{date} must be of the same format as in snapshot folder name"
    	echo "  [preferred_tag] will be a text match"
        return 1
    fi

    local snap=""
    local this_path=$1
    local this_date=$2
    local preferred_tag=$3


    if [ -d $this_path ]; then
    	if [ "$#" -eq "3" ]; then
    	    snap=`ls -1 $this_path|${GREP} $this_date|${GREP} $preferred_tag|tail -n 1`
    	fi
    	if [ "$snap" == "" ]; then
            snap=`ls -1 $this_path|${GREP} $this_date|tail -n 1`
    	fi
    else
    	echo "Directory $this_path not found."
    	return 1
    fi

    if [ "${snap}" == "" ]; then
    	echo "Snapshot for $this_date on path $this_path not found."
    	return 1
    fi

    echo $snap
    return 0
}
