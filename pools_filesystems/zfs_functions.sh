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
blindbackupjobdir="$TOOLS_ROOT/backup/jobs/blind"

    #mkdir -p $snapjobdir
    mkdir -p ${stagingjobdir}
    mkdir -p ${ec2backupjobdir}

    
show_usage() {

cat << EOF_USAGE

Usage: 
  Included with the execution of setup-filesystems.sh

  setupzfs functions are to be used in /{pool}/zfs_tools/etc/pool_filesystems

  setupreplication sets up ssh key distribution and name mapping.   This needs to be run before any replicated 
    file systems are defined.   

  setupzfs: 
  Depricated:
      setupzfs {zfs_path} {zfs_options} {snapshots} 

  Prefered:
    setupzfs -z {zfs_path} 
      [-o {zfs_option)]           Set zfs property (repeatable) 
      [-s {snapshot|count}]       Set snapshot policy and count (repeatable)
      [-R {target|mode|options|freqency}] 
                                  Set a replication target (repeatable)
                                    Target is in the form:
                                      {host}:{zfs_folder}
                                        host is the fix hostname or ip associated with the replication target
                                        this should reside on a backend network or VLAN for locally connected hosts
                                    Mode is one of the following:
                                      m     mbuffer transport
                                      s     ssh tunnel
                                      b     bbcp transport
                                    Options is specified by include any, all or none of the following:
                                      l     lz4 compress the stream
                                      g     gzip compress the stream
                                      o     encrypt the stream with openssl
                                    Frequency is in the form of ####{unit}
                                      Acceptable units are:
                                      m     minutes
                                      h     hours
                                      d     days
                                      w     weeks

                                    Requires zpool feature bookmarks

                                    All replication targets in receive mode will have snapshot and quota jobs 
                                    suspended automatically.  

                                    Replication status is stored in ${pool}/var/db/replication/${zfsfolder}

                                    The folder definition must be the same on all replication points.   

                                    Each time a zfs folder under replication's configuration is updated, all 
                                    target's configuration for the coresponding folder will updated.

        [-V {vIP}]                  The virtual IP that follows this dataset.

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
      [-q "{free}|{alert_type}|{destination}|{frequency}"] 
                                  Send a quota alert at {free} to {destination} every {frequency} seconds.   
                                    {alert_type} can be any adjective, typically "warning", or "critical"
                                    {free} can be xx% or in GB, TB.
                                    (repeatable)
      [-t "{trend}|{scope}|{alert_type}|{destination}|{frequency}] 
                                  Send a trend alert when daily usage varies more than {trend} percent over a scope 
                                    of {scope} days.   Send the alert every {frequency} seconds.
                                    Alert goes to {destination}.
                                    (repeatable)
     
    {destination}       Destination can be one or more email addresses separated by ;     

    {frequency}         Frequency of a report.  Defaults to seconds unless a unit is specified (m,h,d,w)

    Seconds         

    1800        30 Minutes
    3600        60 Minutes
    21600       6 Hours
    43200       12 Hours
    86400       24 Hours
    
    
    Quota and trend alerts can have a default set in the variables "QUOTA_REPORT" and "TREND_REPORT" in the pool_filesystems config or
    zfs-config. 

    The variables "ALL_QUOTA_REPORTS" and "ALL_TREND_REPORTS" can contain an email address to BCC all reports to.

    setupreplication:

      setup_replication.sh: Wrapper script for setupreplication function.  Used to manually run replication configuration functions
        from the shell or external scripts.

      setupreplication
        [-m {target|hostname}]      Target vIP to hostname mapping (repeatable)
                                      For each target a mapping of host(s) which the vIP may be on.
                                      There will be one entry for each host that this dataset can reside on.
                                        For example a primary and DR site.  The primary site has two host for an HA pool.
                                            -m dr-replication01|dr-host
                                            -m pr-replication01|pr-host01
                                            -m pr-replication01|pr-host02
        [-M {target}                Remove a target vIP mapping.
                                      This will remove all entries with the referenced vIP.   
                                        Using the above example
                                          -M pr-replication01 
                                        would remove both the pr-host01 and pr-host02 entries.
  


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

        thisoption=`echo $option | ${AWK} -F "=" '{print $1}'`
        newvalue=`echo $option | ${AWK} -F "${thisoption}=" '{print $2}'`
        currentvalue=`zfs get -H $thisoption $zfsfolder|${CUT} -f3`
        
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

# Test an IP address for validity:
# Usage:
#      valid_ip IP_ADDRESS
#      if [[ $? -eq 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_ip IP_ADDRESS; then echo good; else echo bad; fi
#
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    unset IFS
    return $stat
}

islocal () {

    local host="$1"
    local ip=

    # Is this a raw IP address?

    if valid_ip $host; then
        ip="$host"
    else
        # See if it's in /etc/hosts
        getent hosts $host | ${AWK} -F " " '{print $1}' > ${TMP}/islocal_host_$$
        if [ $? -eq 0 ]; then
            ip=`cat ${TMP}/islocal_host_$$`
        else
            # Try DNS
            dig +short $host > ${TMP}/islocal_host_$$
            if [ $? -eq 0 ]; then
                ip=`cat ${TMP}/islocal_host_$$`
            else
                echo "$host is not valid.  It is not an raw IP, in /etc/host or DNS resolvable."
                return 1
            fi
        fi
    fi
    # See if we own it.

#    echo -n "Checking if $ip is local..."

    case $os in
        'SunOS')
            ifconfig -a | ${GREP} -q -F "inet $ip"
            if [ $? -eq 0 ]; then
                # echo "yes."
                return 0
            else
                # echo "no."
                return 1
            fi
            ;;
        'Linux')
            ifconfig -a | ${GREP} -q -F "inet addr:$ip"
            if [ $? -eq 0 ]; then
                # echo "yes."
                return 0
            else
                # echo "no."
                return 1
            fi
            ;;
    esac

}


