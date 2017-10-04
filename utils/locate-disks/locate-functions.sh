#! /bin/bash


# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2017  Chip Schweiss

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


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

. /opt/ozmt/zfs-tools-init.sh

logfile="$default_logfile"

report_name="$default_report_name"

now=`${DATE} +"%F %H:%M:%S%z"`

local_pools="zpool list -H -o name"

myTMP=${TMP}/disk-map
MKDIR $myTMP

locate_hbas () {
    # Only LSI / Avago / Broadcom HBAs are supported.   
    # Find SAS2 HBAs

    $SAS2IRCU list | \
    while IFS='' read -r line || [[ -n "$line" ]]; do
        index=`echo $line | ${AWK} -F ' ' '{print $1}'`
        echo $index
    done


}


collect_expander_info () {
    local devs=
    local dev=
    local expanders=
    local ses_path=
    local vendor=
    local model=
    local fwrev=
    local line=
    local line_num=
    local path=
    local paths=
    local slots=
    local this_sasaddr=
    local slot_des='false'
    declare -A expander
    expander_list=

    case $os in 
        'SunOS')
            ses_path='/dev/es'
            ;;
        'Linux')
            ses_path='/dev/bsg'
            ;;
    esac

    echo "declare -A expander" > $myTMP/expanders
    rm -f $myTMP/ses_wwn.tmp
    touch $myTMP/ses_wwn.tmp

    if [ ! -f $myTMP/disks ]; then
        collect_disk_info
    fi
    
    source $myTMP/disks

    debug "Collecting SAS expander information"

    source $myTMP/disks
    source $myTMP/sasaddresses
     
    devs=`ls -1 ${ses_path}`
    for dev in $devs; do
        $SG_SES -p ed ${ses_path}/${dev} 1> $myTMP/ses_info.tmp 2>/dev/null
        if [ $? -ne 0 ]; then
            # Not a useful SES link
            rm -f $myTMP/ses_info.tmp
            continue
        else
            # Parse the output for useful information
            line_num=0
            while IFS='' read -r line || [[ -n "$line" ]]; do
                line_num=$(( line_num + 1 ))
                if [ $line_num -eq 1 ]; then
                    vendor=`echo ${line:2:10} | $AWK '{$1=$1};1'`
                    model=`echo ${line:12:16} | $AWK '{$1=$1};1'`
                    fwrev="${line:30}"
                fi
                if [ "${line:2:42}" == 'Primary enclosure logical identifier (hex)' ]; then
                    wwn=`echo $line | $AWK -F ': ' '{print $2}'`
                    cat $myTMP/ses_wwn.tmp | $GREP -q $wwn 
                    if [ $? -eq 0 ]; then
                        # We've already seen this wwn, just add increment the paths
                        paths="$(( ${expander["${wwn}_paths"]} + 1))"
                    else
                        paths=1
                        expander_list="$wwn $expander_list"
                    fi
                    echo $wwn >> $myTMP/ses_wwn.tmp
                    expander["${wwn}_paths"]="$paths"
                    echo "expander["${wwn}_paths"]=\"$paths\"" >> $myTMP/expanders
                    echo "expander["${wwn}_path_${paths}"]=\"${ses_path}/${dev}\"" >> $myTMP/expanders
                fi
                if [ "${line:4:49}" == 'Element type: Array device slot, subenclosure id:' ]; then
                    slot_des='true'
                    slots=0
                    continue
                fi
                if [ "$slot_des" == 'true' ]; then
                    if [ "${line:6:7}" == 'Element' ]; then
                        slots=$(( slots + 1 )) 
                    else
                        if [ "${line:6:7}" == "Overall" ]; then
                            # Skip the line before the elements
                            continue
                        else
                            slot_des='false'
                        fi
                    fi
                fi
            done < "$myTMP/ses_info.tmp"
    
            echo "expander["${wwn}_vendor"]=\"$vendor\"" >> $myTMP/expanders
            echo "expander["${wwn}_model"]=\"$model\"" >> $myTMP/expanders
            echo "expander["${wwn}_fwrev"]=\"$fwrev\"" >> $myTMP/expanders
            echo "expander["${wwn}_slots"]=\"$slots\"" >> $myTMP/expanders

            # Collect attached sas addresses 

            source $myTMP/expanders
            slot=0
            while [ $slot -lt $slots ]; do

                this_sasaddr=`$SG_SES -I 0,${slot} -p aes ${ses_path}/${dev} 2>/dev/null | \
                    $GREP 'SAS address:' | $GREP -v 'attached' | $AWK -F 'x' '{print $2}'`
                echo "expander["${wwn}_sasaddr_${slot}_${paths}"]=\"$this_sasaddr\"" >> $myTMP/expanders

                this_wwn="${sasaddr["${this_sasaddr}_wwn"]}"
                if [ "${this_wwn}" != '' ]; then
                    #echo "addr: $this_sasaddr wwn: $this_wwn"
                    echo "expander["${wwn}_diskwwn_${slot}"]=\"$this_wwn\"" >> $myTMP/expanders
                    echo "disk["${this_wwn}_expander"]=\"$wwn\"" >> $myTMP/disks
                    echo "disk["${this_wwn}_slot"]=\"$slot\"" >> $myTMP/disks
                fi

                if [ "${disk["${this_wwn}_osname"]}" != "" ]; then
                    #echo "addr: $this_sasaddr osname: ${disk["${this_wwn}_osname"]}"
                    echo "expander["${wwn}_diskosname_${slot}"]=\"${disk["${this_wwn}_osname"]}\"" >> $myTMP/expanders
                fi
            
                slot=$(( slot + 1 ))

            done # while slot

        fi

    done # for dev

    rm -f $myTMP/ses_info.tmp
    rm -f $myTMP/ses_wwn.tmp    

    echo "expander_list=\"$expander_list\"" >> $myTMP/expanders
    source $myTMP/expanders

}


