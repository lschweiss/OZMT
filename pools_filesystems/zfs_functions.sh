#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2014  Chip Schweiss

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

#snapjobdir="$TOOLS_ROOT/snapshots/jobs"
stagingjobdir="$TOOLS_ROOT/backup/jobs/staging"
ec2backupjobdir="$TOOLS_ROOT/backup/jobs/ec2"
glacierjobdir="$TOOLS_ROOT/backup/jobs/glacier/active"
glacierjobstatus="$TOOLS_ROOT/backup/jobs/glacier/status"
blindbackupjobdir="$TOOLS_ROOT/backup/jobs/blind"

    #mkdir -p $snapjobdir
    mkdir -p ${stagingjobdir}
    mkdir -p ${ec2backupjobdir}
    mkdir -p ${glacierjobdir}
    mkdir -p ${glacierjobstatus}

    
show_usage() {

cat << EOF_USAGE

Usage: 
  Included with the execution of setup-filesystems.sh

  setupzfs functions are to be used in /{pool}/zfs_tools/etc/pool_filesystems

  setupzfs: 
  Depricated:
      setupzfs {zfs_path} {zfs_options} {snapshots} 

  Prefered:
    setupzfs -z {zfs_path} 
      [-o {zfs_option)]           Set zfs property (repeatable) 
      [-s {snapshot|count}]       Set snapshot policy and count (repeatable)
      [-b {backup_target}]        zfs send/receive target
                                  {pool}/{zfs_folder} or 
                                  {host}:/{pool}/{zfs_folder}  Must have root ssh authorized keys preconfigured.
        [-S {job_schedules}         {job_schedules} ties the backup job to snapshot schedules.   Can be any 
                                    snapshot policy available on the system.   This parameter is repeatable.
        [-p {target_properties}]    Properties to reset on the target zfs folder. (repeatable)  
        [-r]                        Use a replication stream, which will include all child zfs folders and snapshots.
        [-i]                        Use an incremental stream
        [-I]                        Use an incremental stream with all intermediary snapshots
                                    -i and -I are mutually exclusive.
      [-q "{free}|{destination}|{frequency}"] 
                                  Send a quota alert at {free} to {destination} every {frequency} seconds.   
                                    {free} can be xx% or in GB, TB.
                                    (repeatable)
      [-t "{trend}|{scope}|{destination}|{frequency}] 
                                  Send a trend alert when daily usage varies more than {trend} percent over a scope 
                                    of {scope} days.   Send the alert every {frequency} seconds.
                                    Alert goes to {destination}.
                                    (repeatable)
     
    {destination}       Destination can be one or more email addresses separated by ;     

    Seconds         

    1800        30 Minutes
    3600        60 Minutes
    21600       6 Hours
    43200       12 Hours
    86400       24 Hours
    
    
    Quota and trend alerts can have a default set in the variables "QUOTA_REPORT" and "TREND_REPORT" in the pool_filesystems config or
    zfs-config. 

    The variables "ALL_QUOTA_REPORTS" and "ALL_TREND_REPORTS" can contain an email address to BCC all reports to.

     
                           


EOF_USAGE
}


echo "zfs_functions, bash_source: ${BASH_SOURCE[0]}"

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then 
    echo "zfs_function.sh is not meant to be run directly, but is meant to be sourced by"
    echo "setup-filesystems.sh and called by /{pool}/zfs_tools/etc/pool_filesystems"
    show_usage
    exit 1
else
    echo "script ${BASH_SOURCE[0]} is being sourced ..."
fi

setzfs () {

    local zfsfolder="$1"
    local options="$2"
    local option=""

    if [ ! -e "/$pool" ]; then
        echo "ERROR: ZFS pool \"$pool\" does not exist!"
        exit 1
    fi

    for option in $options; do

        thisoption=`echo $option | awk -F "=" '{print $1}'`
        newvalue=`echo $option | awk -F "${thisoption}=" '{print $2}'`
        currentvalue=`zfs get -H $thisoption $zfsfolder|cut -f3`
        
        if [ "$currentvalue" != "$newvalue" ]; then
            echo "$(color cyan)Resetting $(color red)$thisoption $(color cyan)from"
            echo "$(color red)$currentvalue"
            echo "$(color cyan)to"
            echo "$(color red)$newvalue$(color)"
            eval zfs set $option $zfsfolder
        else
            echo "Keeping $thisoption set to $currentvalue"
        fi

    done

}



setupzfs () {

    local zfspath=
    local options=
    local properties=
    local snapshots=
    local backup_target=
    local zfs_backup=
    local target_properties=
    local backup_options=
    local backup_schedules=
    local quota_reports=0
    local trend_reports=0
    local OPTIND=1
   
    while getopts z:o:s:b:S:p:riIq:t: opt; do
        case $opt in
            z)  # Set zfspath
                zfspath="$OPTARG"
                debug "ZFS path set to: $zfspath"
                ;;
            o)  # Add an zfs property
                properties="$properties $OPTARG"
                debug "Adding zfs property: $OPTARG"
                ;;
            s)  # Add a snapshot policy
                snapshots="$snapshots $OPTARG"
                debug "Adding snapshot policy: $OPTARG"
                ;;
            b)  # Backup target
                backup_target="$OPTARG"
                zfs_backup='true'
                debug "Adding backup target: $backup_target"
                ;;
            S)  # Job Schedules
                backup_schedules="$OPTARG $backup_schedules"
                debug "Adding backup schedule: $OPTARG"
                ;;
            p)  # zfs property for backup target
                target_properties="$target_properties $OPTARG"
                debug "Adding backup property for $backup_target: $target_property"
                ;;
            r)  # Use a replication stream
                backup_options="$backup_options -r"
                debug "Setting replication stream for $backup_target"
                ;;
            i)  # Use an incremental stream
                backup_options="-i $backup_options"
                debug "Setting incremental stream for $backup_target"
                ;;
            I)  # Use and incremental stream with intermediary snapshots
                backup_options="-I $backup_options"
                debug "Setting incremental stream with intermediary snapshots for $backup_target"
                ;;
            q)  # Add a quota report
                quota_reports=$(( quota_reports + 1 ))
                local quota_report[$quota_reports]="$OPTARG"
                debug "Adding quota report $OPTARG"
                ;;
            t)  # Add a trend report
                trend_reports=$(( trend_reports + 1 ))
                local trend_report[$trend_reports]="$OPTARG"
                debug "Adding trend report $OPTARG"
                ;;
            ?)  # Show program usage and exit
                show_usage
                return 0
                ;;
            :)  # Mandatory arguments not specified
                error "setupzfs: Option -$OPTARG requires an argument."
                ;;
        
        esac
    done

    #Move to remaining arguments
    shift $(($OPTIND - 1))
    
    if [ "$1" != "" ]; then
        warning "setup zfs using depricated format: setupzfs $*"

        zfspath="$1"
        options="$2"
        snapshots="$3"
        backup_target="$4"
        backup_options="$5"

    else
        options="$properties"
    fi

    snapjobdir="/${pool}/zfs_tools/etc/snapshots/jobs"
    backupjobdir="/${pool}/zfs_tools/etc/backup/jobs"
    reportjobdir="/${pool}/zfs_tools/etc/reports/jobs"

    if [ ! -e "/$pool" ]; then
        echo "ERROR: ZFS pool \"$pool\" does not exist!"
        exit 1
    fi

    mkdir -p $snapjobdir
    mkdir -p $backupjobdir

    if [ -e "/$pool/$zfspath" ]; then
        echo "${pool}/${zfspath} already exists, resetting options"
        setzfs "${pool}/${zfspath}" "$options"
    else
        echo "Creating ${pool}/${zfspath} and setting options"
        zfs create -p $pool/$zfspath
        setzfs "${pool}/${zfspath}" "$options"
    fi

    if [ "x$staging" != "x" ]; then
        if [ ! -e "/$staging" ]; then
            echo "ERROR: ZFS Folder for staging backup must be created first!"
            exit 1
        fi
        
        if [ ! -e "/$staging/$pool" ]; then
            zfs create -p $staging/$pool
        fi   
     
        if [ ! -e "/$staging/$pool/$zfspath" ]; then
            zfs create -p $staging/$pool/$zfspath
        fi
        
        setzfs "$staging/$pool/$zfspath" "atime=off checksum=sha256 ${stagingoptions}"
        stagingjobname=`echo "${staging}/${pool}/${zfspath}" | sed s,/,%,g`
        
        echo "crypt=\"$crypt\"" > ${stagingjobdir}/${stagingjobname}
        echo "source_folder=\"$pool/$zfspath\"" >> ${stagingjobdir}/${stagingjobname}
        echo "target_folder=\"${staging}/${pool}/${zfspath}\"" >> ${stagingjobdir}/${stagingjobname}

    fi

    # Setup EC2 backup

    if [ "$backup" == "ec2" ]; then
        ec2backupjobname=`echo "${backup}/${pool}/${zfspath}" | sed s,/,%,g`
        echo "source_folder=\"${pool}/${zfspath}\"" > ${ec2backupjobdir}/${ec2backupjobname}
        echo "target_folder=\"${ec2_zfspool}/${pool}/${zfspath}\"" >> ${ec2backupjobdir}/${ec2backupjobname}
    fi

    # Setup Amazon Glacier backup

    if [ "x$glacier" != "x" ]; then
        glacierjobname=`echo "${glacier}/${pool}/${zfspath}" | sed s,/,%,g`
        #TODO: Add logic to make sure this zfs folder is not a decendant of another
        #      that is already being backed up via glacier
        echo "job_name=\"${pool}/${zfspath}\"" | sed s,/,%,g > ${glacierjobdir}/${glacierjobname}
        echo "source_folder=\"${pool}/${zfspath}\"" >> ${glacierjobdir}/${glacierjobname}
        echo "glacier_vault=\"${glacier}\"" >> ${glacierjobdir}/${glacierjobname}
        if [ "x$glacier_rotation" == "x" ]; then
            echo "glacier_rotation=\"${glacier_rotation_days}\"" >> ${glacierjobdir}/${glacierjobname}
        else
            echo "glacier_rotation=\"${glacier_rotation}\"" >> ${glacierjobdir}/${glacierjobname}
        fi
    fi

    # Setup Amazon Glacier file level backup

    if [ "x$glacier_files" != "x" ]; then
        glacierjobname=`echo "FILES%${glacier_files}/${pool}/${zfspath}" | sed s,/,%,g`
        echo "job_name=\"FILES/${pool}/${zfspath}\"" | sed s,/,%,g > ${glacierjobdir}/${glacierjobname}
        echo "source_folder=\"${pool}/${zfspath}\"" >> ${glacierjobdir}/${glacierjobname}
        echo "glacier_vault=\"${glacier_files}\"" >> ${glacierjobdir}/${glacierjobname}
        if [ "x$glacier_rotation" == "x" ]; then
            echo "glacier_rotation=\"${glacier_rotation_days}\"" >> ${glacierjobdir}/${glacierjobname}
        else
            echo "glacier_rotation=\"${glacier_rotation}\"" >> ${glacierjobdir}/${glacierjobname}
        fi
    fi

    # Setup blind backups

    if [ "x$blind_backup" != "x" ]; then
        if [ "x$target_folder" == "x" ]; then
            echo "$(color magenta)ERROR: target_folder must be define before calling setupzfs$(color)"
            exit 1
        fi
        blindjobname=`echo "${pool}/${zfspath}" | sed s,/,%,g`
        echo "Setting blind backup to $target_folder"
        mkdir -p "$blindbackupjobdir/$blindjobname"
        echo "zfs_folder=\"${pool}/${zfspath}\"" > $blindbackupjobdir/$blindjobname/folders
        echo "target_folder=\"${target_folder}\"" >> $blindbackupjobdir/$blindjobname/folders
        if [ "x$snap_type" == "x" ]; then
            echo "snap_type=\"daily\"" >> $blindbackupjobdir/$blindjobname/folders
        else
            echo "snap_type=\"$snap_type\"" >> $blindbackupjobdir/$blindjobname/folders
        fi
        echo "$(color cyan)Be sure you schedule blind-increment-job.sh to run after every $snap_type snapshot."
        if [ ! -f "$blindbackupjobdir/$blindjobname/last-snap" ]; then
            echo "$(color cyan)You must seed the file $blindbackupjobdir/$blindjobname/last-snap"
            echo "with the name of the last snapshot that was syncronized.$(color)"
        fi
    fi


    jobname=`echo "${pool}/${zfspath}" | sed s,/,%,g`

    # Setup ZFS backup jobs
    if [[ "$backup" == "zfs" || "$zfs_backup" == 'true' ]] ; then
        echo "Creating backup job:"
        echo "ZFS send to $backup_target"
        mkdir -p "${backupjobdir}/zfs"
        # All variables prefixed by local because this will be sourced in a bash function
        echo "local backup_source=\"${pool}/${zfspath}\"" > "${backupjobdir}/zfs/${jobname}"
        echo "local backup_target=\"${backup_target}\"" >> "${backupjobdir}/zfs/${jobname}"
        echo "local backup_options=\"${backup_options}\"" >> "${backupjobdir}/zfs/${jobname}"
        echo "local backup_schedules=\"${backup_schedules}\"" >> "${backupjobdir}/zfs/${jobname}"
    fi

    # Add quota reports

    if [[ "$QUOTA_REPORT" != "" || $quota_reports -ne 0 ]]; then
        echo "Creating quota reports:"
        mkdir -p "${reportjobdir}/quota"
        echo "local quota_path=\"${pool}/${zfspath}\"" > "${reportjobdir}/quota/${jobname}"
    fi

    if [ "$QUOTA_REPORT" != "" ]; then
        echo "  Setting default report: $QUOTA_REPORT"
        echo "local quota_report[0]=\"$QUOTA_REPORT\"" >> "${reportjobdir}/quota/${jobname}"
    fi

    if [ $quota_reports -ne 0 ]; then
        echo "local quota_reports=$quota_reports" >> "${reportjobdir}/quota/${jobname}"
        report=1
        while [ $report -le $quota_reports ]; do
            echo "  Setting report $report to: ${quota_report[$report]}"
            echo "local quota_report[$report]=\"${quota_report[$report]}\"" >> "${reportjobdir}/quota/${jobname}"
            report=$(( report + 1 ))
        done
    fi



    # Add trend reports

    if [[ "$TREND_REPORT" != "" || $trend_reports -ne 0 ]]; then
        echo "Creating trend reports:"
        mkdir -p "${reportjobdir}/trend"
        echo "local trend_path=\"${pool}/${zfspath}\"" > "${reportjobdir}/trend/${jobname}"
    fi

    if [ "$QUOTA_REPORT" != "" ]; then
        echo "local trend_report[0]=\"$TREND_REPORT\"" >> "${reportjobdir}/trend/${jobname}"
    fi

    if [ $trend_reports -ne 0 ]; then
        echo "local trend_reports=$trend_reports" >> "${reportjobdir}/trend/${jobname}"
        report=1
        while [ $report -le $trend_reports ]; do
            echo "local trend_report[$report]=\"${trend_report[$report]}\"" >> "${reportjobdir}/trend/${jobname}"
            report=$(( report + 1 ))
        done
    fi


    # Prep the snapshot jobs folders
    for snaptype in $snaptypes; do
        if [ ! -d $snapjobdir/$snaptype ]; then
            mkdir "$snapjobdir/$snaptype"
        fi
        rm -f $snapjobdir/$snaptype/${jobname}
        if [ "$staging" != "" ]; then
            rm -f $snapjobdir/$snaptype/${stagingjobname}
        fi
    done

    # Create the jobs
    echo "Creating jobs for ${pool}/${zfspath}:"
    echo -e "Job\t\tType\t\tQuantity"
    if [ "$snapshots" != "" ]; then
        for snap in $snapshots; do
            snaptype=`echo $snap|cut -d "|" -f 1`
            snapqty=`echo $snap|cut -d "|" -f 2`
            echo -e "${jobname}\t${snaptype}\t\t${snapqty}"
            echo $snapqty > $snapjobdir/$snaptype/$jobname
            if [ "$staging" != "" ]; then
                echo "x${snapqty}" > $snapjobdir/$snaptype/${stagingjobname}
            fi
        done
    fi
    echo
}

