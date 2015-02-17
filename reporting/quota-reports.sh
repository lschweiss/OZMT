#! /bin/bash

# TODO: This script relies on floating point math, which Bash has no support
#       It is worth considering using ksh or zsh for this script, it could reduce 
#       overhead on systems with lots of zfs file systems

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

logfile="$default_logfile"
report_name="$default_report_name"


update_last_report () {

    # Takes three input parameters.
    # 1: Report spool file
    # 2: "{free_trigger}|{recipient}"
    # 3: seconds since 1970-01-01 00:00:00 UTC

    local line=
    local temp_file="$TMP/update_last_report_$$"

    # Minimum number of arguments needed by this function
    local MIN_ARGS=3

    if [ "$#" -lt "$MIN_ARGS" ]; then
        error "update_report_status called with too few arguments.  $*"
        exit 1
    fi

    local status_file="$1"
    local variable="$2"
    local value="$3"

    rm -f "$temp_file"

    wait_for_lock "$status_file" 5

    # Copy all status lines execept the variable we are dealing with
    while read line; do
        echo "$line" | ${GREP} -q "^${variable}|"
        if [ $? -ne 0 ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$status_file"

    # Add our variable
    echo "${variable}|${value}" >> "$temp_file"

    # Replace the status file with the updated file
    mv "$temp_file" "$status_file"

    release_lock "$status_file"

    return 0


}


quota_report () {

    local job="$1"
    
    local quota_reports=0
    local referenced=
    local refquota=
    local quota=
    local available=
    local logicalused=
    local logicalreferenced=
    local used=
    local used_ds=
    local used_snap=
    local compression=
    local compressionratio=
    local report=
    local free_trigger=
    local alert_type=
    local trigger_percent=
    local trigger_bytes=
    local trigger_t=
    local trigger_g=
    local triggered=0
    local quota_trigger=
    local refquota_trigger=
    local size_trigger=
    local ref_free=
    local percent_free=
    local mathline=
    local destinations=
    local frequency=
    local frequency_human=
    local last_report=
    local now_secs=`${DATE} +%s`
    local elapsed=
    local emailsubject=
    local emailfile=$TMP/zfs_quota_report_$job_$$
    local receiver=
    local email_bcc=
    local to=
    local cc=
    local cc_list=
    
    source $jobfolder/$job

    local jobstat="/${pool}/zfs_tools/var/spool/reports"

    mkdir -p "$jobstat"
    touch "${jobstat}/${job}"
    init_lock "${jobstat}/${job}"

    if [[ $quota_reports -eq 0 && ${quota_report[0]} == "" ]]; then
        warning "Quota report job defined for $quota_path, but no reports are defined."
    else
        referenced=`zfs list -Hp -o referenced $quota_path`
        refquota=`zfs list -Hp -o refquota $quota_path`
        logicalused=`zfs list -Hp -o logicalused $quota_path`
        logicalreferenced=`zfs list -Hp -o logicalreferenced $quota_path`
        quota=`zfs list -Hp -o quota $quota_path`
        available=`zfs list -Hp -o available $quota_path`
        used=`zfs list -Hp -o used $quota_path`
        used_ds=`zfs list -Hp -o usedbydataset $quota_path`
        used_snap=`zfs list -Hp -o usedbysnapshots $quota_path`
        compression=`zfs list -Hp -o compression $quota_path`
        compressratio=`zfs list -Hp -o compressratio $quota_path`
        report=0
        debug "Checking $quota_path"
        debug "Referenced:          $referenced"
        debug "Ref quota:           $refquota"
        debug "Logical used:        $logicalused"
        debug "Logical ref:         $logicalreferenced"
        debug "Quota:               $quota"
        debug "Used:                $used"
        debug "Used by DS:          $used_ds"
        debug "Used by snaps:       $used_snap"
        debug "Compresion:          $compression"
        debug "Compression ratio:   $compressratio"
        debug "Available:           $available"
        
        while [ $report -le $quota_reports ]; do
            if [ "${quota_report[$report]}" != "" ]; then
                triggered=0
                free_trigger=`echo ${quota_report[$report]} | ${AWK} -F '|' '{print $1}'`
                alert_type=`echo ${quota_report[$report]} | ${AWK} -F '|' '{print $2}'`
                destinations=`echo ${quota_report[$report]} | ${AWK} -F '|' '{print $3}'`
                frequency_human=`echo ${quota_report[$report]} | ${AWK} -F '|' '{print $4}'`

                debug "Free trigger:            $free_trigger"
                debug "Alert type:              $alert_type"
                debug "Destinations:            $destinations"
                debug "Frequency:               $frequency_human"
    
                case $frequency_human in 
                    *w) # Weeks
                        frequency=`echo $frequency_human | ${SED} 's/w/*604800/' | $BC`
                        ;;
                    *d) # Days
                        frequency=`echo $frequency_human | ${SED} 's/d/*86400/' | $BC`
                        ;;
                    *h) # Hours
                        frequency=`echo $frequency_human | ${SED} 's/h/*3600/' | $BC`
                        ;;
                    *m) # Minutes
                        frequency=`echo $frequency_human | ${SED} 's/m/*60/' | $BC`
                        ;;
                    *)  # Default
                        frequency="$frequency_human"
                        ;;
                esac

                if [[ "$frequency" == "" || $frequency -lt $minimum_report_frequency ]]; then
                    # Minimum report frequency
                    frequency="$minimum_report_frequency"
                fi
                    
                case $free_trigger in 
                    *%) # Trigger on percentage                        
                        trigger_percent=`echo $free_trigger | ${AWK} -F '%' '{print $1}'`
                        # Check by reference quota
                        if [ $refquota -ne 0 ] ; then
                            ref_free=`echo "scale=2;100-(${referenced}*100/${refquota})" | $BC | ${SED} 's/^\./0./'`
                            debug "\"scale=2;100-(${referenced}*100/${refquota})\" | $BC | ${SED} 's/^\./0./'"
                            if [ $(echo "$ref_free <= $trigger_percent" | $BC) -eq 1 ]; then 
                                triggered=1
                                refquota_trigger="The zfs folder $quota_path has less than $free_trigger free of $(bytestohuman $refquota 2) reference quota<br>"
                            fi
                        fi
                        # Check by full quota
                        if [ $quota -ne 0 ]; then
                            percent_free=`echo "scale=2;100-(${used}*100/${quota})" | $BC | ${SED} 's/^\./0./'`
                            if [ $(echo "$percent_free <= $trigger_percent" | $BC) -eq 1 ]; then
                                triggered=1
                                quota_trigger="The zfs folder $quota_path has less than $free_trigger free of $(bytestohuman $quota 2) quota<br>"
                            fi
                        fi
                        ;;
                    *T*) # Trigger on terabytes free
                        mathline=`echo $free_trigger | ${SED} 's/TiB/*(1024^4)/' | ${SED} 's/TB/*(1000^4)/' | ${SED} 's/T/*(1024^4)/'`
                        trigger_t=`echo $free_trigger | ${AWK} -F 'T' '{print $1}'`
                        trigger_bytes=`echo "${mathline}" | $BC`
                        if [ $available -le $trigger_bytes ]; then
                            triggered=1
                            size_trigger="The zfs folder $quota_path has $(bytestohuman $available 2) free.  Triggered at $(bytestohuman $trigger_bytes 2) free<br>"
                        fi
                        ;;
                    *G*) # Trigger on gigabytes free
                        mathline=`echo $free_trigger | ${SED} 's/GiB/*(1024^3)/' | ${SED} 's/GB/*(1000^3)/' | ${SED} 's/G/*(1024^3)/'`
                        trigger_g=`echo $free_trigger | ${AWK} -F 'G' '{print $1}'`
                        trigger_bytes=`echo "${mathline}" | $BC`  
                        if [ $available -le $trigger_bytes ]; then
                            triggered=1
                            size_trigger="The zfs folder $quota_path has $(bytestohuman $available 2) free.  Triggered at $(bytestohuman $trigger_bytes 2) free<br>"
                        fi
                        ;; 
                esac
                if [ $triggered -eq 1 ]; then
                    subject="$default_quota_report_title Quota ${alert_type^^}  for $quota_path"
                    # Build the email report
                    if [ -f "$QUOTA_REPORT_TEMPLATE" ]; then
                        if [ "${QUOTA_REPORT_TEMPLATE: -4}" == "html" ]; then
                            emailfile="${emailfile}.html"
                        fi
                        cat $QUOTA_REPORT_TEMPLATE | \
                        ${SED} "s,#HOSTNAME#,$HOSTNAME,g" | \
                        ${SED} "s,#ALERT_TYPE#,${alert_type,,},g" | \
                        ${SED} "s,#ZFS_FOLDER#,$quota_path,g" | \
                        ${SED} "s/#REFERENCED#/$(bytestohuman $referenced 2)/g" | \
                        ${SED} "s/#REF_QUOTA#/$(bytestohuman $refquota 2)/g" | \
                        ${SED} "s/#LOGICALUSED#/$(bytestohuman $logicalused 2)/g" | \
                        ${SED} "s/#LOGICALREFERENCED#/$(bytestohuman $logicalreferenced 2)/g" | \
                        ${SED} "s/#QUOTA#/$(bytestohuman $quota 2)/g" | \
                        ${SED} "s/#AVAILABLE#/$(bytestohuman $available 2)/g" | \
                        ${SED} "s/#USED#/$(bytestohuman $used 2)/g" | \
                        ${SED} "s/#USED_DS#/$(bytestohuman $used_ds 2)/g" | \
                        ${SED} "s/#USED_SNAP#/$(bytestohuman $used_snap 2)/g" | \
                        ${SED} "s/#COMPRESSION#/$compression/g" | \
                        ${SED} "s/#COMPRESSRATIO#/$compressratio/g" | \
                        ${SED} "s,#REFQUOTA_TRIGGER#,$refquota_trigger,g" | \
                        ${SED} "s,#QUOTA_TRIGGER#,$quota_trigger,g" | \
                        ${SED} "s,#SIZE_TRIGGER#,$size_trigger,g" > $emailfile
                    else
                        error "Quote report template file not found: $QUOTA_REPORT_TEMPLATE"
                        exit 1
                    fi
            
                    # Send to each destination
    
                    if [ "$ALL_QUOTA_REPORTS" != "" ]; then
                        email_bcc="-b \"$ALL_QUOTA_REPORTS\""
                    fi
                    
                    receiver=1
                    recipient=`echo $destinations | ${CUT} -d ';' -f $receiver`
                    debug "Recipient: $recipent"
                    while [ "$recipient" != "" ]; do
                        # Check frequency of reporting
                        last_report=`cat ${jobstat}/${job} | ${GREP} "${free_trigger}|${recipient}" | ${CUT} -d "|" -f 3 | tail -1`
                        debug "Last report: $last_report"
                        debug "Now: $now_secs"
                        debug "Frequency: $frequency"
                        elapsed=$(( now_secs - last_report ))
                        if [ $elapsed -ge $frequency ]; then
                            # Add recipient to receiver list
                            if [ $receiver -eq 1 ]; then
                                to="$recipient"
                            else
                                cc_list="-c \"$recipient\" $cc_list"
                            fi
                            # Update last report
                            update_last_report "${jobstat}/${job}" "${free_trigger}|${recipient}" "$now_secs"
                        else
                            debug "Not adding $recipient to report for $quota_path only $elapsed secs since last report.  Requires $frequency."
                        fi    
                        receiver=$(( receiver + 1 ))
                        recipient=`echo $destinations | ${CUT} -d ';' -f $receiver`
                        echo "$destinations" | ${GREP} -q ';' 
                        if [ $? -ne 0 ]; then
                            # There is only one recipient.  'cut' will always return it without a separator.
                            recipient=""
                        fi
                    done    

                    # Send the report 
                    if [ "$to" != "" ]; then
                        debug "Sending email report to $to;$cc_list;$email_bcc"
                        debug "  $subject"
                        ./send_email.sh -s "$subject" -f "$emailfile" -r "$to" $cc_list $email_bcc
                    fi
                    

                fi
                if [ ! -t 1 ]; then
                    rm -f $emailfile 2> /dev/null
                fi
            fi
            
            report=$(( report + 1 ))
        done
    fi

}




# collect jobs

pools="$(pools)"

for pool in $pools; do

    jobfolder="/${pool}/zfs_tools/etc/reports/jobs/quota"

    $BC -v &> /dev/null
    if [ $? -ne 0 ]; then
        error "GNU bc required for quota reports"
        exit 1
    fi

    if [ -d "$jobfolder" ]; then

        jobs=`ls -1 $jobfolder`

        for job in $jobs; do
            quota_reports=0
            launch quota_report "$job"
        done

    fi

done
