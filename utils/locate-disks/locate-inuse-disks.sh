#! /bin/bash


# TODO: Convert to using sg3_utils

# Known tools thus far

# Collect vendor, name, firmware revision
# sg_inq -p sdp {device_path}| head 1

# Collect number of bays, jbod name, wwn
# sg_ses -p ed /dev/es/ses7
# sg_ses -p ed /dev/bsg/{device}

# Gather SAS addresses:
# sg_inq -p sp /dev/rdsk/c0t5000C500857238F3d0s0
# sg_inq -p di /dev/rdsk/c0t5000C500857238F3d0s0
#    SAS addresses on lines like:
#       [0x5000c50093e3be85]
#   

# Gather connected disks via SAS address
# sg_ses -I 0,19 -p aes /dev/es/ses7
#   "SAS address:" will match 'sg_inq -p di' of the disk

# Gather error counts
# iostat -En

# Gather controller connectivity
# sas2ircu


# References:
#
# https://meteo.unican.es/trac/blog/DiskLocationOpenindiana
# http://www.avagotech.com/docs-and-downloads/host-bus-adapters/host-bus-adapters-common-files/sas_sata_6g_p20/SAS2IRCU_P20.zip
# https://stackoverflow.com/questions/555427/map-sd-sdd-names-to-solaris-disk-names
# https://openindiana.org/pipermail/openindiana-discuss/2017-May/020729.html  <--- Maping "Log info received for target" messages
# https://www.redhat.com/archives/dm-devel/2008-March/msg00102.html

# sd mapping:
# paste -d= <(iostat -x | awk 'NR>2{print $1}') <(iostat -nx | awk 'NR>2{print "/dev/dsk/"$11}')



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

myTMP=${TMP}/disk-map
MKDIR $myTMP

source ${TOOLS_ROOT}/utils/locate-disks/locate-functions.sh

if [ ! -f $myTMP/disks ]; then
    collect_disk_info
fi

if [ ! -f $myTMP/expanders ]; then
    collect_expander_info
fi

source $myTMP/disks
source $myTMP/expanders


rm -f ${myTMP}/active_disks ${myTMP}/faulted_disks ${myTMP}/pools

if [ "$cluster_hosts" == '' ]; then
    cluster_hosts="$HOSTNAME"
fi


# Collect active disks in the cluster
for host in $cluster_hosts; do
    notice "Collecting disk mappings for $host"
    if [ "$host" == "$HOSTNAME" ]; then
        # Excute locally
        execute=""
    else
        execute="${SSH} ${host}"
    fi
#    ${execute} /sbin/smartmon-ux -zd > ${myTMP}/${host}.smartmon-ux_-zd.txt
    pools=`${execute} zpool list -H -o name`
    for pool in $pools; do
        debug "Mapping disks for $pool"
        
        ${execute} zpool status ${pool} > ${myTMP}/${pool}_status
    
#        ${execute} zpool status ${pool} | $GREP "ONLINE\|INUSE\|AVAIL" | $GREP "c.t" | \
#            $AWK -F ' ' '{print $1}' > ${myTMP}/${pool}_active_disks
#        ${execute} zpool status ${pool} | $GREP "FAULT\|REMOVED" | $GREP "c.t" | \
#            $AWK -F ' ' '{print $1}' > ${myTMP}/${pool}_faulted_disks
#        ${execute} cat /${pool}/zfs_tools/etc/spare-disks >> ${myTMP}/${pool}_active_disks 2> /dev/null

        # TODO: Catch missing or repairing disk lines. No examples were available at the time of coding


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
                if [[ "$line" == *"logs"* ]]; then
                    # Starting logs
                    debug "Mapping $pool logs"
                    vdev='log'
                    continue
                fi
                if [[ "$line" == *"spares"* ]]; then
                    # Starting spares
                    debug "Mapping $pool spares"
                    vdev='spare'
                    continue
                fi
                if [ "${line:0:7}" == "errors:" ]; then
                    errors=`echo $line | $AWK -F 'errors: ' '{print $2}'`
                    continue
                fi
                
                # By process of elimination this should be a disk line
                IFS=' '
                read disk_osname disk_state disk_read_err disk_write_err disk_cksum_err <<< "$line"
                IFS=''
    

                debug "Found: $disk_osname,$disk_state,$disk_read_err,$disk_write_err,$disk_cksum_err"

                disk_wwn="${disk["${disk_osname}_wwn"]}"
                if [ "${disk_wwn}" != "" ]; then
                    # Disk is known
                    debug "Disk; $disk_osname: $disk_wwn"
                    echo "disk[${disk_wwn}_pool]=\"${pool}\"" >> ${myTMP}/disks
                    echo "disk[${disk_wwn}_vdev]=\"${vdev}\"" >> ${myTMP}/disks
                    echo "disk[${disk_wwn}_status]=\"${disk_state}\"" >> ${myTMP}/disks
                    if [ "$vdev" != 'spare' ]; then
                        echo "disk[${disk_wwn}_readerr]=\"${disk_read_err}\"" >> ${myTMP}/disks
                        echo "disk[${disk_wwn}_writeerr]=\"${disk_write_err}\"" >> ${myTMP}/disks
                        echo "disk[${disk_wwn}_cksumerr]=\"${disk_cksum_err}\"" >> ${myTMP}/disks
                    fi

                    expander="${disk["${disk_wwn}_expander"]}"
                    if [ "${expander}" != "" ]; then
                        # Add info at expander maping
                        slot="${disk["${disk_wwn}_slot"]}"
                        echo "expander[${expander}_pool_${slot}]=\"${pool}\"" >> ${myTMP}/expanders  
                    fi
                fi
            fi # $disk_start
            
        done < ${myTMP}/${pool}_status


