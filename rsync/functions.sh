#! /bin/bash

locate_snap () {
    EXPECTED_ARGS=2
    if [ "$#" -lt "$EXPECTED_ARGS" ]; then
  	echo "Usage: `basename $0` {snapshot_dir} {date} [preferred_tag]"
	echo "	{date} must be of the same format as in snapshot folder name"
	echo "  [preferred_tag] will be a text match"
        return 1
    fi

    snap=""
    path=$1
    date=$2
    preferred_tag=$3

    if [ -d $path ]; then
	if [ "$#" -eq "3" ]; then
	    snap=`ls -1 $path|grep $date|grep $preferred_tag`
	fi
	if [ "$snap" == "" ]; then
            snap=`ls -1 $path|grep $date`
	fi
    else
	echo "Directory $path not found."
	return 1
    fi

    if [ "${snap}" == "" ]; then
	echo "Snapshot for $date on path $path not found."
	return 1
    fi

    echo $snap
    return 0
}
