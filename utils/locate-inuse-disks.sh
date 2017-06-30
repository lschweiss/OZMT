#! /bin/bash


# TODO: Convert to using sg3_utils

# Known tools thus far

# Collect number of bays, jbod name, wwn
# sg_ses -p ed /dev/es/ses7

# Gather SAS addresses:
# sg_inq -p sp /dev/rdsk/c0t5000C500857238F3d0s0

# Gather connected disks via SAS address
# sg_ses -I 0,19 -p aes /dev/es/ses7

# Gather error counts
# iostat -En

# References:
#
# https://meteo.unican.es/trac/blog/DiskLocationOpenindiana



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

rm -f ${myTMP}/active_disks ${myTMP}/faulted_disks

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
    ${execute} /sbin/smartmon-ux -zd > ${myTMP}/${host}.smartmon-ux_-zd.txt
    pools=`${execute} zpool list -H -o name`
    for pool in $pools; do
        debug "Mapping disks for $pool"
        ${execute} zpool status ${pool} | $GREP "ONLINE\|INUSE\|AVAIL" | $GREP "c.t" | \
            $AWK -F ' ' '{print $1}' > ${myTMP}/${pool}_active_disks
        ${execute} zpool status ${pool} | $GREP "FAULT\|REMOVED" | $GREP "c.t" | \
            $AWK -F ' ' '{print $1}' > ${myTMP}/${pool}_faulted_disks
        ${execute} cat /${pool}/zfs_tools/etc/spare-disks >> ${myTMP}/${pool}_active_disks 2> /dev/null

        # TODO: Catch missing or repairing disk lines. No examples were available at the time of coding




        # Collect serial #s
        rm -f ${myTMP}/${host}.${pool}.disk-osname_to_serial
        active_disks=`cat ${myTMP}/${pool}_active_disks`
        for disk in $active_disks; do
            echo -n "${disk}: "
            serial="$(cat ${myTMP}/${host}.smartmon-ux_-zd.txt | \
                        $GREP "$disk" | $GREP "Discovered" | \
                        $AWK -F '"' '{print $2}')"
            echo $serial | tee -a ${myTMP}/active_disks
            echo "${disk}\t${serial}" >> ${myTMP}/${pool}_disk-osname_to_serial
        done
        faulted_disks=`cat ${myTMP}/${pool}_faulted_disks`
        for disk in $faulted_disks; do
            echo -n "${disk}: "
            serial="$(cat ${myTMP}/${host}.smartmon-ux_-zd.txt | \
                        $GREP "$disk" | $GREP "Discovered" | \
                        $AWK -F '"' '{print $2}')"
            echo $serial | tee -a ${myTMP}/faulted_disks
            echo "${disk}\t${serial}" >> ${myTMP}/${pool}_disk-osname_to_serial
        done
    done

done
            
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


