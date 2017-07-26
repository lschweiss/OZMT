#! /bin/bash 

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

if [ ! -f ${myTMP}/active_disks ]; then
    notice "active disks have not been collected. Collecting now."
    ./locate-inuse-disks.sh
fi


#   disks=`cat inuse-disks`
#   
#   
#   # Remove inuse disks from smartmon list
#   
#   cp smartmon-ux_-zd.txt /tmp/disk-reference.txt
#   
#   for disk in "$disks"; do
#       cat /tmp/disk-reference.txt | grep -v "$disk" > /tmp/disk-reference.txt.new
#       mv /tmp/disk-reference.txt.new /tmp/disk-reference.txt
#   done
#   
#   mv /tmp/disk-reference.txt disk-reference.txt
#   
#   # Collect enclosure ids
#   
#   rm enclosure-ids
#   
#   cat smartmon-ux_-zd.txt |grep "/dev/es/"|grep -v "Discovered" >> enclosures
#   
#   while IFS='' read -r line || [[ -n "$line" ]]; do
#       echo "${line:21:12}\t${line:70:16}" >> enclosures2
#   done < enclosures
#   
#   unset IFS
#   
#   cat enclosures2 | sort -u > enclosure-ids
#   rm enclosures enclosures2






# Break down each enclosure
enclnum=0

if [ ! -f ${myTMP}/${HOSTNAME}.smartmon-ux_-E+.txt ]; then
    notice "Generation enclosure status listing"
    /sbin/smartmon-ux -E+ > ${myTMP}/${HOSTNAME}.smartmon-ux_-E+.txt
fi

cat ${myTMP}/${HOSTNAME}.smartmon-ux_-E+.txt |grep 'WWN\|ArrayDevice\|Enclosure Services' > ${myTMP}/enclosures

while IFS='' read -r line || [[ -n "$line" ]]; do
    #echo "    $line"

    echo $line|grep -q "Enclosure Services"
    if [ $? -eq 0 ]; then
        # new enclosure
        if [ $enclnum -ne 0 ]; then
            # Output what we know
            echo "${wwn}\t${encl_id}\t${devnum}\t${vendor}\t${model}\t${ses}" >> ${myTMP}/enclosures2
        fi
        ses=`echo $line|awk -F ' on ' '{print $2}'|awk -F ' ' '{print $1}'`
        id_line=`cat ${myTMP}/${HOSTNAME}.smartmon-ux_-zd.txt |grep "$ses"|grep -v "Discovered"`
        encl_id="${id_line:70:16}"
        #echo "NEW ENCLOSURE $enclnum"
        enclnum=$(( enclnum + 1 ))
        devnum=0
        continue
    fi
    echo $line|grep -q "ArrayDevice"
    if [ $? -eq 0 ]; then 
        # Count bays
        devnum=$(( devnum + 1 ))
        #echo "Dev $devnum"
        continue
    fi
    echo $line|grep -q "WWN"
    if [ $? -eq 0 ]; then
        # Collect vendor, model and wwn
        vendor="${line:0:9}"
        model="${line:9:16}"
        wwn="${line:30:23}"
        #echo "FOUND WWN"
        continue
    fi    
done < ${myTMP}/enclosures
# Output the last enclosure
echo "${wwn}\t${encl_id}\t${devnum}\t${vendor}\t${model}\t${ses}" >> ${myTMP}/enclosures2

cat ${myTMP}/enclosures2 | sort -u > ${myTMP}/enclosure-data
rm -f ${myTMP}/enclosures ${myTMP}/enclosures2

# find unfilled slots
wwns=`cat ${myTMP}/enclosure-data| cut -f1 | sort -u`