#        # Collect serial #s
#        rm -f ${myTMP}/${host}.${pool}.disk-osname_to_serial
#        active_disks=`cat ${myTMP}/${pool}_active_disks`
#        for disk in $active_disks; do
#            echo -n "${disk}: "
#            serial="$(cat ${myTMP}/${host}.smartmon-ux_-zd.txt | \
#                        $GREP "$disk" | $GREP "Discovered" | \
#                        $AWK -F '"' '{print $2}')"
#            echo $serial | tee -a ${myTMP}/active_disks
#            echo "${disk}\t${serial}" >> ${myTMP}/${pool}_disk-osname_to_serial
#        done
#        faulted_disks=`cat ${myTMP}/${pool}_faulted_disks`
#        for disk in $faulted_disks; do
#            echo -n "${disk}: "
#            serial="$(cat ${myTMP}/${host}.smartmon-ux_-zd.txt | \
#                        $GREP "$disk" | $GREP "Discovered" | \
#                        $AWK -F '"' '{print $2}')"
#            echo $serial | tee -a ${myTMP}/faulted_disks
#            echo "${disk}\t${serial}" >> ${myTMP}/${pool}_disk-osname_to_serial
#        done

    done # for pool

done # for host
            

exit

# Find pools that are not active, but online

debug "Looking for offline pools"

zpool import > ${myTMP}/import_pools


offline_pools=''

while IFS='' read -r line || [[ -n "$line" ]]; do
    if [ "${line:0:8}" == "   pool:" ]; then
        # New pool
        pool="${line:9}"
        skip='false'
        continue
    fi
    if [ "$skip" == 'true' ]; then
        # Look for the next pool
        continue
    fi
    if [ "${line:0:8}" == "  state:" ]; then
        # Collec state
        state="${line:9}"
        if [ "$state" == "UNAVAIL" ]; then
            # Pool is active on another host
            skip='true'
            continue
        fi
        if [ "$state" == "ONLINE" ]; then
            notice "Collecting disk mappings for offline pool $pool"
            rm -f ${myTMP}/${pool}_active_disks
            offline_pools="${pool} ${offline_pools}"
        fi
            
    fi
    # Look for associated disks
    echo "$line" | $GREP -q "c.t"
    if [ $? -eq 0 ]; then
        echo "$line" | $AWK -F ' ' '{print $1}' >> ${myTMP}/${pool}_active_disks
    fi

done < ${myTMP}/import_pools

unset IFS


# Collect serial #s

for pool in $offline_pools; do
    rm -f ${myTMP}/${pool}.disk-osname_to_serial
    active_disks=`cat ${myTMP}/${pool}_active_disks`
    for disk in $active_disks; do
        echo -n "${disk}: "
        serial="$(cat ${myTMP}/${HOSTNAME}.smartmon-ux_-zd.txt | \
                    $GREP "$disk" | $GREP "Discovered" | \
                    $AWK -F '"' '{print $2}')"
        echo $serial | tee -a ${myTMP}/active_disks
        echo "${disk}\t${serial}" >> ${myTMP}/${pool}_disk-osname_to_serial
    done
done