setupreplication () {

    local target_maps=
    local OPTIND=1
    local mapdir=/var/zfs_tools/replication/maps
    if [ -f /var/zfs_tools/replication/hosts ]; then
        local rep_hosts=`cat /var/zfs_tools/replication/hosts`
    else
        echo "/var/zfs_tools/replication/hosts does not exist."
        echo "Please populate this file with the host names of all replication hosts including this one."
        return 1
    fi
    local vip=
    local host=
    local rep_host=

    while getopts m:M: opt; do
        case $opt in
            m) # Add a new mapping
                IFS='|'
                read -r vip host <<< "$OPTARG"
                unset IFS
                # We must be able to connect via ssh to both the vip and the host provided
                echo "Validating ${vip} and ${host}..."
                if islocal $vip; then
                    echo "$vip is local."
                else 
                    timeout 5s ssh root@${vip} echo "$vip connected successfully."
                    if [ $? -ne 0 ]; then
                        echo "Cannot connect via ssh to ${vip}.  Please verify ssh pairing is configured."
                        return 1
                    fi
                fi
                if islocal $host; then
                    echo "$host is local."
                else
                    timeout 5s ssh root@${host} echo "$host connected successfully."
                    if [ $? -ne 0 ]; then
                        echo "Cannot connect via ssh to ${vip}.  Please verify ssh pairing is configured."
                        return 1
                    fi
                fi
                for rep_host in $rep_hosts; do
                    echo "Adding $vip mapping to $rep_host"
                    if islocal $rep_host; then
                        mkdir -p ${mapdir}
                        echo "$host" >> ${mapdir}/${vip}
                    else
                        # echo "Connecting remotely to $rep_host"
                        ssh root@${rep_host} "mkdir -p ${mapdir};echo \"$host\" >> ${mapdir}/${vip}"
                    fi
                done
                ;;
            M) # Remove a mapping
                vip="$OPTARG"
                if [ -f "${mapdir}/${vip}" ]; then
                    for rep_host in $rep_hosts; do
                        echo "Removing $vip mapping from $rep_host"
                        if islocal $rep_host; then
                            rm -f ${mapdir}/${vip}
                        else
                            ssh root@${rep_host} "rm -f ${mapdir}/${vip}"
                        fi
                    done
                else
                    echo "$vip is not a current mapping"
                    return 1
                fi
                ;;
            ?)  # Show program usage and exit
                show_usage
                return 1
                ;;
            :)  # Mandatory arguments not specified
                error "setupreplication: Option -$OPTARG requires an argument."
                return 1
                ;;
        esac
    done

}

