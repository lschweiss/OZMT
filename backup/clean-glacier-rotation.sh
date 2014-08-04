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

die () {

    warning "clean-glacier-rotation: $1"
    exit 1

}

backupjobs=`ls -1 $TOOLS_ROOT/backup/jobs/glacier/active/`
jobstatusdir="$TOOLS_ROOT/backup/jobs/glacier/status"

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

pool="$1"
job="$2"
rotation="$3"

notice "clean-glacier-rotation: Removing glacier rotation for job $job, rotation $rotation on pool $pool"

# Work backwards though rotation we are destroying

jobstatusdir="/${pool}/zfs_tools/var/backup/jobs/glacier/status"

# Set the sequence to "delete" so no more jobs get created

debug "clean-glacier-rotation: Setting status to delete for glacier rotation for job $job, rotation $rotation on pool $pool"
echo "delete" > ${jobstatusdir}/sequence/${job}_${rotation}

# Make sure there are no running jobs

ls ${jobstatusdir}/running/${job}_${rotation}_???? &> /dev/null 
if [ $? -eq 0 ]; then
    notice "clean-glacier-rotation: Aborting removing jobs from $job, rotation $rotation on pool $pool, backup still running"
    exit 0
fi

# Cycle through definitions, making sure snapshots have been deleted

definitions=`ls -1 ${jobstatusdir}/definition/${job}_${rotation}_????`

snapshotlist="${TMP}/clean-glacier-rotation_snapshots_$$"

zfs list -t snapshot -H -o name > $snapshotlist

for definition in $definitions; do

    source $definition
    
    cat $snapshotlist | ${GREP} -q "$jobsnapname"
    if [ $? -eq 0 ]; then
        notice "Destroying snapshot $jobsnapname its rotation is deleting"
        zfs destroy -r $jobsnapname &> ${TMP}/clean-glacier-rotation_zfsdestroy_$$ || \
            error "clean-glacier-rotation: Could not delete snapshot $jobsnapname" \
                ${TMP}/clean-glacier-rotation_zfsdestroy_$$
    fi

done


# Remove vault archives

source /${pool}/zfs_tools/etc/backup/jobs/glacier/${job}

folder_fixup=`echo $source_folder | ${SED} 's,/,.,g'`

if [ "${job:0:5}" == "FILES" ]; then
    vaultname="${glacier_vault}-${rotation}-FILES.${folder_fixup}"
else
    vaultname="${glacier_vault}-${rotation}-${folder_fixup}"
fi

inventoryfile="${jobstatusdir}/inventory/${vaultname}"

cat ${inventoryfile} |
while read inventory; do

    x=`echo $inventory | ${AWK} -F '","' '{print $1}'`
    archiveid="${x:1}"

    # Skip the header line
    if [ "$archiveid" != "ArchiveId" ]; then
        debug "Removing $archiveid from vault $vaultname"
        $glacier_cmd rmarchive $vaultname -- $archiveid &> ${TMP}/clean-glacier-rotation_rmarchive_$$ || \
            warning "clean-glacier-rotation: Could not remove archive $archiveid from vault $vaultname" \
                ${TMP}/clean-glacier-rotation_rmarchive_$$
    fi

done

# Destroy Glacier vault

# This will fail until all archiving is complete and inventoried.

$glacier_cmd rmvault $vaultname &> ${TMP}/clean-glacier-rotation_rmvault_$$

if [ $? -ne 0 ]; then
    warning "clean-glacier-rotation: Could not remove the vault $vaultname" \
        ${TMP}/clean-glacier-rotation_rmvault_$$
    exit 0
else
    notice "clean-glacier-rotation: Succesfully removed vault $vaultname"
fi


# If we get here the vault has been removed and we can clean everything else up related to this rotation


# Remove inventory file

rm -f $inventoryfile

# Remove cycle jobs

statustypes="archiving complete definition failed pending"

for type in $statustypes; do
    rm -f ${jobstatusdir}/${type}/${job}_${rotation}_???? 2>/dev/null
done

# Remove the rotation from sequence status

cat ${jobstatusdir}/status/${job}_rotation | ${GREP} -v ${rotation} > ${TMP}/clean-glacier-rotation_rmrotation_$$
mv ${TMP}/clean-glacier-rotation_rmrotation_$$ ${jobstatusdir}/status/${job}_rotation

rm -f ${jobstatusdir}/status/${job}_${rotation}






