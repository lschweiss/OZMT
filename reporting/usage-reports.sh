#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2018  Chip Schweiss

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


usage_report () {

    local pool="$1"
    local line=1

    
    # Build the email report
   

    debug "Generating report for pool ${pool}"

    cp usage-report/header.html ${TMP}/usage_${pool}.html

    cat usage-report/table.header.html >> ${TMP}/usage_${pool}.html

    # Summary report
    cat usage-report/summary-row1.html | \
        ${SED} "s,#NAME#,NAME,g" | \
        ${SED} "s,#USED#,USED,g" >> ${TMP}/usage_${pool}.html

    zfs list -H -d1 -o name,used ${pool} > ${TMP}/usage_${pool}
    while read name used; do
        line=$(( line + 1 ))
        [ $line > 2 ] && line=1
        cat usage-report/summary-row${line}.html | \
            ${SED} "s,#NAME#,$name,g" | \
            ${SED} "s,#USED#,$used,g" >> ${TMP}/usage_${pool}.html
    done < ${TMP}/usage_${pool}
    cat usage-report/table.footer.html >> ${TMP}/usage_${pool}.html

   
    # Detailed report

    echo "<p>Top level folders:</p>" >> ${TMP}/usage_${pool}.html

    cat usage-report/table.header.html >> ${TMP}/usage_${pool}.html
    line=1
    cat usage-report/detail-row1.html | \
        ${SED} "s,#NAME#,NAME,g" | \
        ${SED} "s,#USED#,USED,g" | \
        ${SED} "s,#AVAIL#,AVAIL,g" | \
        ${SED} "s,#REFER#,REFER,g" | \
        ${SED} "s,#COMPRESSRATIO#,RATIO,g" | \
        ${SED} "s,#LOGICALUSED#,LUSED,g" | \
        ${SED} "s,#QUOTA#,QUOTA,g" | \
        ${SED} "s,#REFQUOTA#,REFQUOTA,g" >> ${TMP}/usage_${pool}.html

    zfs list -H -d2 -o name,used,avail,refer,compressratio,logicalused,quota,refquota ${pool} >> ${TMP}/usage_${pool}
    while read name used avail refer compressratio logicalused quota refquota; do
        line=$(( line + 1 ))
        [ $line > 2 ] && line=1
        cat usage-report/detail-row${line}.html | \
            ${SED} "s,#NAME#,$name,g" | \
            ${SED} "s,#USED#,$used,g" | \
            ${SED} "s,#AVAIL#,$avail,g" | \
            ${SED} "s,#REFER#,$refer,g" | \
            ${SED} "s,#COMPRESSRATIO#,$compressratio,g" | \
            ${SED} "s,#LOGICALUSED#,$logicalused,g" | \
            ${SED} "s,#QUOTA#,$quota,g" | \
            ${SED} "s,#REFQUOTA#,$refquota,g" >> ${TMP}/usage_${pool}.html
    done < ${TMP}/usage_${pool}
    cat usage-report/table.footer.html >> ${TMP}/usage_${pool}.html

    line=1
    zfs list -H -r -o name,used,avail,refer,compressratio,logicalused,quota,refquota ${pool} >> ${TMP}/usage_${pool}
    
   
    echo "<p>Top level folders:</p>" >> ${TMP}/usage_${pool}.html
    cat usage-report/table.header.html >> ${TMP}/usage_${pool}.html
    line=1
    cat usage-report/detail-row1.html | \
        ${SED} "s,#NAME#,NAME,g" | \
        ${SED} "s,#USED#,USED,g" | \
        ${SED} "s,#AVAIL#,AVAIL,g" | \
        ${SED} "s,#REFER#,REFER,g" | \
        ${SED} "s,#COMPRESSRATIO#,RATIO,g" | \
        ${SED} "s,#LOGICALUSED#,LUSED,g" | \
        ${SED} "s,#QUOTA#,QUOTA,g" | \
        ${SED} "s,#REFQUOTA#,REFQUOTA,g" >> ${TMP}/usage_${pool}.html
    
    while read name used avail refer compressratio logicalused quota refquota; do
        line=$(( line + 1 ))
        [ $line > 2 ] && line=1
        cat usage-report/detail-row${line}.html | \
            ${SED} "s,#NAME,$name,g" | \
            ${SED} "s,#USED#,$used,g" | \
            ${SED} "s,#AVAIL#,$avail,g" | \
            ${SED} "s,#REFER#,$refer,g" | \
            ${SED} "s,#COMPRESSRATIO#,$compressratio,g" | \
            ${SED} "s,#LOGICALUSED#,$logicalused,g" | \
            ${SED} "s,#QUOTA#,$quota,g" | \
            ${SED} "s,#REFQUOTA#,$refquota,g" >> ${TMP}/usage_${pool}.html
    done < ${TMP}/usage_${pool}
    cat usage-report/table.footer.html >> ${TMP}/usage_${pool}.html
 
    cat usage-report/footer.html >> ${TMP}/usage_${pool}.html

    
    
    # Send the report 
    debug "Emailing report for pool ${pool} to $email_to"
    subject="ZFS usage report ${pool}"
    ./send_email.sh -s "$subject" -f "${TMP}/usage_${pool}.html" -r "chip@nrg.wustl.edu" #"$email_to" 
    
    

}



pools="$(pools)"

for pool in ${pools}; do

    
    usage_report "${pool}"

done
