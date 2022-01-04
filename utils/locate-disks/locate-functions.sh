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

sd_map () {
    paste -d= <(iostat -x | $AWK '{print $1}') <(iostat -xn | $AWK '{print $NF}') | $TAIL -n +3
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
    local wwn=
    local disk_wwn=
    local jbod_name=
    local slot_des='false'
    declare -A expander
    expander_list=

    case $os in
        'SunOS')
            ses_path='/dev/es'
            devs=`ls -1 ${ses_path}`
            ;;
        'Linux')
            ses_path='/dev/bsg'
            devs=`lsscsi -i | ${GREP} 'enclosu' | $CUT -d "[" -f2 | $CUT -d "]" -f1`
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
     
    for dev in $devs; do
        debug "Collecting slot info from: ${ses_path}/${dev}"
        $SG_SES -p ed ${ses_path}/${dev} 1> $myTMP/ses_info.tmp 2>/dev/null
        if [ $? -ne 0 ]; then
            # Not a useful SES link
            #rm -f $myTMP/ses_info.tmp
            debug "Skipping ${ses_path}/${dev}"
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

            jbod_name=`cat /etc/ozmt/jbod-map 2>/dev/null | ${GREP} $wwn 2> /dev/null | ${AWK} -F ' ' '{print $2}'`
            if [ "$jbod_name" != "" ]; then
                echo "expander["${wwn}_name"]=\"$jbod_name\"" >> $myTMP/expanders
            fi
            

            # Collect attached sas addresses 

            # TODO : This can be significantly sped up by using 'sg_ses -p 10 ${ses_path}/${dev}' 
            #        and parsing the output instead of reading each slot

            debug "Collecting disk info from ${ses_path}/${dev}"
            $SG_SES -p 10 ${ses_path}/${dev} 2>/dev/null > $myTMP/disk_wwn.tmp
            $SG_SES -p 2 ${ses_path}/${dev} 2>/dev/null > $myTMP/disk_status.tmp

            source $myTMP/expanders
            slot=0
            while [ $slot -lt $slots ]; do
                #this_sasaddr=`$SG_SES -I 0,${slot} -p aes ${ses_path}/${dev} 2>/dev/null | \
                #    $GREP 'SAS address:' | $GREP -v 'attached' | $AWK -F 'x' '{print $2}'`
                this_sasaddr=`cat $myTMP/disk_wwn.tmp | \
                    $GREP -A 9 "Element index: $slot " | \
                    $GREP 'SAS address:' | $GREP -v 'attached' | $AWK -F 'x' '{print $2}'`
                echo "expander["${wwn}_sasaddr_${slot}_${paths}"]=\"$this_sasaddr\"" >> $myTMP/expanders

                if [ "$this_sasaddr" != '0' ]; then
                    disk_wwn="${sasaddr["${this_sasaddr}_wwn"]}"
                    if [ "${disk_wwn}" != '' ]; then
                        debug "Found disk: $disk_wwn"
                        #echo "addr: $this_sasaddr wwn: $disk_wwn"
                        echo "expander["${wwn}_diskwwn_${slot}"]=\"$disk_wwn\"" >> $myTMP/expanders
                        echo "disk["${disk_wwn}_expander"]=\"$wwn\"" >> $myTMP/disks
                        echo "disk["${disk_wwn}_slot"]=\"$slot\"" >> $myTMP/disks
                    fi

                    if [ "${disk["${disk_wwn}_osname"]}" != "" ]; then
                        #echo "addr: $this_sasaddr osname: ${disk["${disk_wwn}_osname"]}"
                        echo "expander["${wwn}_diskosname_${slot}"]=\"${disk["${disk_wwn}_osname"]}\"" >> $myTMP/expanders
                    fi
                fi
            
                cat $myTMP/disk_status.tmp | \
                    $GREP -m 1 -A 7 "Element $slot descriptor" > $myTMP/disk_status_slot.tmp

                slot_pfailure=`cat $myTMP/disk_status_slot.tmp | \
                    $GREP 'Predicted failure=' | $AWK -F ',' '{print $1}' | $AWK -F '=' '{print $2}'`
                echo "expander["${wwn}_pfailure_${slot}"]=\"$slot_pfailure\"" >> $myTMP/expanders

                slot_disabled=`cat $myTMP/disk_status_slot.tmp | \
                    $GREP 'Disabled=' | $AWK -F ',' '{print $2}' | $AWK -F '=' '{print $2}'`
                echo "expander["${wwn}_disabled_${slot}"]=\"$slot_disabled\"" >> $myTMP/expanders

                slot_status=`cat $myTMP/disk_status_slot.tmp | \
                    $GREP 'status: ' | $AWK -F ',' '{print $4}' | $AWK -F ': ' '{print $2}'`
                echo "expander["${wwn}_status_${slot}"]=\"$slot_status\"" >> $myTMP/expanders

                slot_ident=`cat $myTMP/disk_status_slot.tmp | \
                    $GREP 'Ident=' | $AWK -F ',' '{print $3}' | $AWK -F '=' '{print $2}'`
                echo "expander["${wwn}_ident_${slot}"]=\"$slot_ident\"" >> $myTMP/expanders

                slot_fault=`cat $myTMP/disk_status_slot.tmp | \
                    $GREP 'Fault reqstd=' | $AWK -F ',' '{print $3}' | $AWK -F '=' '{print $2}'`
                echo "expander["${wwn}_fault_${slot}"]=\"$slot_fault\"" >> $myTMP/expanders

                slot_off=`cat $myTMP/disk_status_slot.tmp | \
                    $GREP 'Device off=' | $AWK -F ',' '{print $4}' | $AWK -F '=' '{print $2}'`
                echo "expander["${wwn}_off_${slot}"]=\"$slot_off\"" >> $myTMP/expanders
                
            
                slot=$(( slot + 1 ))

            done # while slot

        fi

    done # for dev

    #rm -f $myTMP/ses_info.tmp
    #rm -f $myTMP/ses_wwn.tmp    

    echo "expander_list=\"$expander_list\"" >> $myTMP/expanders
    source $myTMP/expanders

}


