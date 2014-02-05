#! /bin/bash -x

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

now=`date +%F_%H:%M:%S%z`

if [ "x$zfs_logfile" != "x" ]; then
    logfile="$zfs_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$zfs_report" != "x" ]; then
    report_name="$zfs_report"
else
    report_name="$default_report_name"
fi


pools="$(pools)"

for pool in $pools; do

    jobfolder="/${pool}/zfs_tools/etc/backup/jobs/zfs"

    backupjobs=`ls -1 ${jobsfolder}/`

    for job in $backupjobs; do
        notice "Launching zfs backup job $job"
        zfsjob "$jobfolder" "$job" &
    done
    

done # for pool    



zfsjob () {

    local jobfolder="$1"
    local job="$2"

    source ${jobfolder}/${job}

    # Determine if we've backed up before

        # Create job accounting folder

    # Create snapshot for this increment


    



}

# Perform local snapshots

zfs snapshot -r ${staging_folder:1}@${tools_snapshot_name}${now}

backupjobs=`ls -1 $TOOLS_ROOT/backup/jobs/ec2/`

for job in $backupjobs; do

    source $TOOLS_ROOT/backup/jobs/ec2/${job}

    # Find previous sucessful snapshot

    snapshots=`ssh root@${instance_dns} zfs list -t snapshot -H -o name -s creation | \
                $grep "^${target_folder}@" | \
                $grep "${tools_snapshot_name}"`

    # Determine if there is enough space on the pool for the increment.
    # If not expand the pool first.

    if [ "$snapshots" == "" ]; then
        # This must be our first sync
        required=`zfs list -H ${staging_folder:1} | $cut -f 2`
        requiredunit=${required#${required%?}}
        # Strip the units
        required="${required%?}"
        if [ "$requiredunit" == "T" ]; then
            # Convert to Gigabytes
            required=$(( required * 1024 ))
        fi  
    fi

    targetfree=`ssh root@${instance_dns} zfs list -H $ec2_zfspool | $cut -f 3`
    targetunit=${targetfree#${targetfree%?}}
    # Strip the units
    targetfree="${targetfree%?}"
    if [ "$targetunit" == "T" ]; then
        # Convert to Gigabytes
        targetfree=$(( targetfree * 1024 ))
    fi

    # TODO: Complete calculation of required space and call grow-zfs-pool if necessary.


    # Sync snapshots

    if [ "$snapshots" == "" ]; then
        # This must be our first sync
        # We will push to a file on the instance storage then 'zfs receive' it to the pool
        if [ "$bbcp" != "" ]; then
            # bbcp does not encrypt the traffic so we will pipe trough opensll before
            # handing data off to bbcp.   We will decrypt on the receive end with openssl as well.
            
            #Generate an encryption key
            bbcp_key="/tmp/zfs.${tools_snapshot_name}key_${now}"
            pwgen -s 63 1 > $bbcp_key

            # Send the key file
            scp $bbcp_key root@${instance_dns}:$bbcp_key

            # Create the named pipe
            pipe="/tmp/zfs.${tools_snapshot_name}pipe_${now}"
            mkfifo $pipe

            # Start the zfs send
            # preload an error state incase something else fails and zfs send 
            # is still trying send
            # We collect our own md5sum, bbcp seems to hang at the end if we ask it to generate one

            csfile="/tmp/zfs.${tools_snapshot_name}cksum_${now}"
            send_result=999
            result_file="/tmp/zfs.${tools_snapshot_name}send_result_${now}"
            ( zfs send -R ${staging_folder:1}@${tools_snapshot_name}${now} | \
            mbuffer -q -s 128k -m 128M 2>/dev/null | \
            openssl aes-256-cbc -pass file:$bbcp_key | tee $pipe | \
            md5sum -b > $csfile ; send_result=$? ; \
            echo "send_result=${send_result}" > $result_file ) &

            # Accellorate the copy with bbcp

            if [ "$inst_store_staging" == "true" ]; then
                target_file="/data/instancestore/zfs.${tools_snapshot_name}${now}"
                time $bbcp -s $bbcp_streams -V -P 301 -E md5 -E %md5 -N i $pipe root@${instance_dns}:${target_file} 
                bbcp_result=$?
                # Remove the pipe
                rm -f $pipe

                # Wait 2 seconds to be sure the zfs send process exits and collect its exit code
                sleep 2
                if [ -f $result_file ]; then
                    . $result_file
                fi

                if [ $bbcp_result -eq 0 ] && [ $send_result -eq 0 ]; then

                    # Processes report success
                    # Get the md5sum of the staging file
                    echo -n "Calculating md5sum on target staging file..."
                    cstarget=`ssh root@${instance_dns} "md5sum -b ${target_file} | $cut -d ' ' -f1 " `
                    echo "Done."
                    cssource=`cat $csfile | $cut -d " " -f1`

                    if [ "$cssource" == "$cstarget" ]; then

                        # create target_folder
                        ssh root@${instance_dns} "zfs create -p ${target_folder}"

                        # Target is clean, we can now zfs receive the load
                        echo -n "Importing staging file via zfs receive..."
                        time ssh root@${instance_dns} "openssl aes-256-cbc -d -pass file:$bbcp_key \
                            -in ${target_file} | \
                            zfs receive -F -vu -o canmount=off ${target_folder}"
                        receive_result=$?
                        echo "Done."

                        if [ $receive_result -ne 0 ]; then
                            zfs destroy -r ${staging_folder:1}@${tools_snapshot_name}${now}
                            die "zfs receive failed with result code: $receive_result"
                        else
                            result=0
                        fi

                    else 

                        zfs destroy -r ${staging_folder:1}@${tools_snapshot_name}${now}
                        die "Target md5sum $cstarget does not match source md5sum $cssource."

                    fi

                else

                    # Something failed
                    if [ $bbcp_result -ne 0 ]; then
                        zfs destroy -r ${staging_folder:1}@${tools_snapshot_name}${now}
                        die "bbcp failed with result code: $bbcp_result"
                    fi
                    if [ $send_result -ne 0 ]; then
                        zfs destroy -r ${staging_folder:1}@${tools_snapshot_name}${now}
                        die "zfs send failed with result code: $send_result"
                    fi
                fi
                    
 
            else
                # Pipe directly to zfs receive on the target

                # Create the named pipe wit the same name on the target
                ssh root@${instance_dns} "mkfifo $pipe"

                # create target_folder
                ssh root@${instance_dns} "zfs create -p ${target_folder}"
                
                # start the zfs receive 
                ( ssh root@${instance_dns} "cat $pipe | \
                    openssl aes-256-cbc -d -pass file:$bbcp_key \
                    mbuffer -q -s 128k -m 128M 2>/dev/null | \
                    zfs receive -F -vu -o canmount=off ${target_folder} ; receive_result=$? )" ) & 
                time $bbcp -s $bbcp_streams -V -P 300 -e -E %md5=${csfile} -N io $pipe $pipe 
                bbcp_result=$?
                # Remove the pipe
                rm -f $pipe

            fi # inst_store_staging

        else

            if [ "$inst_store_staging" == "true" ]; then
                target_file="/data/instancestore/zfs.${tools_snapshot_name}${now}"
                csfile="/tmp/zfs.${tools_snapshot_name}cksum_${now}"
                
                time zfs send -R ${staging_folder:1}@${tools_snapshot_name}${now} | \
                ssh root@${instance_dns} "mbuffer -q -s 128k -m 128M 2>/dev/null \
                    > ${target_file} " ; result=$?

                if [ $result -ne 0 ]; then
                    zfs destroy -r ${staging_folder:1}@${tools_snapshot_name}${now}
                    die "Failed to push to instance storage"
                fi

                ssh root@${instance_dns} "zfs create -p ${target_folder}" && \
                ssh root@${instance_dns} "zfs receive -F -vu -o canmount=off ${target_folder} < ${target_file}"
                result=$?

                if [ $result -ne 0 ]; then
                    zfs destroy -r ${staging_folder:1}@${tools_snapshot_name}${now}
                    die "Failed to zfs receive from instance store.  Manual intervention necessary."
                fi
            else
                # Simplest of methods, but has many drawbacks when data becomes sizeable
                # Any type of error will require manual intervention to correct
                ssh root@${instance_dns} "zfs create -p ${target_folder}" && \
                zfs send -R ${staging_folder:1}@${tools_snapshot_name}${now} | \
                ssh root@${instance_dns} "mbuffer -q -s 128k -m 128M 2>/dev/null \
                    zfs receive -F -vu ${target_folder}"
                result=$?

                if [ $result -ne 0 ]; then
                    zfs destroy -r ${staging_folder:1}@${tools_snapshot_name}${now}
                    die "Failed to zfs send/receive.  Manual intervention necessary."
                fi

            fi # inst_store_staging

        fi # bbcp

    else
        
        # TODO:  Process incremental send.

        # Verify last send was succesful.  If not roll back if necessary.
        echo " Process incremental "
    
    
    fi


    if [ $result -ne 0 ]; then
        echo "aws-backup@${now}" > ${TOOLS_ROOT}/backup/jobs/ec2job.failed
        
    else
        echo "aws-backup@${now}" > ${TOOLS_ROOT}/backup/jobs/ec2job.success
        # TODO: Remove previous snapshot(s)

        
    fi

done # job




# Shutdown EC2 instance

if [ "$DEBUG" != "true" ]; then
    $TOOLS_ROOT/stop-instance.sh
fi
