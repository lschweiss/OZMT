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
    cat USAGE
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


clear_cache () {
    local pool="$1"

    if [ -d "/${pool}/zfs_tools/var/cache/zfs_cache" ]; then
        rm -rf "/${pool}/zfs_tools/var/cache/zfs_cache"
    fi
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
    local snapshot_jobs=0
    local count=
    local dataset_name=
    local replication=
    local replication_source=
    local replication_targets=
    local replication_count=0
    local replication_source_pool=
    local replication_failure_limit=
    local replication_previous_snapshot=
    local vip=0
    local cifs=
    local cifs_template=
    local cifs_share=
    local smb_valid_users=
    local backup_target=
    local zfs_backup=
    local target_properties=
    local backup_options=
    local backup_schedules=
    local quota_reports=0
    local trend_reports=0
    local child=
    local children=
    local OPTIND=1


    if [ -t 1 ]; then
        echo;echo;echo
    fi

    if [ "$gen_new_pool_config" == 'true' ]; then
        if [ -f "/${pool}/zfs_tools/etc/filesystem_template" ]; then
            notice "Converting setup config using template" 
        else
            warning "/${pool}/zfs_tools/etc/filesystem_template does not exist.  Create this file for automatic config conversion."
        fi
    fi
   
    while getopts z:o:s:S:n:R:V:F:L:P:b:q:t:C:c:v: opt; do
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
                snapshot_jobs=$(( snapshot_jobs + 1))
                debug "Adding snapshot policy: $OPTARG"
                ;;
            S)  # Add a recursive snapshot policy
                r_snapshots="$r_snapshots $OPTARG"
                snapshot_jobs=$(( snapshot_jobs + 1))
                debug "Adding recursive snapshot policy: $OPTARG"
                ;;
            n)  # Dataset name
                dataset_name="$OPTARG"
                debug "Setting name to: $dataset_name"
                ;;
            R)  # Add a replication target
                replication_targets="$replication_targets $OPTARG"
                replication_count=$(( replication_count + 1 ))
                debug "Adding replication target: $OPTARG"
                ;;
            V)  # vIP associated with this dataset
                vip=$(( vip + 1 ))
                vip[$vip]="$OPTARG"
                debug "Adding vIP ${vip[$vip]}"
                ;;
            C)  # enable CIFS on this dataset
                cifs='true'
                cifs_template="$OPTARG"
                debug "Enabling CIFS on this dataset"
                ;;
            c)  # share this folder via CIFS
                cifs_share="$OPTARG"
                debug "Setting CIFS share using $cifs_share"
                ;;
            v)  # valid cifs users
                smb_valid_users="$OPTARG"
                debug "Setting CIFS valid user to: $smb_valid_users"
                ;;
            F)  # Default source pool
                default_source_folder="$OPTARG"
                debug "Setting default replication source folder to: $default_source_folder"
                ;;
            L)  # Replication failure limit
                replication_failure_limit="$OPTARG"
                debug "Setting replication failure limit to: $replication_failure_limit"
                ;;
            P)  # Previous Snapshot
                replication_previous_snapshot="$OPTARG"
                ;;
            b)  # Backup target
                error "Backup target no longer supported"
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

    jobname=`echo "${pool}/${zfspath}" | ${SED} s,/,%,g`
    simple_jobname=`echo "${zfspath}" | ${SED} s,/,%,g`



    if [ "$dataset_name" != "" ]; then
        # Test for valid characters
        ${GREP} -qv '[^0-9A-Za-z\$\%\(\)\=\+\-\#\:\{\}]' <<< $dataset_name
        if [ $? -eq 0 ]; then
            debug "Dataset name $dataset_name passes character test"
        else
            error "Dataset name $dataset_name contains invalid characters."
        fi
        zfs set ${zfs_dataset_property}=${dataset_name} ${pool}/${zfspath}
        #zfs set ${zfs_replication_dataset_property}=${dataset_name} ${pool}/${zfspath}
        mkdir -p /${pool}/zfs_tools/var/replication/datasets
        echo "${pool}/${zfspath}" > /${pool}/zfs_tools/var/replication/datasets/${dataset_name}
    fi

    # Replication requirements

    if [[ "$replication_targets" != "" && "$dataset_name" == "" ]]; then
        error "Replication defined without defining a dataset name '-n'"
        return 1
    fi

    # Determine if this is a subfolder of a replicated folder
    # Examine each folder level above this one
    echo "Checking for parent replication"
    parent_replication='off'
    i=1 
    check_folder=`echo "$zfspath"|cut -d "/" -f ${i}`
    until [ "$check_folder" == "$zfspath" ]; do
        echo "Checking folder: ${pool}/$check_folder  i=$i"
        replication=`zfs get -H -o value $zfs_replication_property ${pool}/${check_folder} 2>/dev/null`
        if [ "$replication" == 'on' ]; then
            echo "Parent replication is ON, parent: $check_folder"
            parent_replication='on'
            replication_parent="$check_folder"
            replication_dataset=`zfs get -H -o value $zfs_replication_dataset_property ${pool}/${check_folder}`
            replication_source=`cat /${pool}/zfs_tools/var/replication/source/${replication_dataset}`
            debug "Replication source: $replication_source"
            break
        fi
        i=$(( i + 1 ))
        check_folder="${check_folder}/$(echo "$zfspath"|cut -d "/" -f ${i})"
        echo "check_folder: $check_folder  zfspath: $zfspath"
    done

    
    # If this folder is a sub-folder of a replicated folder on a target system, the creation and configuration
    # of this folder will be done with zfs receive.

    if [[ "$parent_replication" == 'off' || ( "$parent_replication" == 'on' && "${pool}:${zfspath}" == "$replication_source"* ) ]]; then
        zfs get creation ${pool}/${zfspath} 1> /dev/null 2> /dev/null
        if [ $? -eq 0 ]; then
            echo "${pool}/${zfspath} already exists, resetting options"
            setzfs "${pool}/${zfspath}" "$options"
            new_folder='false'
        else
            echo "Creating ${pool}/${zfspath} and setting options"
            zfs create -p $pool/$zfspath
            setzfs "${pool}/${zfspath}" "$options"
            new_folder='true'
            echo "$pool/$zfspath" >> ${TMP}/setup_filesystem_reset_replication_ignore
        fi
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
        # Depricated:
            mkdir -p "${reportjobdir}/quota"
            echo "local quota_path=\"${pool}/${zfspath}\"" > "${reportjobdir}/quota/${jobname}"
        # New:
            zfs set ${zfs_quota_reports_property}=${quota_reports} ${pool}/${zfspath}
    else
            zfs inherit ${zfs_quota_reports_property} ${pool}/${zfspath}
    fi

    if [ "$QUOTA_REPORT" != "" ]; then
        echo "  Setting default report: $QUOTA_REPORT"
        # Depricated:
            echo "local quota_report[0]=\"$QUOTA_REPORT\"" >> "${reportjobdir}/quota/${jobname}"
        # New:
            zfs set ${zfs_quota_report_property}:0="${QUOTA_REPORT}" ${pool}/${zfspath}
    fi

    if [ $quota_reports -ne 0 ]; then
        echo "local quota_reports=$quota_reports" >> "${reportjobdir}/quota/${jobname}"
        report=1
        while [ $report -le $quota_reports ]; do
            echo "  Setting report $report to: ${quota_report[$report]}"
            # Depricated:
                echo "local quota_report[$report]=\"${quota_report[$report]}\"" >> "${reportjobdir}/quota/${jobname}"
            # New:
                zfs set ${zfs_quota_report_property}:${report}="${quota_report[$report]}" ${pool}/${zfspath}
    
            report=$(( report + 1 ))
        done
    fi



    # Add trend reports

    if [[ "$TREND_REPORT" != "" || $trend_reports -ne 0 ]]; then
        echo "Creating trend reports:"
        # Depricated
            mkdir -p "${reportjobdir}/trend"
            echo "local trend_path=\"${pool}/${zfspath}\"" > "${reportjobdir}/trend/${jobname}"
        # New:
            zfs set ${zfs_trend_reports_property}=${trend_reports} ${pool}/${zfspath}
    else
            zfs inherit ${zfs_trend_reports_property} ${pool}/${zfspath}
    fi

    if [ "$TREND_REPORT" != "" ]; then
        # Depricated
            echo "local trend_report[0]=\"$TREND_REPORT\"" >> "${reportjobdir}/trend/${jobname}"
        # New:
            zfs set ${zfs_trend_report_property}:0="${TREND_REPORT}" ${pool}/${zfspath}
    fi

    if [ $trend_reports -ne 0 ]; then
        echo "local trend_reports=$trend_reports" >> "${reportjobdir}/trend/${jobname}"
        report=1
        while [ $report -le $trend_reports ]; do
            # Depricated:
                echo "local trend_report[$report]=\"${trend_report[$report]}\"" >> "${reportjobdir}/trend/${jobname}"
            # New:
                zfs set ${zfs_trend_report_property}:${report}="${trend_report[$report]}" ${pool}/${zfspath}

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

    if [ $snapshot_jobs -gt 0 ]; then
        zfs set ${zfs_snapshots_property}=${snapshot_jobs} ${pool}/${zfspath}
    else
        zfs inherit ${zfs_snapshots_property} ${pool}/${zfspath}
    fi

    count=0

    # Create the snapshot jobs
    echo "Creating snapshot jobs for ${pool}/${zfspath}:"
    echo "snapshots: $snapshots"
    echo -e "Job\t\tType\t\tQuantity"
    if [ "$snapshots" != "" ]; then
        for snap in $snapshots; do
            count=$(( count + 1))
            zfs set ${zfs_snapshot_property}:${count}="$snap" ${pool}/${zfspath}
            # Depricated:
                snaptype=`echo $snap|${CUT} -d "|" -f 1`
                snapqty=`echo $snap|${CUT} -d "|" -f 2`
                echo -e "${jobname}\t${snaptype}\t\t${snapqty}"
                echo "${snapqty}" > $snapjobdir/$snaptype/$jobname
            if [ "$staging" != "" ]; then
                echo "x${snapqty}" > $snapjobdir/$snaptype/${stagingjobname}
            fi
        done
    fi
    echo

    # Create the recursive snapshot jobs
    echo "Creating recursive snapshot jobs for ${pool}/${zfspath}:"
    echo "snapshots: $r_snapshots"
    echo -e "Job\t\tType\t\tQuantity"
    if [ "$r_snapshots" != "" ]; then
        for snap in $r_snapshots; do
            zfs set ${zfs_snapshot_property}:${count}="recursive:${snap}" ${pool}/${zfspath}
            # Depricated:
                snaptype=`echo $snap|${CUT} -d "|" -f 1`
                snapqty=`echo $snap|${CUT} -d "|" -f 2`
                echo -e "${jobname}\t${snaptype}\t\t${snapqty}"
                echo "r${snapqty}" > $snapjobdir/$snaptype/$jobname
        done
    fi
    echo
   
