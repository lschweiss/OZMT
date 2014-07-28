#! /bin/bash 

# blind-increment-job.sh

# Copy updates to a target file system using copy-snapshots.sh in blind mode

#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012, 2013  Chip Schweiss

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


cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

# show program usage
show_usage() {
    echo
    echo "Usage: $0 "
    echo "  [-d] Dry run.  Show what would happen."
    echo "  [-r {report_name} Overide default report name."
    echo "  [-g {logfile) Overide default log file."
    echo 
    exit 1
}

if [ "x$blind_logfile" != "x" ]; then
    logfile="$blind_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$blind_report" != "x" ]; then
    report_name="$blind_report"
else
    report_name="$default_report_name"
fi

jobfolder="$TOOLS_ROOT/backup/jobs/blind"

rflag=
gflag=
extra_opts=


copymode=""

while getopts dz:t:r:g: opt; do
    case $opt in
        d)  # Dry run
            echo "Dry run selected."
            dflag=1
            extra_opts="$extra_opts -d";;
        r)  # Overide report name
            rflag=1
            report_name="$OPTARG";;
        g)  # Overide log file
            gflag=1
            logfile="$OPTARG";;
        ?)  # Show program usage and exit
            show_usage
            exit 1;;
        :)  # Mandatory arguments not specified
            echo "Option -$OPTARG requires an argument."
            exit 1;;
    esac
done

extra_opts="$extra_opts -r $report_name"
extra_opts="$extra_opts -g $logfile"


copy_snaps () {

    local this_zfs_folder="${zfs_folder}"
    local this_target_folder="${target_folder}"
    local this_latest_snapshot="${latest_snapshot}"
    local this_last_snapshot="${last_snapshot}"
    local this_extra_opts="$extra_opts"
    local results=0

    ./copy-snapshots.sh -c blind \
        -z $this_zfs_folder \
        -t $this_target_folder \
        -f $this_last_snapshot \
        -l $this_latest_snapshot $this_extra_opts
    result=$?

   if [ $result -ne 0 ]; then
       error "copy-snapshots.sh failed.  Not incrementing last-snap."
   else
       notice "Blind backup of ${this_zfs_folder}@${this_latest_snapshot} successful"
       echo "$this_latest_snapshot" > $jobfolder/$job/last-snap
   fi


}


# collect jobs

blind_jobs=`ls -1 $jobfolder`

for job in $blind_jobs; do

    if [ -d "$jobfolder/$job" ]; then
        if [  -f "$jobfolder/$job/folders" ]; then
            . $jobfolder/$job/folders
        else 
            error "$jobfolder/$job/folders does not exist.  This can be set with setup-filesystems.sh."
            exit 1
        fi
        if [  -f "$jobfolder/$job/last-snap" ]; then
            last_snapshot=`cat $jobfolder/$job/last-snap`
        else
            error "$jobfolder/$job/last-snap does not exist.   This must be seeded with the most resent snapshot synced."
        fi

        if [ "${target_folder:0:1}" == "/" ]; then
            # strip leading / 
            # copy_snapshots.sh will add it back
            target_folder="${target_folder#/}"
        fi

        if [ "x$snap_type" != "x" ]; then
            snap_grep="^${zfs_folder}@${snap_type}_"
        else
            snap_grep="^${zfs_folder}@"
        fi

        latest_snapshot=`zfs list -t snapshot -H -o name,creation -s creation | \
                            ${GREP} "${snap_grep}" | \
                            ${CUT} -f 1 | \
                            tail -n 1 | ${CUT} -d "@" -f 2`

        zfs list -t snapshot -H -o name | ${GREP} -q "^${zfs_folder}@${latest_snapshot}"; result=$?
        if [ $result -ne 0 ]; then
            error "Last snapshot ${zfs_source}@${last_snap} does not exist!" 
            exit 1
        fi

        if [ "$last_snap" == "$latest_snapshot" ]; then
            notice "No newer snapshot of type ${snap_type} available.  Nothing to do."
        else

            if [ -n "$dflag" ]; then
                echo "$(color cyan)Running:"
                echo "./copy-snapshots.sh -c blind -z $zfs_folder -t $target_folder -f $last_snapshot -l $latest_snapshot $extra_opts$(color)"
            fi
            
            notice "Blind backup of diff between:"
            notice "${zfs_folder}@${last_snapshot} and"
            notice "${zfs_folder}@${latest_snapshot} to /${target_folder} started"
       
            copy_snaps 
            sleep 5 
            
        fi
    fi

done