# A/a Enable/disable visual array rebuild abort indicator
# B/b Enable/disable visual array failed indicator
# C/c Enable/disable visual array critical indicator
# F/f Enable/disable visual fault indicator
# H/h Enable/disable visual spare indicator
# I/i Enable/disable visual Idntify indicator
# K/k Enable/disable visual consistency check indicator
# P/p Enable/disable visual predictive failure indicator
# R/r Enable/disable visual rebuild indicator
# S/s Enable/disable visual remove indicator
# V/v Enable/disable visual request reserved indicator

offs='f'

rm -f ${myTMP}/disk_to_location

for wwn in $wwns; do
    # Collect enclosure data
    encl_id=`cat ${myTMP}/enclosure-data|grep "$wwn"|head -1|cut -f2`
    if [ "$encl_id" == '' ]; then
        # Lets try the last in the list
        encl_id=`cat ${myTMP}/enclosure-data|grep "$wwn"|tail -1|cut -f2`
    fi
    devnum=`cat ${myTMP}/enclosure-data|grep "$wwn"|head -1|cut -f3`
    vendor=`cat ${myTMP}/enclosure-data|grep "$wwn"|head -1|cut -f4`
    model=`cat ${myTMP}/enclosure-data|grep "$wwn"|head -1|cut -f5`
    ses=`cat ${myTMP}/enclosure-data|grep "$wwn"|head -1|cut -f6`
    echo "$wwn: $encl_id $vendor $model"
    
    # Check each device and set the lights appropriately

    dev=0


    while [ $dev -lt $devnum ]; do
        # Collect os name
        echo -n "$dev "
        diskline="$(cat ${myTMP}/${HOSTNAME}.smartmon-ux_-zd.txt | awk "\$9 == \"$encl_id\"" | awk "\$10 == \"$dev\""|tail -1)"
        if [ "$diskline" == '' ]; then
            echo -n "NODISK "
            if [ "$DEBUG" == 'true' ]; then
                echo "\n$diskline"
            fi
            diskosname=''
            diskserial=''
        else
            diskosname="$( echo $diskline | awk -F '/dev/rdsk/' '{print $2}'|awk -F 's2' '{print $1}')"
            diskvendor=`echo $diskline|awk -F ' ' '{print $4}'`
            diskmodel=`echo $diskline|awk -F ' ' '{print $5}'`
            diskserial=`echo $diskline|awk -F ' ' '{print $11}'`
            diskfirmware=`echo $diskline|awk -F ' ' '{print $6}'`
        fi
        if [ "$diskserial" = '' ]; then
            echo "NO SERIAL"
            if [ "$DEBUG" != 'true' ]; then
                if [ "$light_empty_bays" == 'true' ]; then
                    /opt/ozmt/3rdparty/setLEDs.sh $dev $dev F $ses 1> /dev/null
                else
                    for off in $offs; do
                        /opt/ozmt/3rdparty/setLEDs.sh $dev $dev $off $ses 1> /dev/null
                    done
                fi
            fi
            dev=$(( dev + 1 ))
            continue
        else
            echo "${diskosname}: $diskserial"
        fi
        cat ${myTMP}/active_disks | grep -q "$diskserial"
        if [ $? -eq 0 ]; then
            # Disk is in use.  Turn off lights
            echo " INUSE $diskvendor $diskmodel $diskserial"
            if [ "$DEBUG" != 'true' ]; then
                for off in $offs; do
                    /opt/ozmt/3rdparty/setLEDs.sh $dev $dev $off $ses 1> /dev/null
                done
            fi
        else
            echo " FAULT $diskvendor $diskmodel $diskserial"
            if [ "$DEBUG" != 'true' ]; then
                /opt/ozmt/3rdparty/setLEDs.sh $dev $dev F $ses 1> /dev/null
            fi
        fi
        dev=$(( dev + 1 ))
        echo "${diskosname}\t${diskserial}\t${wwn}\t${dev}\t${diskvendor}\t${diskmodel}\t${diskfirmware}" >> ${myTMP}/disk_to_location
    done 
    echo;echo
done
    