####
####
##
## Replication
##
####
####


 

    # Create replication target maps before the jobs

    if [ "$target_maps" != "" ]; then
        mapdir="/${pool}/zfs_tools/etc/replication/maps"
        if [ -d ${mapdir}/${simple_jobname} ]; then
            rm -rf ${mapdir}/${simple_jobname}
        fi
        mkdir -p ${mapdir}/${simple_jobname}

        for map in $target_maps; do
            IFS='|'
            read -r target_vip target_hostname <<< "$map"
            unset IFS
            echo "$target_hostname" >> ${mapdir}/${jobname}/${target_vip}            
         done
    fi

    ##
    # Collect already defined replication information
    ##
    replication_job_dir="/${pool}/zfs_tools/var/replication/jobs"    
    source_tracker="/${pool}/zfs_tools/var/replication/source/${dataset_name}"
    dataset_targets="/${pool}/zfs_tools/var/replication/targets/${dataset_name}"

    replication=`zfs get -H -o value $zfs_replication_property ${pool}/${zfspath} 2>/dev/null`
    if [ "$replication" != '-' ]; then
        replication_source_reported=`zfs get -H -o source ${zfs_replication_property} ${pool}/${zfspath}`
        if [ "$replication_source_reported" == "local" ]; then
            replication_parent="${zfspath}"
        else
            replication_parent_full=`echo $replication_source_reported |  ${AWK} -F "inherited from " '{print $2}' `
            IFS="/"
            read -r junk replication_parent <<< "$replication_parent_full"
            unset IFS
        fi
        replication_dataset_name=`zfs get -H -o value $zfs_replication_dataset_property ${pool}/${zfspath} 2>/dev/null`
    else
        replication_parent="-"
    fi

