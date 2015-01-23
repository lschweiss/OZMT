#!/bin/bash

running='true'
remote_tmp="$1"
shift 1
watch="$@"

while [ "$running" == 'true' ]; do
    for process in $watch; do
        errfile="${remote_tmp}/${process}.errorlevel"
        if [ ! -f ${remote_tmp}/${process}.complete ] && [ -f $errfile ]; then
            # This process has ended
            errlvl=`cat $errfile`
            if [ $errlvl -eq 0 ]; then
                touch ${remote_tmp}/${process}.complete
                complete="$process $complete"
            else
                touch ${remote_tmp}/${process}.fail
                running='false'
            fi
        fi
    done

    # Determine if all processes are complete
    finished='true'
    for process in $watch; do
        if [[ $complete != *${process}* ]]; then
            finished='false'
        fi
    done

    if [ "$finished" == 'true' ]; then
        touch ${remote_tmp}/remote.complete
        running='false'
    fi

    sleep 1

done