collect_disk_info () {

    local devs=
    local dev=
    local devpath=
    local tdev=
    local sdnum=
    local addr=
    local addrs=
    local wwns=
    local vendor=
    local model=
    local fwrev=
    local serial=
    local unitserial=
    local result=
    local soft_error=
    local hard_error=
    local trans_error=
    declare -A disk
    declare -A sasaddr

    if [ "$SDPARM" == '/bin/false' ]; then 
        error "Cannot map disks, sdparm not installed."
    fi

    pushd . 1>/dev/null

    case $os in
        'SunOS')
            devpath='/dev/rdsk'
            cd $devpath
            # Not all devices get a *d0 link        
            devs=`ls -1 *d0s0`
            sd_map > $myTMP/sdmap
            iostat -e > $mytmp/io.errors
            ;;
        'Linux')
            devpath="$diskdev_path"
            cd $devpath
            devs=`ls -1 | ${GREP} "^${diskdev_prefix}" | ${GREP} -v '\-part'`
            ;;
    esac

    popd 1>/dev/null
    echo "declare -A disk" > $myTMP/disks
    echo "declare -A sasaddr" > $myTMP/sasaddresses

    debug "Collecting disk information"

    mkdir $myTMP/disk_info


    for dev in $devs; do
        case $os in
            'SunOS')
                tdev="${dev::-2}"
                ;;
            'Linux')
                tdev="${dev}" #:${#diskdev_prefix}}"
                ;;
        esac
        
        # Try up to 3 times
        ( 
        try=0
        while [ $try -lt 3 ]; do
            nice -n 15 $TIMEOUT 5s $SDPARM --quiet --inquiry ${devpath}/${dev} 1> $myTMP/disk_info/${tdev}_disk_info.sdparm 2> /dev/null
            echo $? > $myTMP/disk_info/${tdev}_disk_info.result 
            result=`cat $myTMP/disk_info/${tdev}_disk_info.result`
            if [ $? -eq 0 ]; then
                break
            else
                debug "Could not collect sdparm for ${devpath}/${dev}  Error $result  Try $(( try + 1 ))"
            fi
            try=$(( try + 1 ))
        done 
        ) &

        
    done

 
    wait

    for dev in $devs; do
        sdnum=
        case $os in
            'SunOS')
                tdev="${dev::-2}"
                sdnum=`cat $myTMP/sdmap | $GREP $tdev | $CUT -d '=' -f1`
                ;;
            'Linux')
                tdev="${dev}" #:${#diskdev_prefix}}"
                ;;
        esac
        wwn=
        addrs=0
        result=`cat $myTMP/disk_info/${tdev}_disk_info.result`
        if [ $result -ne 0 ]; then
            # Not a useful disk link
            if [ $result -eq 124 ]; then
                debug "$tdev is not responding"
                echo "disk["${tdev}_wwn"]=\"UNAVAILABLE\"" >> $myTMP/disks
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
            done < $myTMP/disk_info/${tdev}_disk_info.sdparm
        fi

        vendor=
        model=
        fwrev=
        serial=
        unitserial=

        $SG_INQ -s ${devpath}/${dev} 1> $myTMP/disk_info/${tdev}_disk_info.sginq  2> /dev/null
        if [ $? -ne 0 ]; then
            # Not a useful disk link
            echo "UNKNOWN" > $myTMP/disk_info/${tdev}_disk_info.sginq
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
                    unitserial="$($SED -e 's/[[:space:]]*$//' <<<${line:22})"
                fi
                
            done < $myTMP/disk_info/${tdev}_disk_info.sginq
        fi

        if [ "$wwn" == '' ]; then
            [ -n "$unitserial" ] && wwn="nowwn.${unitserial}" 
        fi

        if [ "$wwn" == '' ]; then
            [ -n "$serial" ] && wwn="nowwn.${serial}" 
        fi

        if [ "$wwn" == '' ]; then
            warning "Could not collect or assign a WWN to disk at ${tdev}"
            continue
        fi


        echo "disk["${wwn}_osname"]=\"$tdev\"" >> $myTMP/disks
        echo "disk["${tdev}_wwn"]=\"$wwn\"" >> $myTMP/disks
        echo "disk["${wwn}_sasaddrs"]=\"$addrs\"" >> $myTMP/disks
        [ -n "$vendor" ] && echo "disk["${wwn}_vendor"]=\"${vendor//[[:space:]]}\"" >> $myTMP/disks
        [ -n "$model" ] && echo "disk["${wwn}_model"]=\"${model//[[:space:]]}\"" >> $myTMP/disks
        [ -n "$fwrev" ] && echo "disk["${wwn}_fwrev"]=\"${fwrev//[[:space:]]}\"" >> $myTMP/disks
        [ -n "$serial" ] && echo "disk["${wwn}_serial"]=\"${serial//[[:space:]]}\"" >> $myTMP/disks
        [ -n "$unitserial" ] && echo "disk["${wwn}_unitserial"]=\"${unitserial//[[:space:]]}\"" >> $myTMP/disks
        if [ -n "$sdnum" ]; then
            echo "disk["${wwn}_sdnum"]=\"${sdnum//[[:space:]]}\"" >> $myTMP/disks
            cat $mytmp/io.errors | $GREP "${sdnum} " > $myTMP/io.disk.error
            soft_error=`cat $myTMP/io.disk.error | $AWK -F ' ' '{print $2}'`
            hard_error=`cat $myTMP/io.disk.error | $AWK -F ' ' '{print $3}'`
            trans_error=`cat $myTMP/io.disk.error | $AWK -F ' ' '{print $4}'`
            echo "disk["${wwn}_softerror"]=\"${soft_error//[[:space:]]}\"" >> $myTMP/disks
            echo "disk["${wwn}_harderror"]=\"${hard_error//[[:space:]]}\"" >> $myTMP/disks
            echo "disk["${wwn}_transerror"]=\"${trans_error//[[:space:]]}\"" >> $myTMP/disks
        fi
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
    source $myTMP/sasaddresses

}

