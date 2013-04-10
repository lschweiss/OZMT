#! /bin/bash 

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012  Chip Schweiss

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

now=`date +%F_%H:%M:%S%z`

DEBUG="true"

die () {

    error "restore_from_glacier: $1"
    umount -f /${TMP}/gpgtemp
    ramdiskadm -d gpgtemp0
    exit 1

}

abort () {
    debug "execution aborted"
    umount -f /${TMP}/gpgtemp
    ramdiskadm -d gpgtemp0
    exit 1
}

pause () {
    echo -n "Press enter to continue.."
    read junk
}

trap abort INT

backupjobs=`ls -1 $TOOLS_ROOT/backup/jobs/glacier/active/`
jobstatusdir="$TOOLS_ROOT/backup/jobs/glacier/status"

mkdir -p $jobstatusdir/restore

if [ "x$glacier_logfile" != "x" ]; then
    logfile="$glacier_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$glacier_report" != "x" ]; then
    report_name="$glacier_report"
else
    report_name="$default_report_name"
fi

if [ ! -d $TMP ]; then
    die "\"$TMP\" is not a directory.  TMP must be defined to an existing directory in zfs-config."
fi


case $# in
    '0') 
        die "Must specify file system to restore"
        ;;
    '1') 
        restorefs="$1"
        destinationfs="$restorefs"
        lastcycle="latest"
        ;;
    '2')
        restorefs="$1"
        destinationfs="$2"
        lastcycle="latest"
        ;;
    '3')
        restorefs="$1"
        destinationfs="$2"
        lastcycle="$3"
        ;;
esac

destinationfixup=`echo $destinationfs|sed s,/,%,g`

# locate job definiton
for job in $backupjobs; do

    source $TOOLS_ROOT/backup/jobs/glacier/active/${job}

    if [ "$source_folder" == "$restorefs" ]; then
        vault="$glacier_vault"
        jobname="$job_name"
    fi

done


# Check that we have a jobname
if [ "x$jobname" == "x" ]; then
    die "No job defintion found in $TOOLS_ROOT/backup/jobs/glacier/active/ for $restorefs   Set vault and job environment variables if definition is not available."
fi

jobname_fixup=`echo $jobname|sed s,%,.,g`

# TODO: Determine the rotation number




rotation=100





########################################################################################
# Check for a current inventory
########################################################################################

inventory_file="$jobstatusdir/inventory/${vault}-${rotation}-${jobname_fixup}"
full_vault_name="${vault}-${rotation}-${jobname_fixup}"

if [ ! -f $inventory_file ]; then
    die "No inventory for $restorefs.  Please run glacier-inventory.sh to retrieve latest inventory."
fi

# Determine last cycle we will attempt to restore
if [ "$lastcycle" == "latest" ]; then
    # Grab the last cycle in the inventory
    lastcycle=`cat $inventory_file | tail -1 | awk -F '","' '{print $2}' | tail --bytes=5`
    # Get rid of the newline
    lastcycle=$(( $lastcycle ))
fi

if [ "${#lastcycle}" -gt 4 ]; then
    # We assume this is a date format and will attempt to match an inventory line.
    # If more than one line matches the last match will be used
    archive_record=`cat $inventory_file | grep "$lastcycle" | tail -1`
    if [ "x$archive_record" == "x" ]; then
        die "Date ($lastcycle) specified for last cycle, but no maching date found in $inventory_file"
    fi
    lastcycle=`echo $archive_record | awk -F '","' '{print $2}' | tail --bytes=5`
    # Get rid of the newline
    lastcycle=$(( $lastcycle ))
fi

if [ "${#lastcycle}" -ne 4 ]; then
    die "Could not determing the last cycle to restore"
fi


# Determine if we are resuming or continuing a restore
restore_record="${jobstatusdir}/restore/${vault}%${jobname}_to_${destinationfixup}"
# Get or initialize the rotation number
if [ -f ${restore_record} ]; then
    # We are continuing
    source ${restore_record}
    debug "Coninuing previous restore from last cycle ${last_complete_cycle}"
else
    # Initialize
    last_complete_cycle=$(( glacier_start_sequence - 1 ))
    echo "last_complete_cycle=\"${last_complete_cycle}\"" > $restore_record
    debug "Starting restore from initial sequence: $glacier_start_sequence"
fi

###################################################################################
# Prompt for GPG private key and password
# Store it on a temporary ramdisk
###################################################################################

ramdiskadm -a gpgtemp0 10m || die "could not create ramdisk for gpg keys"
echo "y" |newfs -b 4096 /dev/ramdisk/gpgtemp0
mkdir -p /${TMP}/gpgtemp
mount /dev/ramdisk/gpgtemp0 /${TMP}/gpgtemp || die "could not mount /${TMP}/gpgtemp to ramdisk"

# TODO: Get private key and password

echo "Remove this text and save GPG private key to this file." >/${TMP}/gpgtemp/private.gpg

vim /${TMP}/gpgtemp/private.gpg

echo
echo -n "Enter GPG private key password: "

read -s gpg_password

touch /${TMP}/gpgtemp/keyring.gpg
gpg --no-default-keyring --keyring /${TMP}/gpgtemp/keyring.gpg --import /${TMP}/gpgtemp/private.gpg

