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
    statfolder="/${pool}/zfs_tools/etc/backup/stat/zfs"

    backupjobs=`ls -1 ${jobsfolder}/`

    for job in $backupjobs; do
        notice "Launching zfs backup job $job"
        zfsjob "$jobfolder" "$job" &
    done
    

done # for pool    


snap_list () {

    # Echo the snapshot between the first and last snapshot provided.
    # Will not include the first snapshot unless "origin" is specified for the first
    # in which case the first snapshot of the folder will be included.

    local zfs_folder="$1"
    local first_snap="${zfs_folder}/${2}"
    local last_snap="${zfs_folder}/${3}"
    local snaplist=

    snaplist=`zfs list -t snapshot -H -o name -s creation | \
        $grep "^${zfs_folder}@"`

    if [ "$first_snap" == "${zfs_folder}@origin" ]; then  
        first_snap=`echo $snaplist|head -1`
        echo $first_snap
    fi
    
    zfs list -t snapshot -H -o name -s creation | \
        $grep "^${zfs_folder}@" | \
        $awk "/${first_snap}/{a=1;next}/${last_snap}/{a=0}a"
}



zfs_send () {

    # Must support multiple options
    #   Local source and destination
    #   Remote destination
    #     Use bbcp
    #     Encrypt traffic
    #     Compress traffic
    #   Use mbuffer (local or remote)
    #   Replication stream
    #   Property reset
    #   Flat file target
    #   SHA256 sum

    local result=
    local verify='true'
    local remote_ssh=
    local target_fifo=
    local target_fifos=
    local source_fifo=
    local local_fifos=

    die () {
        error "$1"
        return 1
    }

    # show function usage
    show_usage() {
        echo
        echo "Usage: $0 -s {source_zfs_folder} -t {target_zfs_folder}"
        echo "  [-f {first_snap}]   First snapshot.  Defaults to 'origin'"
        echo "  [-l {last_snap}]    Last snapshot.  Defaults to latest snapshot."
        echo "  [-r host]           Send to a remote host.  Defaults to via SSH."
        echo "  [-m]                Use mbuffer."
        echo "  [-b n]              Use BBCP, n connections.  "
        echo "     [-e]             Encrypt traffic w/ openssl.  Only for BBCP."
        echo "  [-g n]              Compress with gzip level n."
        echo "  [-z n]              Compress with LZ4.  Specify 1 for standard LZ4.  Specify 4 - 9 for LZ4HC compression level."
        echo "  [-R]                Use a replication stream"
        echo "  [-p {prop_string} ] Reset properties on target"
        echo "  [-F]                Target is a flat file.  No zfs receive will be used."
        echo "  [-k {file} ]        Generate a md5 sum.  Store it in {file}."
        exit 1
    }
    
    # Minimum number of arguments needed by this program
    local MIN_ARGS=4
    
    if [ "$#" -lt "$MIN_ARGS" ]; then
        show_usage
        return 1
    fi

    local source_folder=
    local target_folder=
    local target_pool=
    local first_snap=
    local last_snap=
    local remote_host=
    local mbuffer_use='false'
    local bbcp_connections=0
    local bbcp_encrypt='false'
    local gzip=0
    local lz4=0
    local replicate='false'
    local target_prop=
    local flat_file='false'
    local gen_chksum=
    
    while getopts s:t:f:l:r:mbeg:zRpFk: opt; do
        case $opt in
            s)  # Source ZFS folder
                source_folder="$OPTARG"
                debug "zfs_send: Source folder: $source_folder"
                ;;
            t)  # Target ZFS folder or flat file
                target_folder="$OPTARG"
                debug "zfs_send: Target folder: $target_folder"
                ;;
            f)  # First snapshot
                first_snap="$OPTARG"
                debug "zfs_send: first_snap:    $first_snap"
                ;;
            l)  # Last snapshot
                last_snap="$OPTARG"
                debug "zfs_send: last_snap:     $last_snap"
                ;;
            r)  # Remote host
                remote_host="$OPTARG"
                debug "zfs_send: Remote host:   $remote_host"
                ;;
            m)  # Use mbuffer
                mbuffer_use='true'
                debug "zfs_send: Using mbuffer"
                ;;
            b)  # Use BBCP
                bbcp_connections="$OPTARG"
                debug "zfs_send: Using BBCP, $bbcp_connecitons connections."
                ;;
            e)  # Encrypt BBCP traffic
                bbcp_encrypt='true'
                debug "zfs_send: Encrypting BBCP traffic"
                ;;
            g)  # Compress with gzip
                gzip="$OPTARG"
                debug "zfs_send: Gzip compression level $gzip"
                ;;
            z)  # Compress with LZ4
                lz4="$OPTARG"
                case $lz4 in
                    1) 
                        debug "zfs_send: Using LZ4 standard" ;;
                    [4-9])
                        debug "zfs_send: Using LZ4HC level $lz4" ;;
                    *)
                        error "zfs_send: Invalid LZ4 specified" ;;
                        return 1
                esac
                ;;
            R)  # Use a replication stream
                replicate='true'
                debug "zfs_send: Using a replication stream."
                ;;
            p)  # Reset properties on target
                target_prop="$OPTARG"
                debug "zfs_send: resetting target properties to: $target_prop"
                ;;
            F)  # Target is a flat file
                flat_file='true'
                debug "zfs_send: Flat file target"
                ;;
            k)  # Generate a md5 checksum
                gen_chksum="$OPTARG"
                debug "zfs_send: Generate MD5 sum in file $gen_chksum"
                ;;                
            ?)  # Show program usage and exit
                show_usage
                return 1
                ;;
            :)  # Mandatory arguments not specified
                echo "Option -$OPTARG requires an argument."
                return 1
                ;;
        esac
    done

    ###
    #
    # Verify all input is valid
    #
    ###

    if [ "$source_folder" == "" ]; then
        error "zfs_send: no source folder specified"
        return 1
    fi

    if [ "$target_folder" == "" ]; then
        error "zfs_send: not target specified"
        return 1
    fi


    if [ "$first_snap" == "" ]; then
        first_snap='origin'
        debug "zfs_send: first_snap no specified, set to origin"
    fi

    if [ "$flat_file" == 'false' ]; then
        # Split into pool / folder
        target_pool=`echo $target_folder | awk -F "/" '{print $1}'`
    fi

    ###
    # Verify remote host
    ###


    if [ "$remote_host" != "" ]; then
        $timeout 30s $ssh root@${remote_host} sleep 1
        result=$?
        if [ $result -ne 0 ]; then
            error "zfs_send: Cannot connect to remote host at root@${remote_host}"
            verify='fail'
        else
            debug "zfs_send: Remote host connection verified."
        fi
    else
        if [ "$bbcp_connections" != "0" ]; then
            error "zfs_send: Cannot use bbcp for local jobs"
        fi
    fi

    ###
    # Verify source folder
    ###
    
    zfs list $source_folder &> /dev/null
    result=$?
    if [ $result -ne 0 ]; then
        error "zfs_send: Source zfs folder $source_folder not found."
        verify='fail'
    fi

    ###
    # Verify target folder / file
    ##

    if [ "$remote_host" == "" ]; then
        # Local test
        if [ "$flat_file" == 'false' ]; then
            if [ "$replicate" == 'false' ]; then
                zfs list $target_folder &> /dev/null
                result=$?
                if [ $result -ne 0 ]; then
                    error "zfs_send: Replicate not specified however target folder $target_folder does not exist."
                    verify='fail'
                fi
            else
                # Verify pool exists
                zfs list $target_pool &> /dev/null
                result=$?
                if [ $result -ne 0 ]; then
                    error "zfs_send: Replicate specified however target pool $target_pool does not exist."
                    verify='fail'
                fi
            fi
        else # Flat file
            touch $target_folder &> /dev/null
            result=$?
            if [ $result -ne 0 ]; then
                error "zfs_send: Cannot create flat file $target_folder"
                verify='fail'
            else
                rm $target_folder
            fi
        fi
    else
        # Remote test
        remote_ssh="$ssh root@$remote_host"
        if [ "$flat_file" == 'false' ]; then
            if [ "$replicate" == 'false' ]; then
                $timeout 2m $remote_ssh zfs list $target_folder &> /dev/null
                result=$?
                if [ $result -ne 0 ]; then
                    error "zfs_send: Replicate not specified however target folder $target_folder does not exist on host $remote_host"
                    verify='fail'
                fi
            else
                # Verify pool exists
                $timeout 2m $ssh $remote_ssh zfs list $target_pool &> /dev/null
                result=$?
                if [ $result -ne 0 ]; then
                    error "zfs_send: Replicate specified however target pool $target_pool does not exist on host $remote_host"
                    verify='fail'
                fi
            fi
        else # Flat file
            $timeout 30s $remote_ssh touch $target_folder &> /dev/null
            result=$?
            if [ $result -ne 0 ]; then
                error "zfs_send: Cannot create flat file $target_folder on host $remote_host"
                verify='fail'
            else
                $remote_ssh rm $target_folder
            fi
        fi
    fi
    
    if [ "$verify" == 'fail' ]; then
        die "zfs_send: Input validation failed.  Aborting."
    fi    

    ###
    #
    # Setup named pipes for each transport type
    #
    ###

    remote_fifo () {
        $timeout 1m $remote_ssh mkfifo $1 || \
            die "zfs_send: Could not setup remote fifo $1 on host $remote_host"
        target_fifos="$1 $target_fifos"
    }

    local_fifo () {
        mkfifo $1 || \
            die "zfs_send: Could not setup fifo $1"
        local_fifos="$1 $local_fifos"
    }
    

    #TODO: Build from target to source connecting fifos as we build
    
    ##
    # mbuffer
    ##


    if [ "$mbuffer_use" == 'true' ]; then
        # Target end
        if [ [ "$flat_file" == 'false' ] && [ "$remote_host" != "" ] ]; then
                remote_fifo /tmp/zfs_target.mbuffer.in.$$ 
                remote_fifo /tmp/zfs_target.mbuffer.out.$$
        fi
        # Source end
        local /tmp/zfs_send.mbuffer.in.$$
        local /tmp/zfs_send.mbuffer.out.$$
    fi
        

    


}




