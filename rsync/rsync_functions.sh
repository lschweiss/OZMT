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

    if [ -d $path ]; then
	if [ "$#" -eq "3" ]; then
	    snap=`ls -1 $path|${GREP} $this_date|${GREP} $preferred_tag`
	fi
	if [ "$snap" == "" ]; then
            snap=`ls -1 $this_path|${GREP} $this_date`
	fi
    else
	warning "Directory $this_path not found."
	return 1
    fi

    if [ "${snap}" == "" ]; then
	warning "Snapshot for $this_date on path $path not found."
	return 1
    fi

    echo $snap
    return 0
}