collect_disk_info () {

    local devs=
    local dev=
    local addr=
    local addrs=
    local wwns=
    local vendor=
    local model=
    local fwrev=
    local serial=
    local unitserial=
    local result=
    declare -A disk
    declare -A sasaddr

    pushd . 1>/dev/null
    cd /dev/rdsk
    devs=`ls -1 *d0`
    popd 1>/dev/null
    echo "declare -A disk" > $myTMP/disks
    echo "declare -A sasaddr" > $myTMP/sasaddresses

    debug "Collecting disk information"

    for dev in $devs; do
        addrs=0
        ${TIMEOUT} 3s $SDPARM --quiet --inquiry /dev/rdsk/${dev}s0 1> $myTMP/disk_info.tmp  2> /dev/null
        result=$?
        if [ $result -ne 0 ]; then
            # Not a useful disk link
            rm -f $myTMP/disk_info.tmp
            if [ $result -eq 124 ]; then
                debug "$dev is not responding"
                echo "disk["${dev}_wwn"]=\"UNAVAILABLE\"" >> $myTMP/disks
            fi
            continue
        else
            while IFS='' read -r line || [[ -n "$line" ]]; do
                if [ "${line:0:2}" == '0x' ]; then
                    # This is a SAS address
                    addrs=$(( addrs + 1 ))
                    sasaddr["$addrs"]="${line:2:16}"
                fi
                if [ "${line:0:4}" == "naa." ]; then
                    # This is a WWN
                    wwn="${line:4:16}"
                    wwn="${wwn,,}"
                fi
            done < $myTMP/disk_info.tmp
        fi

        vendor=
        model=
        fwrev=
        serial=
        unitserial=

        $SG_INQ -s /dev/rdsk/${dev}s0 1> $myTMP/disk_info.tmp  2> /dev/null
        if [ $? -ne 0 ]; then
            # Not a useful disk link
            rm -f $myTMP/disk_info.tmp
        else
            while IFS='' read -r line || [[ -n "$line" ]]; do
                if [[ "${line}" == *"Vendor identification"* ]]; then
                    vendor="${line:24}"
                    continue
                fi
                if [[ "${line}" == *"Product identification"* ]]; then
                    model="${line:25}"
                    continue
                fi
                if [[ "${line}" == *"Product revision level"* ]]; then
                    fwrev="${line:25}"
                    continue
                fi
                if [[ "${line}" == *"Vendor specific"* ]]; then
                    serial="${line:18}"
                    continue
                fi
                if [[ "${line}" == *"Unit serial number"* ]]; then
                    unitserial="${line:22}"
                fi
                
            done < $myTMP/disk_info.tmp
        fi

        echo "disk["${wwn}_osname"]=\"$dev\"" >> $myTMP/disks
        echo "disk["${dev}_wwn"]=\"$wwn\"" >> $myTMP/disks
        echo "disk["${wwn}_sasaddrs"]=\"$addrs\"" >> $myTMP/disks
        [ -n $vendor ] && echo "disk["${wwn}_vendor"]=\"${vendor//[[:space:]]}\"" >> $myTMP/disks
        [ -n $model ] && echo "disk["${wwn}_model"]=\"${model//[[:space:]]}\"" >> $myTMP/disks
        [ -n $fwrev ] && echo "disk["${wwn}_fwrev"]=\"${fwrev//[[:space:]]}\"" >> $myTMP/disks
        [ -n $serial ] && echo "disk["${wwn}_serial"]=\"${serial//[[:space:]]}\"" >> $myTMP/disks
        [ -n $unitserial ] && echo "disk["${wwn}_unitserial"]=\"${unitserial//[[:space:]]}\"" >> $myTMP/disks

        addr=1
        while [ $addr -le $addrs ]; do
            echo "disk["${wwn}_sasaddr_${addr}"]=\"${sasaddr["$addr"]}\"" >> $myTMP/disks
            echo "sasaddr["${sasaddr["$addr"]}_wwn"]=\"$wwn\"" >> $myTMP/sasaddresses
            addr=$(( addr + 1 ))
        done
        wwns="$wwn $wwns"
    done

    echo "disk_list=\"$wwns\"" >> $myTMP/disks

    rm -f $myTMP/disk_info.tmp

    source $myTMP/disks
    

}
    
