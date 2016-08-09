#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2016  Chip Schweiss

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

locate_quota () {
    EXPECTED_ARGS=2
    if [ "$#" -lt "$EXPECTED_ARGS" ]; then
        echo "Usage: `basename $0` {quota_dir} {date} [preferred_tag]"
        echo "  {date} must be of the same format as in quota folder name"
        echo "  [preferred_tag] will be a text match"
        return 1
    fi

    quota=""
    path=$1
    date=$2
    preferred_tag=$3

    if [ -d $path ]; then
        if [ "$#" -eq "3" ]; then
            quota=`ls -1 $path|${GREP} $date|${GREP} $preferred_tag`
        fi
        if [ "$quota" == "" ]; then
            quota=`ls -1 $path|${GREP} $date`
        fi
    else
        warning "locate_quota: Directory $path not found."
        return 1
    fi

    if [ "${quota}" == "" ]; then
        warning "locate_quota: Snapshot for $date on path $path not found."
        return 1
    fi

    echo $quota
    return 0
}

quota_job_usage () {
    local quota=
    if [ -t 1 ]; then
        cat ${TOOLS_ROOT}/quotas/USAGE
        for quota in $quotatypes; do
            echo "      $quota"
        done
    fi
}
    
show_quota_job () {

    local zfs_folder="$1"
    local folder=
    local folders=
    local fl=           # Maximum folder length
    local recursive="$2"
    local result=
    local report=
    local reports=
    local re=
    local header=
    local email=
    local emails=
    local thresh=
    local alert=
    local freq=
    local line=
    local S=$'\t' # Separator character
    local tempfile="quotajobs"

    # Test folder exists
    zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        warning "show_quota_job called on non-existant zfs folder $zfs_folder"
        quota_job_usage
        return 1
    fi

    if [[ "$recursive" != "" && "$recursive" != "-r" ]]; then
        warning "show_quota_job called with invalid parameter $recursive"
        quota_job_usage
        return 1
    fi
    
    folders=`zfs list -o name -H ${recursive} ${zfs_folder}`
    fl=`zfs list -o name -H ${recursive} ${zfs_folder} | wc -L`
    fl=60


    printf "$(color cyan)%-${fl}.${fl}s $(color green)%-10s $(color)%-5s %-40s $(color magenta)%-15s$(color)\n" \
        "Folder" "Quota" "Alert" "Email" "Frequency"
    printf "$(color cyan)%-${fl}.${fl}s $(color)%-15s %-10s %-20s %-${fl}.${fl}s %-15s\n" \
        "" "Threshold" "" "" ""
    echo

    for folder in $folders; do
        quota=`zfs get -o value -H -s local,received,default quota $folder`
        refquota=`zfs get -o value -H -s local,received,default refquota $folder`
        printf "$(color cyan)%-${fl}.${fl}s $(color green)%-15s$(color)\n" \
            "${folder}" "${quota}" 
        if [ "$refquota" != 'none' ]; then
            printf "$(color cyan)%-${fl}.${fl}s $(color green)%-.16s $(color)(ref) \n" \
            "" "$refquota"
        fi
        reports=`zfs get -o value -H -s local,received $zfs_quota_reports_property $folder`
        report=1
        re='^[0-9]+$'
        if [[ $reports =~ $re ]]; then
            if [[ "$quota" == 'none' && "$refquota" == 'none' ]]; then
                #echo -E "  $(color white red)WARNING$(color red black): Quota reports defined without quota.$(color)${S} ${S} ${S} ${S} " >> \
                #    ${TMP}/${tempfile}
                printf "  $(color white red)WARNING$(color red black): Quota reports defined without quota.$(color)\n"
            fi
            line=1
            while [ $report -le $reports ]; do
                existing=`zfs get -o value -H -s local,received ${zfs_quota_report_property}:${report} $folder`
                if [ "$existing" != '' ]; then
                    thresh=`echo $existing | ${CUT} -d '|' -f 1`
                    alert=`echo $existing | ${CUT} -d '|' -f 2`
                    freq=`echo $existing | ${CUT} -d '|' -f 4`
                    emails=`echo $existing | ${CUT} -d '|' -f 3 | ${SED} 's/;/\n/g'`
                    email_line=1
                    for email in $emails; do                    
                        if [ $email_line -gt 1 ]; then
                            thresh=" "
                            alert=" "
                            freq=" "    
                        fi
                        printf "  $(color ltgrey)%-$(( fl - 2)).$(( fl - 2))s$(color) %-10s %-4.4s  %-40s $(color magenta)%-15s$(color)\n" \
                            "${existing}" "$thresh" "$alert" "$email" "$freq" 
                        line=$(( line + 1)) 
                        email_line=$(( email_line + 1 ))
                    done
                fi
                report=$(( report + 1 ))
            done
        fi
        echo
    done 

    #cat ${TMP}/${tempfile}
#    columns -c 5 --fill -i ${TMP}/${tempfile} | \
#        ${SED} "s/warning/$(color yellow)warning$(color)/g" | \
#        ${SED} "s/critical/$(color red)critical$(color)/g"
#    rm ${TMP}/${tempfile}    

}