setupzfs () {

    local zfspath=
    local options=
    local properties=
    local snapshots=
    local replication_targets=
    local vip=
    local backup_target=
    local zfs_backup=
    local target_properties=
    local backup_options=
    local backup_schedules=
    local quota_reports=0
    local trend_reports=0
    local OPTIND=1

    if [ "$gen_new_pool_config" == 'true' ]; then
        if [ -f "/${pool}/zfs_tools/etc/filesystem_template" ]; then
            notice "Converting setup config using template" 
        else
            warning "/${pool}/zfs_tools/etc/filesystem_template does not exist.  Create this file for automatic config conversion."
        fi
    fi
   
    while getopts z:o:s:R:V:b:S:p:riIq:t: opt; do
        case $opt in
            z)  # Set zfspath
                zfspath="$OPTARG"
                debug "ZFS path set to: $zfspath"
                if [ "$gen_new_pool_config" == 'true' ]; then
                    config_file="/${pool}/zfs_tools/etc/pool-filesystems.new/$(echo $zfspath | ${SED} s,/,%,g)"
                    cp "/${pool}/zfs_tools/etc/filesystem_template" "$config_file"
                fi
                ;;
            o)  # Add an zfs property
                properties="$properties $OPTARG"
                debug "Adding zfs property: $OPTARG"
                ;;
            s)  # Add a snapshot policy
                snapshots="$snapshots $OPTARG"
                debug "Adding snapshot policy: $OPTARG"
                ;;
            R)  # Add a replication target
                replication_targets="$replication_target $OPTARG"
                debug "Adding replication target: $OPTARG"
                ;;
            V)  # vIP associated with this dataset
                vip="$OPTARG"
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
        if [ "$gen_new_pool_config" == 'true' ]; then
            search=`echo $zfspath | ${SED} 's,\/,\\\/,g'`
            ${SED} -n "/^setupzfs -z \"${search}\"/,/^$/p" /${pool}/zfs_tools/etc/pool-filesystems >> $config_file
        fi
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

    zfs get creation ${pool}/${zfspath} 1> /dev/null 2> /dev/null
    if [ $? -eq 0 ]; then
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
        stagingjobname=`echo "${staging}/${pool}/${zfspath}" | ${SED} s,/,%,g`
        
        echo "crypt=\"$crypt\"" > ${stagingjobdir}/${stagingjobname}
        echo "source_folder=\"$pool/$zfspath\"" >> ${stagingjobdir}/${stagingjobname}
        echo "target_folder=\"${staging}/${pool}/${zfspath}\"" >> ${stagingjobdir}/${stagingjobname}

    fi

    # Setup EC2 backup

    if [ "$backup" == "ec2" ]; then
        ec2backupjobname=`echo "${backup}/${pool}/${zfspath}" | ${SED} s,/,%,g`
        echo "source_folder=\"${pool}/${zfspath}\"" > ${ec2backupjobdir}/${ec2backupjobname}
        echo "target_folder=\"${ec2_zfspool}/${pool}/${zfspath}\"" >> ${ec2backupjobdir}/${ec2backupjobname}
    fi

    # Setup Amazon Glacier backup
    glacierjobdir="/${pool}/zfs_tools/etc/backup/jobs/glacier"
    glacierjobstatus="/${pool}/zfs_tools/var/backup/jobs/glacier/status"

    mkdir -p ${glacierjobdir}
    mkdir -p ${glacierjobstatus}

 
    if [ "x$glacier" != "x" ]; then
        glacierjobname=`echo "${glacier}/${pool}/${zfspath}" | ${SED} s,/,%,g`
        #TODO: Add logic to make sure this zfs folder is not a decendant of another
        #      that is already being backed up via glacier
        echo "job_name=\"${pool}/${zfspath}\"" | ${SED} s,/,%,g > ${glacierjobdir}/${glacierjobname}
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
        glacierjobname=`echo "FILES%${glacier_files}/${pool}/${zfspath}" | ${SED} s,/,%,g`
        echo "job_name=\"FILES/${pool}/${zfspath}\"" | ${SED} s,/,%,g > ${glacierjobdir}/${glacierjobname}
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
        blindjobname=`echo "${pool}/${zfspath}" | ${SED} s,/,%,g`
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


    jobname=`echo "${pool}/${zfspath}" | ${SED} s,/,%,g`

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
            snaptype=`echo $snap|${CUT} -d "|" -f 1`
            snapqty=`echo $snap|${CUT} -d "|" -f 2`
            echo -e "${jobname}\t${snaptype}\t\t${snapqty}"
            echo $snapqty > $snapjobdir/$snaptype/$jobname
            if [ "$staging" != "" ]; then
                echo "x${snapqty}" > $snapjobdir/$snaptype/${stagingjobname}
            fi
        done
    fi
    echo
    

    # Create replication target maps before the jobs

    if [ "$target_maps" != "" ]; then
        mapdir="/${pool}/zfs_tools/etc/replication/maps"
        if [ -d ${mapdir}/${jobname} ]; then
            rm -rf ${mapdir}/${jobname}
        fi
        mkdir -p ${mapdir}/${jobname}

        for map in $target_maps; do
            IFS='|'
            read -r target_vip target_hostname <<< "$map"
            unset IFS
            echo "$target_hostname" >> ${mapdir}/${jobname}/${target_vip}            
         done
    fi


    # Create replication jobs

    replication=`zfs get -H -o value $zfs_replication_property ${pool}/${zfspath}`

    if [ "$replication_targets" != "" ]; then
        if [[ "$replication" != '-' || "$replication" != "$zfspath" ]]; then
            error "Replication is already defined on parent zfs folder $replication"
            error "Remove replication from that folder before adding it to this folder ($zfspath)"
            return 1
        fi         

        mkdir -p /${pool}/zfs_tools/etc/replication/jobs/${jobname}
        mkdir -p /${pool}/zfs_tools/var/replication/jobs/{definition,pending,running,complete,failed,sequence}
        mkdir -p /${pool}/zfs_tools/var/replication/primary/${jobname}

        for target_def in $replication_targets; do
            IFS='|' 
            read -r target mode options frequency <<< "${target_def}"
            unset IFS
            # Test access to target
            timeout 5s ssh root@target "echo Hello from $target"
            if [ $? -ne 0 ]; then
                error "Cannot connect to target host at $target, ignore this if the target is down."
            fi
            target_job="/${pool}/zfs_tools/etc/replication/jobs/${jobname}/$(foldertojob $target)"

            echo "target=\"${target}\"" >> $target_job
            echo "mode=\"${mode}\"" >> $target_job
            echo "options=\"${options}\"" >> $target_job
            echo "frequency=\"${frequency}\"" >> $target_job
        done
        zfs set ${zfs_replication_property}=${zfspath} ${pool}/${zfspath}
        replication=`zfs get -H -o value $zfs_replication_property $zfspath`
    fi
   

    # Syncronize all replication targets

    if [ "$replication" != "-" ]; then
        # Get target(s) from parent definition
        parent_jobname="$(foldertojob $replication)"
        replication_targets=`ls -1 /${pool}/zfs_tools/etc/replication/jobs/${parent_jobname}`
        for replication_target in $replication_targets; do
            source /${pool}/zfs_tools/etc/replication/jobs/${replication_target}
            # Determine the host and pool
            t_host=`echo "$target" | ${AWK} -F '/' '{print $1}'`
            t_pool=`echo "$target" | ${AWK} -F '/' '{print $2}'`
                  
            # push a copy of this definition
            # Rsync is used to only update if the definition changes.  Its verbose output
            #   will list the definition being updated if it sync'd.  This will cause the
            #   trigger of a run to happen only if there were changes, short circuiting the 
            #   potential for an endless loop.
            if ! islocal $t_host; then
                rsync -cv -e ssh /${pool}/zfs_tools/etc/pool-filesystems/$(foldertojob $zfspath) \
                    root@${t_host}:/${t_pool}/zfs_tools/etc/pool-filesystems/$(foldertojob $zfspath) > \
                    ${TMP}/setup_filesystem_replication_$$
                if [ $? -ne 0 ]; then
                    error "Could not replicate definition to $t_host"
                else
                    cat ${TMP}/setup_filesystem_replication_$$ | \
                        grep -q -F "/${pool}/zfs_tools/etc/pool-filesystems/$(foldertojob $zfspath)"
                    if [ $? -eq 0 ]; then
                        echo "Target config updated on ${t_host}.  Triggering setup run."
                        ssh root@${t_host} "/opt/zfstools/pools_filesystems/setup-filesystems.sh"
                    fi
                fi
            fi

        done
    fi

    if [[ "$replication" == "$zfspath" && "$replication_targets" == "" ]]; then
            # Previous replication job for this path has been removed.   Remove the job definitions.
                rm -rf /${pool}/zfs_tools/etc/replication/jobs/${jobname}
                rm -rf /${pool}/zfs_tools/var/replication/primary/${jobname}

            # TODO: Remove replication bookmarks



            

    fi


    

    # Define vIP

    if [ "$vip" != "" ]; then
        mkdir -p /${pool}/zfs_tools/etc/replication/vip
        echo "$vip" > /${pool}/zfs_tools/etc/replication/vip/${jobname}
    fi
    




}

