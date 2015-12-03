#! /bin/bash

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. /opt/ozmt/zfs-tools-init.sh


pools="$(pools)"

report () {

    local job="$1"
    source $job
    echo "zfs set ${zfs_quota_reports_property}=${quota_reports} $quota_path"
    zfs set ${zfs_quota_reports_property}=${quota_reports} $quota_path
    x=1
    while [ $x -le ${quota_reports} ]; do
        echo "zfs set ${zfs_quota_report_property}:${x}=\"${quota_report[$x]}\" $quota_path"
        zfs set ${zfs_quota_report_property}:${x}="${quota_report[$x]}" $quota_path
        x=$(( x + 1 ))
    done

}


for pool in $pools; do

    jobfolder="/${pool}/zfs_tools/etc/reports/jobs/quota"
    if [ -d "$jobfolder" ]; then

        jobs=`ls -1 $jobfolder`

        for job in $jobs; do
            quota_reports=0
            echo "Set reports for: ${jobfolder}/${job}"
            report "${jobfolder}/${job}"
        done

    fi
done