zfsjob () {

    # All variables used must be copied to a local variable because this function will be called
    # multiple times as a job fork.

    local jobfolder="$1"
    local job="$2"
    local job_backup_snaptag=
    local job_mode=
    local now="$(now_stamp)"
    local source_begin_snap=
    local source_end_snap=
    local last_complete_snap=
    local target_snapshots=
    local target_host=
    local target_folder=

    source ${jobfolder}/${job}

    # Determine if we've backed up before
    if [ -d ${statfolder}/${job} ]; then
        source ${statfolder}/${job}
    else
        # Create job accounting folder
        mkdir -p ${statfolder}/${job}
    fi

    target_host=`echo $backup_target | awk -F ":" '{print $1}'`
    target_folder=`echo $backup_target | awk -F ":" '{print $2}'`
    debug "Backing up $backup_source to $target_host folder $target_folder"


    # Create snapshot for this increment
    if [ "$job_backup_snaptag" == "" ]; then
        if [ "$zfs_backup_snaptag" == "" ]; then
            job_backup_snaptag="zfs_tools_backup"
        else
            job_backup_snaptag="$zfs_backup_snaptag"
        fi
    fi
        
    source_end_snap="${backup_source}@${job_backup_snaptag}_${now}"
    if [ "$backup_children" == "true" ]; then
        zfs snapshot -r ${source_end_snap}
        zfs hold -r ${job_backup_snaptag} ${source_end_snap}
    else
        zfs snapshot ${source_end_snap}
        zfs hold ${job_backup_snaptag} ${source_end_snap}
    fi

    
    # Loop until completed snapshot is most current

    while [ "$last_complete_snap" != "$source_end_snap" ]; do

        if [ "$last_complete_snap" == "" ]; then
            # This must be the first pass so we start from the origin
    
    
        else
            # Verify recorded last completed snapshot is the last snapshot on the destination
            
    
    
        
        fi
       
    done 

    



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