#    pause

#    ##
#    # Prepare replication for new children
#    ##
#    set -x    
#
#    if [[ "$parent_replication" == 'on' && "$new_folder" == 'true' ]]; then
#        # Find replication jobs and add info to the job_status file
#        if [ -d "/$pool/zfs_tools/var/replication/jobs/definitions" ]; then  
#            definitions=`find "/$pool/zfs_tools/var/replication/jobs/definitions/" -type f`
#            for definition in $definitions; do
#                cat $definition | ${GREP}  "dataset_name" | ${GREP} -q "$replication_dataset_name"
#                if [ $? -eq 0 ]; then
#                    pause
#                    # Normally we would just source the definition and status file, however,
#                    # this could potentially disrupt local variables.
#                    this_job_status_file=`cat $definition | \
#                                          ${GREP} "job_status" | \
#                                          ${AWK} -F "=" '{print $2}' | \
#                                          ${SED} 's/"//g'`
#                    update_job_status "$this_job_status_file" "new_children" "+1"
#                    this_child_count=`cat $this_job_status_file | \
#                                          ${GREP} "new_children" | \
#                                          ${AWK} -F "=" '{print $2}' | \
#                                          ${SED} 's/"//g'`
#                    update_job_status "$this_job_status_file" "new_child[${this_child_count}]" "$zfspath"
#                fi
#            done
#        fi
#    fi
#
#    set +x
#
#    pause

    

    # TODO: new requirements:  Need to support more than one replication pair.
    #       No target host specification.  Pool names must resolve to an IP or vIP.
    #       New variable: targets, containing all pool/folder targets for this dataset
    #           If more than two targets are active snapshot deletion becomes a post
    #           sync process across all inactive targets.
    
    ##
    # Clean up if replication has been removed from the definition
    ##
    echo "Replication parent: $replication_parent"

    if [[ "$replication_parent" == "$zfspath" && "$replication_targets" == "" ]]; then
        # Previous replication job for this path has been removed.   Remove the job definitions.
        debug "Removing previous replication job ${simple_jobname}"
        clear_cache $pool
        rm -rf ${replication_job_dir}/definitions/${simple_jobname}
        rm -f /${pool}/zfs_tools/var/replication/source/${simple_jobname}
        zfs get creation ${pool}/${zfspath} &> /dev/null
        if [ $? -eq 0 ]; then
            # Remove zfs properties
            zfs inherit $zfs_replication_property ${pool}/${zfspath}
            zfs inherit $zfs_replication_dataset_property ${pool}/${zfspath}
            zfs inherit $zfs_replication_endpoints_property ${pool}/${zfspath}
        fi
    
        replication_parent='-'
        replication='off'
        replication_dataset_name=
        replication_parent_full=

        # TODO: Remove replication snapshots



        # TODO: Clean up job status, pending jobs, suspended, failed etc.


         
    fi


   
    # Flush dataset_targets file and rebuild
    if [ "$dataset_name" != "" ]; then
        rm "$dataset_targets" 2> /dev/null
        rm "${TMP}/dataset_targets_$$" 2> /dev/null
    fi


    ##
    # Build replication jobs
    ##

    if [ "$replication_targets" != "" ]; then

        clear_cache $pool

        if [[ "$replication_parent" != '-' && "$replication_parent" != "${zfspath}" ]]; then
            warning "Replication is already defined on parent zfs dataset $replication_parent"
        fi         

        mkdir -p /${pool}/zfs_tools/var/replication/jobs/{definitions,pending,running,synced,complete,failed,suspended,status}
        rm -rf "${replication_job_dir}/definitions/${simple_jobname}"
        mkdir -p "${replication_job_dir}/definitions/${simple_jobname}"
        mkdir -p /${pool}/zfs_tools/var/replication/{source,targets}
        if [ ! -f ${source_tracker} ]; then
            # TODO: validate the default_source_folder
            if [ "$default_source_folder" != "" ]; then
                echo "$default_source_folder" > "$source_tracker"
            else
                error "New replication configuration for $simple_jobname, but no default source folder set."
                return 1
            fi
        fi

        if [ "$replication_failure_limit" == "" ]; then
            replication_failure_limit="default"
        fi

        for target_def in $replication_targets; do
            target_job=
            echo "Configuring $target_def"
            IFS='|' 
            read -r targetA targetB mode options frequency <<< "${target_def}"
            IFS=":"
            # Split targets into host and folder
            read -r targetA_pool targetA_folder <<< "$targetA"
            read -r targetB_pool targetB_folder <<< "$targetB"
            unset IFS

            # Update dataset_targets file
            if [ -f "$datset_targets" ]; then
                cp "$datset_targets" "${TMP}/dataset_targets_$$"
            fi
            echo "$targetA" >> "${TMP}/dataset_targets_$$"
            echo "$targetB" >> "${TMP}/dataset_targets_$$"
            cat "${TMP}/dataset_targets_$$" | sort -u > "$dataset_targets"
            rm "${TMP}/dataset_targets_$$"

            echo "targetA: $targetA"
            echo "targetB: $targetB"
            echo "mode: $mode"
            echo "options: $options"
            echo "freq: $frequency"
            echo "$targetA_pool"
            echo "$targetA_folder"
            echo "$targetB_pool"
            echo "$targetB_folder"

            if [ "$mode" == 'L' ]; then
                # This is a local replication with source and target on the same host
                # There will be two definitions for this dataset at two zfs paths
                if [ "$targetA_pool" != "$targetB_pool" ]; then
                    error "Local replication specified with different pools.  Use mbuffer transport, even if on the same host."
                    return 1
                fi
                debug "Creating replication job between $targetA_folder for $targetB_folder on this host."
                # Create jobs for this folder definition
                if [ "$targetA_folder" == "$zfspath" ]; then
                    job_status="${replication_job_dir}/status/${simple_jobname}#${targetB_pool}:$(foldertojob $targetB_folder)"
                    target_job="${replication_job_dir}/definitions/${simple_jobname}/${targetB_pool}:$(foldertojob $targetB_folder)"
                    echo "target=\"${targetB}\"" > $target_job
                    echo "target_pool=\"${targetB_pool}\"" >> $target_job
                    echo "target_folder=\"${targetB_folder}\"" >> $target_job
                fi
                if [ "$targetB_folder" == "$zfspath" ]; then
                    job_status="${replication_job_dir}/status/${simple_jobname}#${targetA_pool}:$(foldertojob $targetB_folder)"
                    target_job="${replication_job_dir}/definitions/${simple_jobname}/${targetA_pool}:$(foldertojob $targetA_folder)"
                    echo "target=\"${targetA}\"" > $target_job

                    echo "target_pool=\"${targetA_pool}\"" >> $target_job
                    echo "target_folder=\"${targetA_folder}\"" >> $target_job
                fi
            else
                # Remote replication
                # Create jobs for local folder

                if islocal $targetA_pool; then
                    # Test access to targetB_pool
                    timeout 5s ssh root@${targetB_pool} "echo Hello from ${targetB_pool}"
                    if [ $? -ne 0 ]; then
                        error "Cannot connect to target host at ${targetB_pool}, ignore this if the target is down."
                    fi
                    # Create a job for this replication pair
                    debug "Creating replication job between this host $targetA_pool and host $targetB_pool for $targetA_folder"
                    job_status="${replication_job_dir}/status/${simple_jobname}#${targetB_pool}:$(foldertojob $targetB_folder)"
                    target_job="${replication_job_dir}/definitions/${simple_jobname}/${targetB_pool}"
                    echo "target=\"${targetB}\"" > $target_job
                    echo "target_pool=\"${targetB_pool}\"" >> $target_job
                    echo "target_folder=\"${targetB_folder}\"" >> $target_job
                fi
    
                if islocal $targetB_pool; then
                    # Test access to targetA_pool
                    timeout 5s ssh root@${targetA_pool} "echo Hello from ${targetA_pool}"
                    if [ $? -ne 0 ]; then
                        error "Cannot connect to target host at ${targetA_pool}, ignore this if the target is down."
                    fi
                    # Create a job for this replication pair
                    debug "Creating replication job between this host $targetB_pool and host $targetA_pool for $targetB_folder"
                    job_status="${replication_job_dir}/status/${simple_jobname}#${targetA_pool}:$(foldertojob $targetA_folder)"
                    target_job="${replication_job_dir}/definitions/${simple_jobname}/${targetA_pool}"
                    echo "target=\"${targetA}\"" > $target_job
                    echo "target_pool=\"${targetA_pool}\"" >> $target_job
                    echo "target_folder=\"${targetA_folder}\"" >> $target_job
                fi
    
                if [ "$target_job" != '' ]; then
                    echo "dataset_name=\"$dataset_name\"" >> $target_job
                    echo "pool=\"${pool}\"" >> $target_job
                    echo "folder=\"${zfspath}\"" >> $target_job 
                    echo "job_status=\"${job_status}\"" >> $target_job
                    echo "source_tracker=\"${source_tracker}\"" >> $target_job
                    echo "dataset_targets=\"${dataset_targets}\"" >> $target_job
                    echo "replication_count=\"${replication_count}\"" >> $target_job
                    echo "mode=\"${mode}\"" >> $target_job
                    echo "options=\"${options}\"" >> $target_job
                    echo "frequency=\"${frequency}\"" >> $target_job
                    echo "failure_limit=\"${replication_failure_limit}\"" >> $target_job
                fi

                if [ "$replication_previous_snapshot" != "" ]; then
                    if [ ! -f "${job_status}" ]; then
                        # TODO: Verify snapshot exists on souce and target
                        echo "previous_snapshot=\"$replication_previous_snapshot\"" > $job_status
                    fi
                fi

            fi # if $mode

            # Initialize the job status file if it is not already

            if [ ! -f "${job_status}" ]; then
                touch "${job_status}"
                init_lock "${job_status}"
            fi

        done # for target_def
        endpoint_count=`cat "$dataset_targets" | wc -l`
        # Tag the zfs folder as replicated.
        zfs set ${zfs_replication_property}=on ${pool}/${zfspath}
        zfs set ${zfs_replication_dataset_property}=${dataset_name} ${pool}/${zfspath}
        zfs set ${zfs_replication_endpoints_property}=${endpoint_count} ${pool}/${zfspath}
        replication=`zfs get -H -o value $zfs_replication_property ${pool}/${zfspath}`
        replication_parent="${zfspath}"
    fi
   

    # Syncronize all replication targets


    if [[ "$replication" == "on" && "$replication_setup" != 'true' ]]; then

        
        # Get target(s) from parent definition
        
        if [ "$parent_replication" == 'on' ]; then
            parent_jobname="$(foldertojob $replication_parent)"
            echo "Replication parent jobname: $parent_jobname"
        else
            parent_jobname="${simple_jobname}"
            echo "Replication jobname: $parent_jobname"
        fi

        notice "Setting reset on replication for $replication_dataset_name"
        echo $replication_dataset_name >> ${TMP}/setup_filesystem_reset_replication

        clear_cache $pool
        
        replication_targets=`ls -1 ${replication_job_dir}/definitions/${parent_jobname}`
        for replication_target in $replication_targets; do
            source ${replication_job_dir}/definitions/${parent_jobname}/${replication_target}
            # Determine the pool and the zfs path of the target
            IFS=":"
            read -r t_pool t_path <<< "$target"
            unset IFS
                  
            # push a copy of this definition
            # Rsync is used to only update if the definition changes.  Its verbose output
            #   will list the definition being updated if it sync'd.  This will cause the
            #   trigger of a run to happen only if there were changes, short circuiting the 
            #   potential for an endless loop.
            if [ "$replication_parent" != "$t_path" ]; then
                echo "Replication source: $replication_parent"
                echo "zfspath:            $zfspath"
                sub_path=`echo "$zfspath" | ${SED} "s,${replication_parent},,g"`
                full_t_path="${t_path}${sub_path}"
            else
                full_t_path="$zfspath"
            fi
            target_simple_jobname="$(foldertojob $full_t_path)"

            sync_jobname="$simple_jobname"

            timeout 30s ssh root@${t_pool} touch /${t_pool}/zfs_tools/etc/pool-filesystems/.replication_setup

            # Recursively push defintions up to the root so all necessary defintions are replicated
            # Only push missing definitions

            sub_folder=0
            while [ $sub_folder -eq 0 ]; do
                debug "Pushing configuration for $sync_jobname to pool $t_pool folder $target_simple_jobname"
                    
                # Don't update existing parent folders only add missing ones
                if [ "$simple_jobname" != "${sync_jobname}" ]; then
                    ignore="--ignore-existing"
                else
                    ignore=""
                fi

                timeout 30s ${RSYNC} -cptgov --rsync-path=/opt/csw/bin/rsync --update ${ignore} -e ssh /${pool}/zfs_tools/etc/pool-filesystems/${sync_jobname} \
                    root@${t_pool}:/${t_pool}/zfs_tools/etc/pool-filesystems/${target_simple_jobname} > \
                    ${TMP}/setup_filesystem_replication_$$.txt
                if [ $? -ne 0 ]; then
                    error "Could not replicate definition ${sync_jobname} to ${t_pool}:${target_simple_jobname}" \
                        ${TMP}/setup_filesystem_replication_$$.txt
                    cat ${TMP}/setup_filesystem_replication_$$.txt
                else
                    cat ${TMP}/setup_filesystem_replication_$$.txt | \
                        grep -q -F "$simple_jobname"
                    if [ $? -eq 0 ]; then
                        echo "$t_pool" >> ${TMP}/setup_filesystem_replication_targets
                    fi
                fi

                rm ${TMP}/setup_filesystem_replication_$$.txt 2>/dev/null

                echo "${sync_jobname}" | ${GREP} -q "%"
                if [ $? -eq 0 ]; then
                    echo "target_simple_jobname" | ${GREP} -q "%"
                    sub_folder=$?
                else
                    sub_folder=1
                fi
                if [ $sub_folder -eq 0 ]; then
                    sync_jobname=`echo $sync_jobname|${SED} 's/\(.*\)%.*/\1/'`
                    target_simple_jobname=`echo $target_simple_jobname|${SED} 's/\(.*\)%.*/\1/'`
                fi
            done
        done
    fi

    if [ "$replication" == "on" ]; then
        # Trigger any child folders to also be re-examined and synced.
        # This is most important when replication is added to an existing zfs folder to assure all child folders
        # are synced to all targets.
        current_folder_def_name="/${pool}/zfs_tools/etc/pool-filesystems/${simple_jobname}"
        strip_len=$(( ${#current_folder_def_name} + 2 ))
        children=`ls -1 ${current_folder_def_name}%* 2>/dev/null | ${CUT} -c ${strip_len}-`
        for child in $children; do
            echo "${simple_jobname}%${child}" >> "${TMP}/setup_filesystem_replication_children"
        done
        if [[ "$DEBUG" == 'true' &&  -f ${TMP}/setup_filesystem_replication_children ]]; then
            echo "Replication children definitions:"
            cat ${TMP}/setup_filesystem_replication_children | ${SORT} -u 
        fi

    fi

    ##    
    # Define vIP
    ##

    # Remove any definitions in the zfs parameters and reload them
    # TODO: Only remove the ones that change

    zfs_vips=
    zfs_vip=`zfs get -H -o value -s local $zfs_vip_property ${pool}/${zfspath}`
    if [ "$zfs_vip" != "" ]; then
        zfs inherit ${zfs_vip_property} ${pool}/${zfspath}
        x=1
        while [ $x -le $zfs_vip ]; do
            zfs inherit ${zfs_vip_property}:${x} ${pool}/${zfspath}
            x=$(( x + 1 ))
        done
    fi

    mkdir -p /${pool}/zfs_tools/var/vip

    if [ $vip -ne 0 ]; then
        if [ "$replication_targets" == "" ]; then
            warning "vIP assigned without replication definition.  This vIP will be attached to the pool activated."
        fi
        rm -f ${TMP}/previous_vip_$$ 2> /dev/null
        if [ -f "/${pool}/zfs_tools/var/vip/${simple_jobname}" ]; then
            mv "/${pool}/zfs_tools/var/vip/${simple_jobname}" ${TMP}/previous_vip_$$
        fi

        x=1
        while [ $x -le $vip ]; do
            # Break down the vIP definition
            IFS='|'
            read -r vIP routes ipifs <<< "${vip[$x]}"
            unset IFS
            # TODO: validate vIP, routes and interfaces 




            debug "Adding vIP $vIP to folder definition $simple_jobname"
            echo "${pool}|${dataset_name}|${vip[$x]}" >> /${pool}/zfs_tools/var/vip/${simple_jobname}
            zfs set ${zfs_vip_property}:${x}="${vip[$x]}" ${pool}/${zfspath}
            x=$(( x + 1 ))
        done

        zfs set ${zfs_vip_property}="$(( x - 1 ))" ${pool}/${zfspath}

        # TODO: Post process changes from ${TMP}/previous_vip_$$.  
        #       Remove any vIP no longer defined, update changes routes, etc.
        #       In short, any vIP that changes, remove it and recreate it.

    fi

    ##    
    # Setup CIFS
    ##

    mkdir -p /${pool}/zfs_tools/{etc,var}/samba
    
    if [ "$cifs" == 'true' ]; then
        debug "cifs: true"
        clear_cache $pool
        if [ "$dataset_name" != '' ]; then
            server_name="${zfs_samba_server_prefix}${dataset_name}${zfs_samba_server_suffix}"
            mkdir -p /${pool}/zfs_tools/{etc,var}/samba/${dataset_name}
            zfs set ${zfs_cifs_property}=${server_name} ${pool}/${zfspath}
            case $cifs_template in
                *.conf|*.conf.template)
                    if [ -f /$pool/zfs_tools/etc/samba/${dataset_name}/$cifs_template ]; then
                        debug "Setting smb_${dataset_name}.conf via /$pool/zfs_tools/etc/samba/${dataset_name}/$cifs_template"
                        zfs set ${zfs_cifs_property}:template="dataset:$cifs_template" ${pool}/${zfspath}
                    else if [ -f /$pool/zfs_tools/etc/samba/$cifs_template ]; then
                        debug "Setting smb_${dataset_name}.conf via /$pool/zfs_tools/etc/samba/$cifs_template"
                        zfs set ${zfs_cifs_property}:template="pool:$cifs_template" ${pool}/${zfspath}
                    else if [ -f /etc/ozmt/samba/$cifs_template ]; then
                        debug "Setting smb_${dataset_name}.conf via /etc/ozmt/samba/$cifs_template"
                        zfs set ${zfs_cifs_property}:template="system:$cifs_template" ${pool}/${zfspath}
                    else
                        error "Cannot define cifs template.  Configuration file $cifs_template not found in /$pool/zfs_tools/etc/samba/$cifs_parent_dataset/$cifs_template or /$pool/zfs_tools/etc/samba/$cifs_template or /etc/ozmt/samba/$cifs_template"
                    fi;fi;fi
                    ;;
                default)
                    if [ ! -f $zfs_cifs_default_template ]; then
                        error "Cannot define cifs template.  Configuration file missing: $zfs_cifs_default_template"
                    else
                        debug "Setting template via $zfs_cifs_default_template"
                        zfs set ${zfs_cifs_property}:template="$default" ${pool}/${zfspath}
                    fi
                    ;;
                *)
                    error "CIFS template must be of the form {filename}.conf, {filename}.conf.template, or 'default'"
                    ;;
            esac
        else
            error "CIFS enabled without specifying dataset name"
        fi
    else
        zfs inherit ${zfs_cifs_property} ${pool}/${zfspath}
        zfs inherit ${zfs_cifs_property}:template ${pool}/${zfspath}
    fi

    # Setup CIFS share

    if [ "$cifs_share" != "" ]; then
        clear_cache $pool
        cifs_parent_dataset=`zfs get -H -o value ${zfs_cifs_property} ${pool}/${zfspath}`
        if [ "$cifs_parent_dataset" == '-' ]; then
            error "CIFS must be enabled at the dataset level before defining shares"
        else
            case $cifs_share in
                *.conf|*.conf.template)
                    if [ -f /$pool/zfs_tools/etc/samba/$cifs_parent_dataset/$cifs_share ]; then
                        debug "Setting share via /$pool/zfs_tools/etc/samba/$cifs_parent_dataset/$cifs_share"
                        zfs set ${zfs_cifs_property}:share="dataset:$cifs_share" ${pool}/${zfspath}
                    else if [ -f /$pool/zfs_tools/etc/samba/$cifs_share ]; then
                        debug "Setting share via /$pool/zfs_tools/etc/samba/$cifs_share"
                        zfs set ${zfs_cifs_property}:share="pool:$cifs_share" ${pool}/${zfspath}
                    else if [ -f /etc/ozmt/samba/$cifs_share ]; then
                        debug "Setting share via /etc/ozmt/samba/$cifs_share"
                        zfs set ${zfs_cifs_property}:share="system:$cifs_share" ${pool}/${zfspath}
                    else
                        error "Cannot define cifs share.  Configuration file $cifs_share not found in /$pool/zfs_tools/etc/samba/$cifs_parent_dataset/$cifs_share or /$pool/zfs_tools/etc/samba/$cifs_share or /etc/ozmt/samba/$cifs_share"
                    fi;fi;fi
                    ;;
                default)
                    if [ ! -f $zfs_cifs_default_share_template ]; then
                        error "Cannot define cifs share.  Configuration file missing: $zfs_cifs_default_share_template"
                    else
                        debug "Setting share via $zfs_cifs_default_share_template"
                        zfs set ${zfs_cifs_property}:share="$default" ${pool}/${zfspath}
                    fi
                    ;;
                *)
                    error "CIFS share template must be of the form {filename}.conf, {filename}.conf.template, or 'default'"
                    ;;
            esac

        fi
        if [ "$smb_valid_users" != "" ]; then
            debug "Setting valid CIFS users to: $smb_valid_users"
            zfs set ${zfs_cifs_property}:users="$smb_valid_users" ${pool}/${zfspath}
        fi

    else
        debug "No cifs share defined for this folder"
        zfs inherit ${zfs_cifs_property}:share ${pool}/${zfspath}
    fi

    
}