locate_in_use_disks () {

    local host=
    local execute=
    local pool=
    local pools=
    local disk_start=
    local vdev=
    local line=
    local pool_state=
    local pool_read_err=
    local pool_write_err=
    local pool_cksum_err=
    local disk_osname=
    local disk_state= 
    local disk_read_err= 
    local disk_write_err=
    local disk_cksum_err=
    local disk_wwn=
    local slot=


    debug "Collecting in use disk information"

    if [ "$cluster_hosts" == '' ]; then
        cluster_hosts="$HOSTNAME"
    fi

    if [ ! -f $myTMP/expanders ]; then
        collect_expander_info
    fi

    source $myTMP/disks
    source $myTMP/expanders

    # Collect active disks in the cluster
    for host in $cluster_hosts; do
        notice "Collecting disk mappings for $host"

        if [ "$host" == "$HOSTNAME" ]; then
            # Excute locally
            execute=""
        else
            execute="${SSH} ${host}"
        fi

        eval ${execute} zpool list -H -o name > ${myTMP}/${host}_pools
        pools=`cat ${myTMP}/${host}_pools`
        unset IFS
        for pool in $pools; do
            #is_mounted $pool || continue
            debug "Mapping disks for $pool"

            eval ${execute} zpool status ${pool} > ${myTMP}/${pool}_status
            echo "offline spares:" >> ${myTMP}/${pool}_status
            eval ${execute} cat /${pool}/zfs_tools/etc/spare-disks 2>/dev/null >> ${myTMP}/${pool}_status

            # Parse zpool status
            disk_start='false'
            vdev=

            while IFS='' read -r line || [[ -n "$line" ]]; do
                # Remove leading spaces
                line="${line#"${line%%[![:space:]]*}"}"

                if [ "$disk_start" != 'true' ]; then
                    if [[ "$line" == *"state: "* ]]; then
                        # Pool state
                        pool_state=`echo $line | $AWK -F ' ' '{print $2}'`
                        echo "pool["${pool}_status"]=\"${pool_state}\"" >> ${myTMP}/pools
                        if [ -z "$execute" ]; then
                            echo "pool["${pool}_host"]=\"$host\"" >> ${myTMP}/pools
                        fi
                        continue
                    fi
                    if [[ "$line" == *"NAME"*"STATE"*"READ"*"WRITE"*"CKSUM"* ]]; then
                        disk_start='true'
                        continue
                    fi
                    continue
                else
                    if [ "$line" == '' ]; then
                        continue
                    fi
                    if [[ "$line" == *"$pool"*"$pool_state"* ]];then
                        # Collect pool errors
                        IFS=' '
                        read junk1 junk2 pool_read_err pool_write_err pool_cksum_err <<< "$line"
                        IFS=''
                        continue
                    fi
                    if [[ "$line" == *"raidz"* || "$line" == *"mirror"* ]]; then
                        # Starting raidz or mirror vdev
                        vdev=`echo $line | $AWK -F ' ' '{print $1}'`
                        debug "Mapping $pool vdev $vdev"
                        continue
                    fi
                    if [[ "$line" == *"cache"* ]]; then
                        # Starting logs
                        debug "Mapping $pool cache"
                        vdev='cache'
                        continue
                    fi
                    if [[ "$line" == *"logs"* ]]; then
                        # Starting logs
                        debug "Mapping $pool logs"
                        vdev='log'
                        continue
                    fi
                    if [ "$line" == "offline spares:" ]; then
                        # Starting offline spares
                        debug "Mapping $pool offline spares"
                        vdev='cldSPARE'
                        continue
                    fi
                    if [[ "$line" == *"spares"* ]]; then
                        # Starting spares
                        debug "Mapping $pool spares"
                        vdev='hotSPARE'
                        continue
                    fi
                    if [ "${line:0:7}" == "errors:" ]; then
                        errors=`echo $line | $AWK -F 'errors: ' '{print $2}'`
                        continue
                    fi

                    disk_osname=
                    disk_state=
                    disk_read_err=
                    disk_write_err=
                    disk_cksum_err=

                    # By process of elimination this should be a disk line
                    if [ "$vdev" == 'cldSPARE' ]; then
                        disk_osname="$line"
                        disk_state=''
                    else
                        IFS=' '
                        read disk_osname disk_state disk_read_err disk_write_err disk_cksum_err <<< "$line"
                        IFS=''
                    fi

                    if [[ "$disk_osname" == *"d0p"* ]] || [[ "$disk_osname" == *"d0s"* ]]; then
                        disk_osname="${disk_osname::-2}"
                    fi

                    debug "Found: $disk_osname,$disk_state,$disk_read_err,$disk_write_err,$disk_cksum_err"

                    disk_wwn="${disk["${disk_osname}_wwn"]}"
                    if [ "${disk_wwn}" != "" ]; then
                        # Disk is known
                        echo "disk[${disk_wwn}_pool]=\"${pool}\"" >> ${myTMP}/disks
                        echo "disk[${disk_wwn}_vdev]=\"${vdev}\"" >> ${myTMP}/disks
                        if [[ "$vdev" != 'hotSPARE' && "$vdev" != 'coldSPARE' ]]; then
                            echo "disk[${disk_wwn}_readerr]=\"${disk_read_err}\"" >> ${myTMP}/disks
                            echo "disk[${disk_wwn}_writeerr]=\"${disk_write_err}\"" >> ${myTMP}/disks
                            echo "disk[${disk_wwn}_cksumerr]=\"${disk_cksum_err}\"" >> ${myTMP}/disks
                        fi
                        echo "disk[${disk_wwn}_status]=\"${disk_state}\"" >> ${myTMP}/disks

                        expander="${disk["${disk_wwn}_expander"]}"
                        if [ "${expander}" != "" ]; then
                            # Add info at expander maping
                            slot="${disk["${disk_wwn}_slot"]}"
                            echo "expander[${expander}_pool_${slot}]=\"${pool}\"" >> ${myTMP}/expanders
                        fi
                    fi

                fi # $disk_start

            done < ${myTMP}/${pool}_status

        done # for pool

    done # for host

}


