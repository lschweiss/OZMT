#! /bin/bash -x

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
    umount -f /tmp/gpgtemp
    ramdiskadm -d gpgtemp0
    exit 1

}

abort () {
    debug "execution aborted"
    umount -f /tmp/gpgtemp
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

pause

# locate job definiton
for job in $backupjobs; do

    source $TOOLS_ROOT/backup/jobs/glacier/active/${job}

    if [ "$source_folder" == "$restorefs" ]; then
        vault="$glacier_vault"
        jobname="$job_name"
    fi

done

pause

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

pause

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

pause
###################################################################################
# Prompt for GPG private key and password
# Store it on a temporary ramdisk
###################################################################################

ramdiskadm -a gpgtemp0 10m || die "could not create ramdisk for gpg keys"
echo "y" |newfs -b 4096 /dev/ramdisk/gpgtemp0
mkdir -p /tmp/gpgtemp
mount /dev/ramdisk/gpgtemp0 /tmp/gpgtemp || die "could not mount /tmp/gpgtemp to ramdisk"

# TODO: Get private key and password

echo "Remove this text and save GPG private key to this file." >/tmp/gpgtemp/private.gpg

vim /tmp/gpgtemp/private.gpg

echo
echo -n "Enter GPG private key password: "

read -s gpg_password

touch /tmp/gpgtemp/keyring.gpg
gpg --no-default-keyring --keyring /tmp/gpgtemp/keyring.gpg --import /tmp/gpgtemp/private.gpg

touch /tmp/gpgtemp/passphrase
chmod 600 /tmp/gpgtemp/passphrase
echo $gpg_password > /tmp/gpgtemp/passphrase



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

    pause

done

###################################################################################
# Create destination file system if it does not already exists
###################################################################################

zfs list $destinationfs &> /dev/null
result=$?

if [ "$result" -ne "0" ]; then
    zfs create $destinationfs || die "could not create destination file system $destinationfs"
else
    debug "Destination file system $destinationfs already exists.  Will overwrite"
fi

pause

###################################################################################
# Download and restore one cycle at a time
###################################################################################

working_cycle=$(( $last_complete_cycle + 1 ))

while [ "$working_cycle" -le "$lastcycle" ]; do

    request_status=""

    while [ "$request_status" != "Succeeded" ]; do

        $glacier_cmd --output csv getarchive $full_vault_name -- $archiveID > /tmp/glacier_cmd_getarchive_$$ || \
            die "glacier-cmd failed to execute getarchive $full_vault_name $archiveID"

        cat /tmp/glacier_cmd_getarchive_$$|grep -q "RequestId" ; result=$?

        if [ "$result" -eq "0" ]; then
            debug "Submitted request for $thisjob"
        else
            request_status=`cat /tmp/glacier_cmd_getarchive_$$|grep StatusCode|awk -F '","' '{print $2}'|sed s'/..$//'`
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

    $glacier_cmd download --outfile /tmp/glacier-cmd-download_$$_.gz.gpg $full_vault_name -- $archiveID || \
        die "Failed to download $full_vault_name $archiveID"
 
    
    gpg --batch --passphrase-file /tmp/gpgtemp/passphrase \
        --secret-keyring /tmp/gpgtemp/keyring.gpg \
        --decrypt /tmp/glacier-cmd-download_$$_.gz.gpg | \
    gunzip | \
    zfs receive -F -vu $destinationfs || die "Failed to receive archive #${working_cycle} for $restorefs" || \
        die "Failed to decrypt, uncompress and zfs receive /tmp/glacier-cmd-download_$$_gpg.gz"


    working_cycle=$(( working_cycle + 1 ))

    pause
done
