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

die () {

    error "verify-archives: $1"
    exit 1

}


recollect () {

    local search_vault="$1"
    local search_job="$2"
    local archiving_file="$3"
    local jobstats=

    $glacier_cmd search ${search_vault} > ${TMP}/glacier-job-$$.search
    jobstats=`cat ${TMP}/glacier-job-$$.search | ${GREP} -F "${search_job}"`


    echo -n "archive_id=" >> $archiving_file
    archive_id=`echo -n $jobstats|${AWK} -F "|" '{print $2}'|tr -d ' '`
    echo "\"$archive_id\"" >> $archiving_file

    echo -n "archive_hash=" >> $archiving_file
    archive_hash=`echo -n $jobstats|${AWK} -F "|" '{print $3}'|tr -d ' '`
    echo "\"$archive_hash\"" >> $archiving_file

    echo -n "archive_size=" >> $archiving_file
    archive_size=`echo -n $jobstats|${AWK} -F "|" '{print $8}'|tr -d ' '`
    echo "\"$archive_size\"" >> $archiving_file

}

pools="$(pools)"

for pool in $pools; do

    jobdefdir="/${pool}/zfs_tools/etc/backup/jobs/glacier"    
    backupjobs=`ls -1 ${jobdefdir}/`
    jobstatusdir="/${pool}/zfs_tools/var/backup/jobs/glacier/status"
    
   for job in $backupjobs; do
    
        source ${jobdefdir}/${job}
    
        # Get the rotation number
    
        if [ ! -f "${jobstatusdir}/sequence/${job}_rotation" ]; then
            # No rotation number(s) exist for the job.  Assume starting rotation
            rotations="$glacier_start_rotation"
        else
            rotations=`cat ${jobstatusdir}/sequence/${job}_rotation`
        fi
    
        jobfixup=`echo $job_name|${SED} s,%,.,g`
    
        for rotation in $rotations; do
    
            # Find sequence number
            if [ ! -f "${jobstatusdir}/sequence/${job}_${rotation}" ]; then
                debug "No sequence defined for ${job}_${rotation}.  Skipping."
            else
                lastjob=`cat ${jobstatusdir}/sequence/${job}_${rotation}`

                if [ "$lastjob" == 'delete' ]; then
                    # Rotation is undergoing deletion.   Try for 14 days to clean it all up
                    lastjob=$(( $glacier_start_sequence + $glacier_rotation_days + 14 ))
                fi
                
                # Step through sequences confirming the archive job is in the latest inventory.
                # Delete any sequential snapshot that is no longer needed.
            
                jobnum="$glacier_start_sequence"
        
                while [ "$jobnum" -lt "$lastjob" ]; do
    
                    #jobfilename="${glacier_vault}%${job_name}_${rotation}_${jobnum}"
                    jobfilename="${job}_${rotation}_${jobnum}"
    
                    # Collect the definition
                
                    source ${jobstatusdir}/definition/${jobfilename}
    
                    if [ ! -f ${jobstatusdir}/complete/${jobfilename} ]; then
    
                        # collect the job record
                        if [ -f ${jobstatusdir}/archiving/${jobfilename} ]; then
                            source ${jobstatusdir}/archiving/${jobfilename}
                        else
                            if [ ! -f ${jobstatusdir}/complete/${jobfilename} ]; then
                                warning "Job $jobfilename not in archiving or complete state.  Cannot continue verifying."
                                break
                            fi
                        fi
        
                        # Collect the inventory record
                        if [ -f ${jobstatusdir}/inventory/${vault} ]; then
                            archive_description="${jobroot}-${jobnum}"
                            inventory_record=`cat ${jobstatusdir}/inventory/${vault}|${GREP} "$archive_description"`
                            if [ "x${inventory_record}" == "x" ]; then
                                notice "Job $jobfilename not yet inventoried."
                                break
                            fi
                            inventory_hash=`echo $inventory_record|${AWK} -F '","' '{print $4}'`
                            inventory_id=`echo $inventory_record|${AWK} -F '","' '{print $1}'|${SED} -r 's/^.{1}//'`
                            inventory_size=`echo $inventory_record|${AWK} -F '","' '{print $5}'|${AWK} -F '"' '{print $1}'`
                        else
                            notice "Vault $vault not yet inventoried."
                            break
                        fi
    
                        errors=0
                        checks=1
    
                        while [ "$checks" -le "2" ]; do 
    
                            if [ "$checks" -ne "2" ]; then 
                                report_type="notice"
                            else
                                report_type="warning"
                            fi
        
                            # Check hash, id and size
    
                            if [ "${archive_hash}" != "${inventory_hash}" ]; then
                                $report_type "${jobfilename}: Archive hash (${achive_hash}) does not match inventory hash (${inventory_hash})."
                                errors=$(( errors + 1 ))
                            fi
                            
                            if [ "${archive_id}" != "${inventory_id}" ]; then
                                $report_type "${jobfilename}: Archive id (${achive_id}) does not match inventory id (${inventory_id})."
                                errors=$(( errors + 1 ))
                            fi
                
                            if [ "${archive_size}" != "${inventory_size}" ]; then
                                $report_type "${jobfilename}: Archive size (${archive_size}) does not match inventory size (${inventory_size})."
                                errors=$(( errors + 1 ))
                            fi
    
                            if [ "$errors" -ne "0" ] && [ "$checks" -ne "2" ]; then
                                    notice "Attepting to recollect data for ${jobfilename}"
                                    recollect "${vault}" "${archive_description}" \
                                        "${jobstatusdir}/archiving/${jobfilename}"
                                    errors=0
                            fi
    
    
                            checks=$(( checks + 1 ))
    
    
                        done # while checks
    
                        if [ "$errors" -ne "0" ]; then
                            error "Unresolvable archive error in ${achive_id}"
                            break
                            
                        fi
                        
    
                        notice "Job $jobfilename confirmed archived in Glacier."
                        debug "Archive hash:    ${archive_hash}"
                        debug "Inventory hash:  ${inventory_hash}"
                        
                        if [ "x${lastjobsnapname}" != "x" ]; then
                            notice "Deleting snapshot ${lastjobsnapname}"
                            zfs destroy -r $lastjobsnapname || warning "Could not destroy $lastjobsnapname"
                        fi
    
                        notice "Moving $jobfilename to complete status"
                        mv ${jobstatusdir}/archiving/${jobfilename} ${jobstatusdir}/complete/${jobfilename}
    
                        # Check for previous rotation and destroy it
                        prev_rotation=$(( rotation - 1 ))
                        
                        if [ -f ${jobstatusdir}/sequence/${job}_${prev_rotation} ]; then
                            ./clean-glacier-rotation.sh ${pool} ${job} ${prev_rotation}
                        fi  
    
    
                    fi # not complete
        
                    jobnum=$(( $jobnum + 1 ))
    
                done # while jobnum
    
            fi # sequence number
        
        done # for rotation
    
    done # for job
    
done # for pool

