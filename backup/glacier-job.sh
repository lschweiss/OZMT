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

pool="$1"
job="$2"

jobstatusdir="/${pool}/zfs_tools/var/backup/jobs/glacier/status"
jobdefdir="/${pool}/zfs_tools/etc/backup/jobs/glacier"

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

    error "glacier_job: $1" 
    exit 1

}

if [ ! -f "${jobstatusdir}/definition/${job}" ]; then
    
    die "Job \"$job\" not defined. Nothing to do."
   
fi

# Collect job information
source ${jobstatusdir}/definition/${job}

if [ "${job_name:0:5}" == "FILES" ]; then
    filesjob="true"
    backuptype="tar"
else
    filesjob="false"
    backuptype="zfs send"
fi


# Build backup_cmd

if [ "$filesjob" == "true" ]; then
    # Backup only the current files via tar_gz
    backup_cmd="tar cz --sparse --directory=\"${jobsnapname}\""
else
    # Use zfs send
    if [ "$thisjob" -eq "$glacier_start_sequence" ]; then
        # This is the first job 
        debug "glacier job: starting push to glacier for ${jobsnapname}"
        backup_cmd="zfs send -R ${jobsnapname}"
    else
        # This is an incremental job
        debug "glacier job: starting incremental push to glacier for ${lastjobsnapname} to ${jobsnapname}"
        backup_cmd="zfs send -R -I ${lastjobsnapname} ${jobsnapname}"
    fi
fi

mv ${jobstatusdir}/pending/${job} ${jobstatusdir}/running/${job}

# Start the tar/zfs send

$backup_cmd  2> ${TMP}/glacier-job-backup-error_$$ | \
#    mbuffer -q -s 128k -m 16M 2> ${TMP}/glacier-job-mbuffer-error_$$ | \
    gzip 2> ${TMP}/glacier-job-gzip-error_$$ | \
#    mbuffer -q -s 128k -m 16M | \
    gpg -r "$gpg_user" --encrypt 2> ${TMP}/glacier-job-gpg-error_$$ | \
#    mbuffer -q -s 128k -m 128M | \
    $glacier_cmd upload ${vault} \
        --stdin \
        --description "${jobroot}-${thisjob}" \
        --name "${jobroot}-${thisjob}" \
        --partsize 128 &> ${TMP}/glacier-cmd-output_$$

result=$?

debug "glacier_job: ${job} ${backuptype} output: " ${TMP}/glacier-job-backup-error_$$
#debug "glacier_job: ${job} mbuffer output: " ${TMP}/glacier-job-mbuffer-error_$$
debug "glacier_job: ${job} gzip output: " ${TMP}/glacier-job-gzip-error_$$
debug "glacier_job: ${job} gpg: " ${TMP}/glacier-job-gpg-error_$$
debug "glacier_job: ${job} glacier-cmd output:" ${TMP}/glacier-cmd-output_$$


# Handle job failures or success

if [ "$result" -ne "0" ]; then

    # Job failed

    # Collect the archive ID

    # Move the job to failed status
    mv ${jobstatusdir}/running/${job} ${jobstatusdir}/failed/${job}

    # submit results
    warning "glacier_job: job ${job} failed will retry"
    # Report output
    notice "glacier_job: ${job} ${backuptype} output: " ${TMP}/glacier-job-backup-error_$$
    #notice "glacier_job: ${job} mbuffer output: " ${TMP}/glacier-job-mbuffer-error_$$
    notice "glacier_job: ${job} gzip output: " ${TMP}/glacier-job-gzip-error_$$
    notice "glacier_job: ${job} gpg: " ${TMP}/glacier-job-gpg-error_$$
    notice "glacier_job: ${job} glacier-cmd output:" ${TMP}/glacier-cmd-output_$$

else

    # Move the job to archiving status
    mv ${jobstatusdir}/running/${job} ${jobstatusdir}/archiving/${job}

    # Collect information about the job

    $glacier_cmd search ${vault} > ${TMP}/glacier-job-$$.search
    jobstats=`cat ${TMP}/glacier-job-$$.search | ${GREP} -F "${jobroot}-${thisjob}"`

    echo "archive_name=\"${jobroot}-${thisjob}\"" >> ${jobstatusdir}/archiving/${job}

    echo -n "archive_id=" >> ${jobstatusdir}/archiving/${job} 
    archive_id=`echo -n $jobstats|${AWK} -F "|" '{print $2}'|tr -d ' '`
    echo "\"$archive_id\"" >> ${jobstatusdir}/archiving/${job}

    echo -n "archive_hash=" >> ${jobstatusdir}/archiving/${job}
    archive_hash=`echo -n $jobstats|${AWK} -F "|" '{print $3}'|tr -d ' '`
    echo "\"$archive_hash\"" >> ${jobstatusdir}/archiving/${job}

    echo -n "archive_size=" >> ${jobstatusdir}/archiving/${job}
    archive_size=`echo -n $jobstats|${AWK} -F "|" '{print $8}'|tr -d ' '`
    echo "\"$archive_size\"" >> ${jobstatusdir}/archiving/${job}

    rm ${TMP}/glacier-job-$$.search

    # submit results
    notice "glacier_job: successully submitted archive for job ${job}"

fi

if [ "$DEBUG" != "true" ]; then
    rm ${TMP}/glacier-job-backup-error_$$
    #rm ${TMP}/glacier-job-mbuffer-error_$$
    rm ${TMP}/glacier-job-gzip-error_$$
    rm ${TMP}/glacier-job-gpg-error_$$
    rm ${TMP}/glacier-cmd-output_$$
fi