touch /${TMP}/gpgtemp/passphrase
chmod 600 /${TMP}/gpgtemp/passphrase
echo $gpg_password > /${TMP}/gpgtemp/passphrase



###################################################################################
# Request archives from Glacier
###################################################################################

debug "Restoring $restorefs to $destinationfs from $(( $last_complete_cycle + 1 )) to $lastcycle"

working_cycle=$(( $last_complete_cycle + 1 ))

job_prefix="${vault}%${jobname}-"

while [ "$working_cycle" -le "$lastcycle" ]; do

    thisjob="${job_prefix}${working_cycle}"

    # Locate archiveID
    archiveID=`cat $inventory_file|grep $thisjob|awk -F '","' '{print $1}'|awk -F '"' '{print $2}'`

    cmd_result=`$glacier_cmd --output csv getarchive $full_vault_name -- $archiveID`

    echo $cmd_result|grep -q "RequestId" ; result=$?

    if [ "$result" -eq "0" ]; then
        debug "Submitted request for $thisjob"
    else
        request_status=`echo cmd_result|grep StatusCode|awk -F '","' '{print $2}'|sed s'/..$//'` 
        debug "Job status for ${thisjob}: $request_status"
    fi    

    working_cycle=$(( working_cycle + 1 ))

done

###################################################################################
# Create destination file system if it does not already exists
###################################################################################

zfs list $destinationfs &> /dev/null
result=$?

if [ "$result" -ne "0" ]; then
    debug "Destination file system does not exist.  Creating it."
    zfs create $destinationfs || die "could not create destination file system $destinationfs"
else
    debug "Destination file system $destinationfs already exists. "
fi


###################################################################################
# Download and restore one cycle at a time
###################################################################################

debug "Starting download phase."

working_cycle=$(( $last_complete_cycle + 1 ))

while [ "$working_cycle" -le "$lastcycle" ]; do

    request_status=""

    while [ "$request_status" != "Succeeded" ]; do

        thisjob="${job_prefix}${working_cycle}"

        # Locate archiveID
        archiveID=`cat $inventory_file|grep $thisjob|awk -F '","' '{print $1}'|awk -F '"' '{print $2}'`
        cmd_result=`$glacier_cmd --output csv getarchive $full_vault_name -- $archiveID`

        debug "Checking status."
        debug "  This job: ${thisjob}"
        debug "  vault name: ${full_vault_name}"
        debug "  archiveID: ${archiveID}"

        $glacier_cmd --output csv getarchive $full_vault_name -- $archiveID > /${TMP}/glacier_cmd_getarchive_$$ || \
            die "glacier-cmd failed to execute getarchive $full_vault_name $archiveID"

        cat /${TMP}/glacier_cmd_getarchive_$$|grep -q "RequestId" ; result=$?

        if [ "$result" -eq "0" ]; then
            debug "Submitted request for $thisjob"
        else
            request_status=`cat /${TMP}/glacier_cmd_getarchive_$$|grep StatusCode|awk -F '","' '{print $2}'|sed s'/..$//'`
            debug "Job status for ${thisjob}: $request_status"
        fi
    
        if [ "$request_status" == "InProgress" ]; then
            debug "Sleep 30m until job is ready for download"
            sleep 30m
        fi

    done

    ##############################################
    # Job is ready for download
    ##############################################


    debug "Job, ${thisjob}, cycle ${working_cycle}, is ready for download"
    restore_status=1
    restore_count=0
 
    while [ "$restore_status" -ne 0 ]  && [ "$restore_count" -lt 3 ]; do  

        download_status=1
        try_count=0
        
        while [ "$download_status" -ne 0 ]  && [ "$try_count" -lt 3 ]; do
    
            $glacier_cmd download --outfile /${TMP}/glacier-cmd-download_$$_${working_cycle}_.gz.gpg \
                $full_vault_name -- $archiveID 
            download_status=$?
            
            # Check the return status
            if [ "$download_status" -ne 0 ]; then
                notice "Download attempt failed.  Will try again."
                try_count=$(( try_count + 1 ))
            fi

        done
    
        if [ "$download_status" -ne 0 ]; then
            die "Failed to download $full_vault_name $archiveID"
        fi
    
        stat /${TMP}/glacier-cmd-download_$$_${working_cycle}_.gz.gpg
    
        gpg --batch --passphrase-file /${TMP}/gpgtemp/passphrase \
            --secret-keyring /${TMP}/gpgtemp/keyring.gpg \
            --decrypt /${TMP}/glacier-cmd-download_$$_${working_cycle}_.gz.gpg | \
        gunzip | tee /${TMP}/zfstest_${working_cycle} | \
        zfs receive -F -v $destinationfs || die "Failed to receive archive #${working_cycle} for $restorefs" 
        restore_status=$?

        # Check the exit status
        if [ "$restore_status" -ne 0 ]; then
            notice "Restore attempt failed.  Will try downloading and restoring again."
            restore_count=$(( restore_count + 1 ))
            rm /${TMP}/glacier-cmd-download_$$_${working_cycle}_.gz.gpg    
        fi
        

    done

    if [ "$restore_status" -ne 0 ]; then
        die "Failed to decrypt, uncompress and zfs receive /${TMP}/glacier-cmd-download_$$_gpg.gz"
    fi

    echo "last_complete_cycle=\"${working_cycle}\"" > $restore_record
    working_cycle=$(( working_cycle + 1 ))

done