add_mod_quota_job () {

    local zfs_folder="$1"
    local quota_job="$2"
    local quota_job_type=
    local quota_job_keep=
    local result=
    local fixed_folder=`foldertojob $zfs_folder`
    local pool=`echo $zfs_folder | ${CUT} -f 1 -d '/'`
    local existing=

    if [ $# -lt 2 ]; then
        warning "add_mod_quota_job called with too few arguements"
        quota_job_usage
        return 1
    fi


    # Test folder exists
    zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        warning "add_mod_quota_job called on non-existant zfs folder $zfs_folder"
        quota_job_usage
        return 1
    fi

    while [ "$quota_job" != "" ]; do

        quota_job_type=`echo $quota_job | ${CUT} -f 1 -d '/'`
        quota_job_keep=`echo $quota_job | ${CUT} -f 2 -d '/'`

        # Test valid quota_job
        echo $quotatypes | ${GREP} -q "\b${quota_job_type}\b"
        result=$?
        if [ $result -ne 0 ]; then
            warning "add_mod_quota_job: invalid quota type specified: $quota_job_type"
            quota_job_usage
        fi
    
        notice "add_mod_quota_job: updating $zfs_folder job $quota_job"
        # Update the job
        zfs set ${zfs_quota_property}:${quota_job_type}="$quota_job_keep" $zfs_folder
        
        # Flush appropriate caches
        # TODO: Don't just flush but reload the cache, so next job executes quickly

        # Flush cache for the job type
        rm -fv /${pool}/zfs_tools/var/cache/zfs_cache/*${zfs_quota_property}:${quota_job_type}_${pool} \
            2>&1 1>${TMP}/clean_quota_cache_$$.txt 
        #debug "Cleaned cache for ${quota_job_type} on ${pool}" ${TMP}/clean_quota_cache_$$.txt
        rm ${TMP}/clean_quota_cache_$$.txt 2>/dev/null

        # Flush the cache for the folder
        rm -fv /${pool}/zfs_tools/var/cache/zfs_cache/*${zfs_quota_property}:${quota_job_type}_${fixed_folder} \
            2>&1 1>${TMP}/clean_quota_cache_$$.txt
        #debug "Cleaned cache for ${quota_job_type} on ${fixed_folder}" ${TMP}/clean_quota_cache_$$.txt
        rm ${TMP}/clean_quota_cache_$$.txt 2>/dev/null
    
        shift
        quota_job="$2"

    done
            
}
        
del_quota_job () {

    local zfs_folder="$1"
    local quota_job="$2"
    local result=
    local fixed_folder=`foldertojob $zfs_folder`
    local pool=`echo $zfs_folder | ${CUT} -f 1 -d '/'`
    
    if [ $# -lt 2 ]; then
        warning "del_quota_job called with too few arguements"
        quota_job_usage
        return 1
    fi

    # Test folder exists
    zfs list -o name $zfs_folder 1>/dev/null 2>/dev/null
    result=$?
    if [ $result -ne 0 ]; then
        warning "del_quota_job called on non-existant zfs folder $zfs_folder"
        quota_job_usage
        return 1
    fi

    while [ "$quota_job" != "" ]; do
        # Test valid quota_job
        echo $quotatypes | ${GREP} -q "\b${quota_job}\b"
        result=$?
        if [ $result -ne 0 ]; then
            warning "del_quota_job: invalid quota type specified: $quota_job"
            quota_job_usage
            return 1
        fi

        zfs inherit ${zfs_quota_property}:${quota_job} $zfs_folder
        # flush cache for the job type and folder
        rm -f /${pool}/zfs_tools/var/cache/zfs_cache/*${zfs_quota_property}:${quota_job}_${pool} 2>/dev/null
        rm -f /${pool}/zfs_tools/var/cache/zfs_cache/*${zfs_quota_property}:${quota_job}_${fixed_folder} 2>/dev/null

        shift
        quota_job="$2"
    done


}    
