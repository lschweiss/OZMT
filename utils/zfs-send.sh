#! /bin/bash

# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012-2015  Chip Schweiss

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

if [ "$logfile" == "" ]; then
    if [ "x$zfs_logfile" != "x" ]; then
        logfile="$zfs_logfile"
    else
        logfile="$default_logfile"
    fi
fi

if [ "$report_name" == "" ]; then
    if [ "x$zfs_report" != "x" ]; then
        report_name="$zfs_report"
    else
        report_name="$default_report_name"
    fi
fi

# TODO: Several remote commands need to have tunable full paths.

result=
verify='true'
remote_ssh=
remote_port=
target_fifo=
target_fifos=
source_fifo=
local_fifos=
success='false'


##
# Clean up 
##
clean_up () {

    ptree $$ > $tmpdir/ptree-zfs_send.txt
    set > $tmpdir/environment.txt
    echo $1 > $tmpdir/exit-code.txt

    
    if [ "$post_sync_lock" == 'true' ]; then
        release_lock $post_sync_file
    fi

    if [ "$success" == 'false' ]; then
        # Kill running processes
        pidfiles=`ls -1 $tmpdir/*.pid 2> /dev/null`
        for pidfile in $pidfiless; do
            pids=`cat $pidfile`
            for pid in $pids; do
                # Find child pids
                for cpid in $(pidtree $pid); do 
                    notice "Killing process $pidfile, PID $cpid"
                    kill $cpid &> /dev/null
                done
            done
        done
        # Find any remaining child processes
        this_pid=$$
        pids=`pidtree $this_pid | $SED -n '1!p'`
        for pid in $pids; do
            kill $pid &>/dev/null
        done

        if [ "$remote_host" != "" ]; then
            pids=`$remote_ssh "cat $remote_tmp/*.pid 2>/dev/null"`
            for pid in $pids; do
                notice "Killing remote process PID $pid"
                $remote_ssh "kill $pid &> /dev/null"
            done
        fi
    else
        # Clean up temp space
        if [ ! -t 1 ]; then
            if [ "$tmpdir" != "" ]; then
                rm -rf $tmpdir
            fi
            if [ "$remote_host" != "" ]; then
                $remote_ssh "rm -r $remote_tmp"
            fi
        fi
    fi

    # Clean up reserved port
    if [ "$remote_port" != "" ]; then
        debug "Returning remote port $remote_port to the port pool"
        $remote_ssh "${TOOLS_ROOT}/backup/zfs-backup-port-pool.sh return_port $remote_port"
    fi 

    # Clean up info files

    if [[ "$pid_info" != "" && -f "$pid_info" ]]; then
        rm -f "$pid_info"
    fi

    if [[ "$t_pid_info" != "" && -f "$t_pid_info" ]]; then
        rm -f "$t_pid_info"
    fi
 
    exit $1
}

trap clean_up SIGHUP SIGINT SIGTERM


die () {
    warning "$1" $2
    rm $2 2>/dev/null
    clean_up 1
}

# show function usage
show_usage() {
    echo
    echo "Usage: $0 -s {source_zfs_folder} -t {target_zfs_folder}"
    echo "  [-f {first_snap}]   First snapshot.  Defaults to 'origin'"
    echo "  [-l {last_snap}]    Last snapshot.  Defaults to latest snapshot."
    echo "  [-r]                Use a replication stream"
    echo "  [-i]                Use an incremental stream"
    echo "  [-I]                Use an incremental stream with all intermediary snapshots"
    echo "                      -i and -I are mutually exclusive.  The last one specfied will be honored."
    echo "  [-d]                Delete snapshots on the target that do not exist on the source."
    echo "  [-p {prop_string} ] Reset properties on target"
    echo "  [-u]                pUsh locally set zfs properties to the target."
    echo "  [-U]                pUsh locally set zfs properties to the target durring job cleaning."
    echo "                        Requires -n to be set to the dataset name"
    echo "  [-c]                Use zfs send --compressed option"
    echo "  [-A]                Use zfs send --large-block option"
    echo "  [-h host]           Send to a remote host.  Defaults to via mbuffer."
    echo "  [-S]                Use ssh transport."
    echo "  [-M]                Use mbuffer transport."
    echo "  [-b n]              Use BBCP, n connections.  "
    echo "     [-e]             Encrypt traffic w/ openssl.  Only for BBCP."
    echo "  [-m]                Use mbuffer."
    echo "  [-g n]              Compress with gzip level n."
    echo "  [-z n]              Compress with LZ4.  Specify 1 for standard LZ4.  Specify 4 - 9 for LZ4HC compression level."
    echo "  [-F]                Target is a flat file.  No zfs receive will be used."
    echo "  [-k {file} ]        Generate a md5 sum.  Store it in {file}."
    echo "  [-K {file} ]        Generate a md5 sum.  Store it in remote {file}."
    echo "  [-L {file} ]        Overide default log file location."
    echo "  [-R {report_name} ] Overide default report name."
    echo "  [-n {name} ]        Name for this job."
    echo "  [-P {file} ]        File to place PID info path on the source side"
    echo "  [-T {file ]         File to place PID on the target side"
}

# Minimum number of arguments needed by this program
MIN_ARGS=4

if [ "$#" -lt "$MIN_ARGS" ]; then
    show_usage
    exit 1
fi

source_folder=
target_folder=
target_pool=
first_snap=
last_snap=
replicate='false'
increment_type=''
delete_snaps='false'
receive_options='-vu'
target_prop=
push_prop=
remote_host=
mbuffer_use='false'
mbuffer_transport_use='false'
ssh_use='false'
bbcp_streams=0
bbcp_encrypt='false'
transport_selected='false'
gzip_level=0
lz4_level=0
flat_file='false'
gen_chksum=
job_name='zfs_send'
pid_info=
t_pid_info=
send_compressed='false'
send_large='false'


while getopts s:t:f:l:ruUcAiIdp:h:miMSb:eg:z:Fk:K:L:R:n:P:T: opt; do
    case $opt in
        s)  # Source ZFS folder
            source_folder="$OPTARG"
            debug "${job_name}: Source folder: $source_folder"
            ;;
        t)  # Target ZFS folder or flat file
            target_folder="$OPTARG"
            debug "${job_name}: Target folder: $target_folder"
            ;;
        f)  # First snapshot
            first_snap="$OPTARG"
            debug "${job_name}: first_snap:    $first_snap"
            ;;
        l)  # Last snapshot
            last_snap="$OPTARG"
            debug "${job_name}: last_snap:     $last_snap"
            ;;
        r)  # Use a replication stream
            replicate='true'
            debug "${job_name}: Using a replication stream."
            ;;
        i)  # Use an incremental stream
            increment_type='-i'
            debug "${job_name}: Using an incremental stream."
            ;;
        I)  # Use an incremental stream with intermediary snapshots
            increment_type='-I'
            debug "${job_name}: Using an incremental stream with intermediary snapshots."
            ;; 
        d)  # Delete snapshots on the target
            delete_snaps='true'
            receive_options="-F $receive_options"
            debug "${job_name}: Will delete snapshots on the target"
            ;;
        p)  # Reset properties on target
            target_prop="-o $OPTARG"
            debug "${job_name}: resetting target properties to: $target_prop"
            ;;
        u)  # Push locally set zfs properties to the target
            push_prop='true'
            debug "${job_name}: pushing locally set zfs properties to the target"
            ;;
        U)  # pUsh locally set zfs properties to the target durring job cleaning.
            push_prop='true'
            push_prop_later='true'
            debug "${job_name}: pushing locally set zfs properties to the target durring job cleaning"
            ;;
        c)  # Use send --compress
            send_compressed='true'
            debug "${job_name}: Using zfs send --compress"
            ;;
        A)  # Use send --large-block
            send_large='true'
            debug "${job_name}: Using zfs send --large-block"
            ;;
        h)  # Remote host
            remote_host="$OPTARG"
            debug "${job_name}: Remote host:   $remote_host"
            ;;
        m)  # Use mbuffer
            mbuffer_use='true'
            debug "${job_name}: Using mbuffer"
            ;;
        M)  # Use mbuffer transport
            mbuffer_transport_use='true'
            transport_selected='mbuffer'
            debug "${job_name}: Using mbuffer transport"
            ;;    
        S)  # Use SSH transport
            ssh_use='true'
            transport_selected='ssh'
            debug "${job_name}: Using ssh transport"
            ;;
        b)  # Use BBCP
            bbcp_streams="$OPTARG"
            transport_selected='bbcp'
            debug "${job_name}: Using BBCP, $bbcp_streams connections."
            ;;
        e)  # Encrypt BBCP traffic
            bbcp_encrypt='true'
            debug "${job_name}: Encrypting BBCP traffic"
            ;;
        g)  # Compress with gzip
            gzip_level="$OPTARG"
            debug "${job_name}: Gzip compression level $gzip_level"
            ;;
        z)  # Compress with LZ4
            lz4_level="$OPTARG"
            debug "${job_name}: lz4 set to: $lz4_level"
            case $lz4_level in
                1) 
                    debug "${job_name}: Using LZ4 standard" ;;
                [4-9])
                    debug "${job_name}: Using LZ4HC level $lz4_level" ;;
                *)
                    die "${job_name}: Invalid LZ4 specified" ;;
            esac
            ;;
        F)  # Target is a flat file
            flat_file='true'
            debug "${job_name}: Flat file target"
            ;;
        k)  # Generate a md5 checksum
            gen_chksum="$OPTARG"
            debug "${job_name}: Generate MD5 sum in file $gen_chksum"
            ;;
        K)  # Generate a md5 checksum
            remote_chksum="$OPTARG"
            debug "${job_name}: Generate MD5 sum in file remote $remote_chksum"
            ;;
        L)  # Overide default log file
            log_file="$OPTARG"
            debug "${job_name}: Log file set to $log_file"
            ;;
        R)  # Overide default report name
            report_name="$OPTARG"
            debug "${job_name}: Report name set to $report_name"
            ;;   
        n)  # Job name
            job_name="$OPTARG"
            debug "${job_name}: Job name set to $job_name"
            ;;
        P)  # PID file
            pid_info="${OPTARG}"
            debug "${job_name}: PID info file set to $pid_info"
            ;;
        T)  # Target system PID file
            t_pid_info="${OPTARG}"
            debug "${job_name}: Target system PID info file set to $t_pid_info"
            ;;
        ?)  # Show program usage and exit
            show_usage
            exit 0
            ;;
        :)  # Mandatory arguments not specified
            die "${job_name}: Option -$OPTARG requires an argument."
            ;;
    esac
done

tmpdir=${TMP}/replication/zfs_send/zfs_send_to_$(foldertojob ${target_folder})_$$
if [ "$pid_info" != "" ]; then
    echo "$tmpdir" > "$pid_info"
fi

remote_tmp=${TMP}/replication/zfs_receive/zfs_receive_from_$(foldertojob ${source_folder})_$$
if [ "$t_pid_info" != "" ]; then
    echo "$remote_tmp" > "$t_pid_info"
fi



if [ -d $tmpdir ]; then
    warning "${jobname}: Temp directory $tmpdir already exists. Removing."
    rm -rf $tmpdir
fi
MKDIR $tmpdir

######
######
##
## Verification
##
######
######

###
#
# Verify all input is valid
#
###

if [ "$source_folder" == "" ]; then
    die "${job_name}: no source folder specified"
fi

if [ "$target_folder" == "" ]; then
    die "${job_name}: not target specified"
fi


if [ "$first_snap" == "" ]; then
    first_snap='origin'
    debug "${job_name}: first_snap not specified, set to origin"
fi

if [ "$flat_file" == 'false' ]; then
    # Split into pool / folder
    target_pool=`echo $target_folder | ${AWK} -F "/" '{print $1}'`
fi

re='^[0-9]+$'
if ! [[ $gzip_level =~ $re ]] ; then
   die "${job_name}: -g expects a number between 0 and9"
fi

if ! [[ $lz4_level =~ $re ]] ; then
    if [ [ $lz4_level -gt 9 ] || [ $lz4_level -lt 4 ] ]; then
        die "${job_name}: -z expects a number between 4 and 9"
    fi
fi

##
# Verify remote host
##


if [ "$remote_host" != "" ]; then
    if [ "$transport_selected" == 'false' ]; then
        error "${job_name} Remote host specified, but no viable transport selected."    
        verify='fail'
    fi 
    ${TIMEOUT} 30s ${SSH} root@${remote_host} rm -rf $remote_tmp
    ${TIMEOUT} 30s ${SSH} root@${remote_host} mkdir -p $remote_tmp
    result=$?
    if [ $result -ne 0 ]; then
        warning "${job_name}: Cannot connect to remote host at root@${remote_host}"
        verify='fail'
    else
        debug "${job_name}: Remote host connection verified."
    fi
else
    if [ "$bbcp_streams" != "0" ]; then
        error "${job_name}: Cannot use bbcp for local jobs"
    fi
fi

##
# Verify source folder
##

zfs list $source_folder &> /dev/null
result=$?
if [ $result -ne 0 ]; then
    error "${job_name}: Source zfs folder $source_folder not found."
    verify='fail'
else
    debug "${job_name}: Source zfs folder $source_folder verified."
    zfs list -r -t snapshot -H -o name -s creation $source_folder | ${GREP} "^${source_folder}@" > $tmpdir/snapshot.list
fi

##
# Verify last snapshot
##

if [ "$last_snap" != "" ]; then
    cat $tmpdir/snapshot.list | ${GREP} -q "$last_snap"
    if [ $? -ne 0 ]; then
        die "${job_name}: Last snapshot $last_snap not found in source folder $source_folder"
    else
        debug "${job_name}: Last snapshot $last_snap verified."
    fi
else
    debug "${job_name}: Last snap not specified.  Looking up last snapshot for folder $source_folder"
    last_snap=`cat $tmpdir/snapshot.list | ${GREP} "^${source_folder}@" | tail -1`
fi

debug "${job_name}: Last snap set to $last_snap"

##
# Verify first snapshot
##

if [ "$first_snap" != "origin" ]; then
    cat $tmpdir/snapshot.list | ${GREP} -q "$first_snap"
    if [ $? -ne 0 ]; then
        die "${job_name}: First snapshot $first_snap not found in source folder $source_folder"
    else
        send_snaps="$increment_type ${first_snap} ${last_snap}"
        debug "${job_name}: First snapshot $first_snap verified."
    fi
else
#    if [ "$increment_type" != '' ]; then
#        error "${job_name}: Incremental jobs cannot start at the origin unless it is a clone"
#    fi
    # Determine if this is a clone
    origin=`zfs get -H origin $source_folder|${AWK} -F " " '{print $3}'`
    if [ "$origin" == '-' ]; then
        first_snap_name="${source_folder}@origin"
        if [ "$delete_snaps" != 'true' ]; then
            receive_options="-F $receive_options"
        fi
    else
        originfs=`echo $origin | ${AWK} -F "@" '{print $1}'`
        debug "${job_name}: Source file system is a clone.  Setting source to ${originfs}@origin"
        first_snap_name="${originfs}@origin"
    fi
    if [ "$replicate" == 'true' ] && [ "$first_snap" == 'origin' ] && [ "$increment_type" != '' ]; then
        die "${job_name}: Cannot use a replication stream and incremental scream from a filesystem's origin."
    else 
        if [ "$increment_type" != '' ]; then
            if [ "$first_snap_name" == "${source_folder}@origin" ]; then
                send_snaps="${last_snap}"
            else
                send_snaps="${increment_type} ${first_snap_name} ${last_snap}"
            fi
        else
            send_snaps="${last_snap}"
            #if [ "$delete_snaps" != 'true' ]; then
            #    receive_options="-F $receive_options"
            #fi
        fi
    fi
    
fi


##
# Verify target folder / file
##

if [ "$remote_host" == "" ]; then
    # Local test
    if [ "$flat_file" == 'false' ]; then
        if [ "$replicate" == 'false' ]; then
            zfs list $target_folder &> /dev/null
            result=$?
            if [ $result -ne 0 ]; then
                error "${job_name}: Replicate not specified however target folder $target_folder does not exist."
                verify='fail'
            fi
        else
            # Verify pool exists
            zfs list $target_pool &> /dev/null
            result=$?
            if [ $result -ne 0 ]; then
                error "${job_name}: Replicate specified however target pool $target_pool does not exist."
                verify='fail'
            fi
        fi
    else # Flat file
        touch $target_folder &> /dev/null
        result=$?
        if [ $result -ne 0 ]; then
            error "${job_name}: Cannot create flat file $target_folder"
            verify='fail'
        else
            rm $target_folder
        fi
    fi
else
    # Remote test
    remote_ssh="${SSH} root@$remote_host"
    remote_ssh_quick="${SSH_BIN} root@$remote_host"
    if [ "$flat_file" == 'false' ]; then
        if [ "$replicate" == 'false' ]; then
            ${TIMEOUT} 2m $remote_ssh zfs list $target_folder &> /dev/null
            result=$?
            if [ $result -ne 0 ]; then
                error "${job_name}: Replicate not specified however target folder $target_folder does not exist on host $remote_host"
                verify='fail'
            fi
        else
            # Verify pool exists
            ${TIMEOUT} 2m $remote_ssh zfs list $target_pool &> /dev/null
            result=$?
            if [ $result -ne 0 ]; then
                error "${job_name}: Replicate specified however target pool $target_pool does not exist on host $remote_host"
                verify='fail'
            fi
        fi
    else # Flat file
        ${TIMEOUT} 30s $remote_ssh touch $target_folder &> /dev/null
        result=$?
        if [ $result -ne 0 ]; then
            error "${job_name}: Cannot create flat file $target_folder on host $remote_host"
            verify='fail'
        else
            $remote_ssh rm $target_folder
        fi
    fi
fi


if [ "$verify" == 'fail' ]; then
    die "${job_name}: Input validation failed.  Aborting."
else
    debug "${job_name}: Input valdation succeeded.  Proceeding."
fi

######
######
##
## Functions
##
######
######

remote_fifo () {
    local fifo="${remote_tmp}/${1}.fifo"
    debug "${job_name}: Creating remote fifo ${fifo}"
    ${TIMEOUT} 1m $remote_ssh "mkfifo ${fifo}" 2>${TMP}/remote_fifo_$$.txt || \
        die "${job_name}: Could not setup remote fifo $1 on host $remote_host" ${TMP}/remote_fifo_$$.txt
    rm ${TMP}/remote_fifo_$$.txt 2>/dev/null
    target_fifos="${fifo} $target_fifos"
    result="${fifo}"
}

local_fifo () {
    local fifo="${tmpdir}/${1}.fifo"
    debug "${job_name}: Creating local fifo $fifo"
    mkfifo "${fifo}" || \
        die "${job_name}: Could not setup fifo $fifo"
    local_fifos="${fifo} $local_fifos"
    result="${fifo}"
}

remote_launch () {

    local name="$1"
    local stdin="$2"
    local process="$3"
    local stdout="$4"
    local stderr="$5"
    local errlvl="$remote_tmp/${name}.errorlevel"
    local pidfile="$remote_tmp/${name}.pid"

    $remote_ssh "nohup $TOOLS_ROOT/utils/remote-runner.sh \"${stdin}\" \"${stdout}\" \"${stderr}\" \"${errlvl}\" \"${pidfile}\" \"${process}\" </dev/null 1>/dev/null 2>/dev/null &"

}


pause () {

    local nothing=
    echo "Press enter to continue..."
    read nothing
}



################################################################
#
# Build from target to source connecting fifos as we build
#
################################################################


##
# zfs receive or flat file
##

if [ "$flat_file" == 'true' ]; then
    # To flat file
    if [ "$remote_host" == "" ]; then
        local_fifo flat_file
        target_fifo="$result"
        debug "${job_name}: Starting local pipe from $target_fifo to $target_folder"
        ( cat $target_fifo 1> $target_folder 2> $tmpdir/flat_file.error ; echo $? > $tmpdir/flat_file.errorlevel ) &
        pidtree $! > $tmpdir/flat_file.pid
        local_watch="flat_file $local_watch"
        
    else
        remote_fifo flat_file
        target_fifo="$result"
        debug "${job_name}: Starting remote pipe from $target_fifo to $target_folder"
        remote_launch "flat_file" \
            "cat $target_fifo" \
            "$target_folder" \
            "$remote_tmp/flat_file.error" 
        remote_watch="flat_file $remote_watch"
    fi
else
    # To zfs receive
    if [ "$remote_host" == "" ]; then
        # Local
        local_fifo zfs_receive
        target_fifo="$result"
        debug "${job_name}: Starting local zfs receive $target_fifo to ${target_folder}"
        ( cat $target_fifo | zfs receive ${receive_options} ${target_prop} ${target_folder} \
            2> $tmpdir/zfs_receive.error ; echo $? > $tmpdir/zfs_receive.errorlevel ) &
        pidtree $! > $tmpdir/zfs_receive.pid
        local_watch="$zfs_receive $local_watch"
    else
        # Remote
        remote_fifo zfs_receive
        target_fifo="$result"
        debug "${job_name}: Starting remote zfs receive ${receive_options} ${target_prop} ${target_folder}"
        remote_launch "zfs_receive" \
            "$target_fifo" \
            "zfs receive ${receive_options} ${target_prop} ${target_folder}" \
            "$remote_tmp/zfs_receive.out" \
            "$remote_tmp/zfs_receive.error" 
        remote_watch="zfs_receive $remote_watch"
    fi
fi

##
# to Glacier
##

#TODO: Make backup to glacier use this script
# Allow usage of more than one glacier tool.

##
# mbuffer - Receive end
##

if [ "$mbuffer_use" == 'true' ]; then
    # Target end
    if [ "$flat_file" == 'false' ] && [ "$remote_host" != "" ] ; then
        remote_fifo mbuffer
        target_mbuffer_fifo="$result"
        debug "${job_name}: Starting remote mbuffer from $target_mbuffer_fifo to $target_fifo"
        remote_launch "mbuffer" \ 
            "$target_mbuffer_fifo" \
            "$mbuffer -q -s 128k -m 128M --md5 -l $remote_tmp/mbuffer.log" \
            "$target_fifo"
            "$remote_tmp/mbuffer.error"
        remote_watch="mbuffer $remote_watch"
        sleep 3
        target_fifo="$target_mbuffer_fifo"
    fi
fi

##
# gzip - Decompress
##

if [ "$gzip_level" -ne 0 ] && [ "$flat_file" == 'false' ] && [ "$remote_host" != "" ]; then
    remote_fifo gzip
    target_gzip_fifo="$result"
    debug "${job_name}: Starting remote gzip decompression from $target_gzip_fifo to $target_fifo"
    remote_launch "gunzip" \
        "$target_gzip_fifo" \
        "$gzip -d --stdout" \
        "$target_fifo" \
        "$remote_tmp/gunzip.error"
    remote_watch="gunzip $remote_watch"
    sleep 2
    target_fifo="$target_gzip_fifo"
fi

##
# LZ4     
##

if [ "$lz4_level" -ne 0 ] && [ "$flat_file" == 'false' ] && [ "$remote_host" != "" ]; then
    remote_fifo lz4
    target_lz4_fifo="$result"
    debug "${job_name}: Starting remote lz4 decompression from $target_lz4_fifo to $target_fifo"
    remote_launch "lz4" \
        "$target_lz4_fifo" \
        "$lz4 -d" \
        "$target_fifo" \
        "$remote_tmp/lz4.error"
    remote_watch="lz4 $remote_watch"
    sleep 2
    target_fifo="$target_lz4_fifo"
fi


##
# OpenSSL Decrypt
##

if [ "$bbcp_encrypt" == 'true' ]; then
    bbcp_key="$tmpdir/bbcp.key"
    remote_bbcp_key="$remote_tmp/bbcp.key"
    # Generate ssl key 
    pwgen -s 63 1 > $bbcp_key
    # Push key to remote
    scp $bbcp_key root@${remote_host}:${remote_bbcp_key}

    # Open FIFO
    remote_fifo openssl
    target_ssl_fifo="$result"

    # Start openssl
    debug "${job_name}: Starting remote openssl decrypt from $target_ssl_fifo to $target_fifo"
    remote_launch "openssl" \
        "$target_ssl_fifo" \
        "openssl aes-256-cbc -d -pass file:$bbcp_key" \
        "$target_fifo" \
        "$remote_tmp/openssl.error"
    remote_watch="openssl $remote_watch"
    sleep 1
    target_fifo="$target_ssl_fifo"
fi


##
# mbuffer transport - Receive end
##

if [ "$mbuffer_transport_use" == 'true' ]; then
    # Target end
    if [ "$remote_host" != "" ] ; then
        debug "${job_name}: Gathering remote listening port for mbuffer"
        # Collect listening port from remote pool
        $remote_ssh "${TOOLS_ROOT}/backup/zfs-backup-port-pool.sh get_port" > ${TMP}/$$_remote_port
        if [ $? != 0 ]; then
            warning "${job_name}: Could not retrieve remote listening port for mbuffer transport."
            clean_up 1
        fi

        remote_port=`cat ${TMP}/$$_remote_port`
        rm ${TMP}/$$_remote_port        
        
        remote_launch "mbuffer_transport" \
            "/dev/null" \
            "$mbuffer -I ${remote_port} -q -s 128k -m 128M -l $remote_tmp/mbuffer_transport.log" \
            "$target_fifo" \
            "$remote_tmp/mbuffer_transport.error" 
        remote_watch="mbuffer_transport $remote_watch"
        # TODO:  Under heavy load this sleep is not enough causing the job to fail. A method to 
        # deal with this is needed.
        sleep 2
        # Attach the port reservation to the mbuffer process
        timeout 30s $remote_ssh "cat ${remote_tmp}/mbuffer_transport.pid" > ${TMP}/$$_remote_mbuffer_pid 2>${TMP}/$$_remote_mbuffer_pid_error.txt
        if [ $? -ne 0 ]; then
            rm -f ${TMP}/$$_remote_mbuffer_pid
            die "${job_name}: Could not connect to remote host to collect mbuffer_transport.pid" ${TMP}/$$_remote_mbuffer_pid_error.txt
        fi
        mbuffer_pid=`cat ${TMP}/$$_remote_mbuffer_pid`
        rm ${TMP}/$$_remote_mbuffer_pid ${TMP}/$$_remote_mbuffer_pid_error.txt 2>/dev/null
        debug "Attaching remote port $remote_port to mbuffer PID $mbuffer_pid command $mbuffer"
        $remote_ssh "${TOOLS_ROOT}/backup/zfs-backup-port-pool.sh attach_port $remote_port $mbuffer_pid $mbuffer"
    fi
fi


##
# Remote components are all running.
# Launch remote watch script
##

if [ "$remote_host" != "" ]; then
    # Launch remote monitor script

    debug "${job_name}: Launching remote monitor script"
    remote_launch "monitor" \
        "/dev/null" \
        "$TOOLS_ROOT/utils/remote-monitor.sh \"${remote_tmp}\" \"$remote_watch\"" \
        "${remote_tmp}/monitor.out" \
        "${remote_tmp}/monitor.error" 
fi



case $transport_selected in

    bbcp)
        ##
        # BBCP
        ##
        
        # Source FIFO
        local_fifo bbcp
        target_bbcp_fifo="$result"
        debug "${job_name}: Starting bbcp pipe transport from local $target_bbcp_fifo to remote $target_fifo"
        ( $BBCP -V -T "$remote_ssh $BBCP" -o -s $bbcp_streams -P 60 --port 5201:5500 \
            -b 5 -b +5 -B 8m -N io "$target_bbcp_fifo" "root@${remote_host}:${target_fifo}" \
            1> $tmpdir/bbcp.log \
            2> $tmpdir/bbcp.error ; echo $? > $tmpdir/bbcp.errorlevel ) &
        pidtree $! > $tmpdir/bbcp.pid
        target_fifo="$target_bbcp_fifo"
        local_watch="bbcp $local_watch"
        if [ -t 1 ]; then
            tail -f $tmpdir/bbcp.error &
        fi  
        # Wait for bbcp pipe to be setup
        bbcp_started=1
        debug "${job_name}: Waiting for BBCP to start"
        SECONDS=0
        while [ $bbcp_started -eq 1 ]; do
            sleep 0.2
            cat $tmpdir/bbcp.error | ${GREP} -q "bbcp: Creating"
            bbcp_started=$?
            if [ $SECONDS -gt 60 ]; then
                warning "${job_name}: Failed to start BBCP" $tmpdir/bbcp.error
                touch $tmpdir/bbcp.fail
                break
            fi
        done
        [ -f $tmpdir/bbcp.fail ] && clean_up 1
        debug "${job_name}: BBCP started $bbcp_started"
        sleep 10
    ;;

    ssh)
        ##
        # SSH
        ##
        
        local_fifo ssh
        target_ssh_fifo="$result"
        debug "${job_name}: Starting ssh pipe transport from local $target_ssh_fifo to remote $target_fifo"
        ( cat $target_ssh_fifo | $remote_ssh "cat > $target_fifo" 2> /$tmpdir/ssh.error ; echo $? > $tmpdir/ssh.errorlevel ) &
        pidtree $! > $tmpdir/ssh.pid
        target_fifo="$target_ssh_fifo"
        local_watch="ssh $local_watch"
        sleep 3
    ;;

    mbuffer)
        ##
        # mbuffer transport
        ##
        
        local_fifo source_mbuffer_transport
        source_mbuffer_transport_fifo="$result"
        # Source end
        debug "${job_name}: Starting local mbuffer transport from $source_mbuffer_transport_fifo to ${remote_host}:${remote_port}"
        ( cat $source_mbuffer_transport_fifo | \
            $mbuffer \
            -O ${remote_host}:${remote_port} -q -s 128k -m 128M \
            -l $tmpdir/mbuffer_transport.log \
            2> $tmpdir/mbuffer_transport.error ; \
            echo $? > $tmpdir/mbuffer_transport.errorlevel ) &
        pidtree $! > $tmpdir/mbuffer_transport.pid
        target_fifo="$source_mbuffer_transport_fifo"
        local_watch="mbuffer_transport $local_watch"
        sleep 3
    ;;

esac

##
# OpenSSL Encrypt
##

if [ "$bbcp_encrypt" == 'true' ]; then
    # Setup was handled when target decrypt was configured
    local_fifo openssl
    source_ssl_fifo="$result"
    debug "${job_name}: Starting local openssl encrypt from $source_ssl_fifo to $target_fifo"
    ( cat "$source_ssl_fifo" | \
        openssl aes-256-cbc -pass file:$bbcp_key \
        2> "$tmpdir/openssl.error" | \
        cat > "$target_fifo" ; echo $? > $tmpdir/openssl.errorlevel ) &
    pidtree $! > $tmpdir/openssl.pid
    target_fifo="$target_ssl_fifo"
    local_watch="openssl $local_watch"
    sleep 3
fi

##
# gpg Encrypt
##

#TODO: Redo backup to glacier to use this send routine.

##
# LZ4
##

if [ "$lz4_level" -ne 0 ]; then
    local_fifo lz4
    source_lz4_fifo="$result"
    debug "${job_name}: Starting local lz4 compression from $source_lz4_fifo to $target_fifo"
    ( cat "$source_lz4_fifo" | \
        $lz4 -${lz4_level} 2> "$tmpdir/lz4.error" | \
        cat > "$target_fifo" ; \
        echo $? > "$tmpdir/lz4.errorlevel" ) &
    pidtree $! > $tmpdir/lz4.pid
    target_fifo="$source_lz4_fifo"
    local_watch="lz4 $local_watch"
    sleep 2
fi

##
# gzip Compress
##

if [ "$gzip_level" -ne 0 ]; then
    local_fifo gzip
    source_gzip_fifo="$result"
    debug "${job_name}: Starting local gzip compression from $source_gzip_fifo to $target_fifo"
    ( cat "$source_gzip_fifo" | \
        gzip -${gzip_level} --stdout 2> "$tmpdir/gzip.error" | \
        cat > "$target_fifo" ; echo $? > "$tmpdir/gzip.errorlevel" ) &
    pidtree $! > $tmpdir/gzip.pid
    target_fifo="$source_gzip_fifo"
    local_watch="gzip $local_watch"
    sleep 2
fi


##
# mbuffer - Send end
##

if [ "$mbuffer_use" == 'true' ]; then
    # Source end
    local_fifo mbuffer
    source_mbuffer_fifo="$result"
    debug "${job_name}: Starting local mbuffer from $source_mbuffer_fifo to $target_fifo"
    ( cat "$source_mbuffer_fifo" | \
        $mbuffer -q -s 128k -m 128M --md5 -l "$tmpdir/mbuffer.log" \
        2> $tmpdir/mbuffer.error | \
        cat > "$target_fifo" ; \
        echo $? > "$tmpdir/mbuffer.errorlevel" ) &
    pidtree $! > $tmpdir/mbuffer.pid
    target_fifo="$source_mbuffer_fifo"
    local_watch="mbuffer $local_watch"
    sleep 2
fi

##
# Generate md5 sum for local or remote storage
##

if [ "$gen_chksum" != "" ] || [ "$remote_chksum" != "" ]; then
    local_fifo md5sum
    source_md5sum_fifo="$result"
    debug "${job_name}: Starting md5sum from $source_md5sum_fifo piping to $target_fifo"
    ( cat "$source_md5sum_fifo" | \
        tee $target_fifo | \
        md5sum -b > "$tmpdir/md5sum" 2> "$tmpdir/md5sum.error" ; \
        echo $? > "$tmpdir/md5sum.errorlevel" ) &
    pidtree $! > $tmpdir/md5sum.pid
    target_fifo="$source_md5sum_fifo"
    local_watch="md5sum $local_watch"
fi


################################################################
#
# Start the zfs send
#
################################################################

if [ "$replicate" == 'true' ]; then
    send_options="-R"
else
    send_options=
fi

[ "$send_compressed" == 'true' ] && send_options="$send_options --compressed"
[ "$send_large" == 'true' ] && send_options="$send_options --large-block"

debug "${job_name}: Starting zfs send to $target_fifo"
debug "${job_name}:   zfs send -v -P $send_options $send_snaps 2> $tmpdir/zfs_send.error 1> $target_fifo"
( sleep 2 ; zfs send -v -P $send_options $send_snaps 2> $tmpdir/zfs_send.error 1> $target_fifo ; echo $? > $tmpdir/zfs_send.errorlevel ) &
pidtree $! > $tmpdir/zfs_send.pid
local_watch="zfs_send $local_watch"




################################################################
#
# Watch the running processes for completion or failure
#
################################################################

running='true'
watch="$local_watch"
success='false'

debug "${job_name}: Starting watch loop"

while [ "$running" == 'true' ]; do
    for process in $watch; do
        errfile="${tmpdir}/${process}.errorlevel"
        if [ ! -f ${tmpdir}/${process}.complete ] && [ -f $errfile ]; then
            # This process has ended
            errlvl=`cat $errfile`
            if [ $errlvl -eq 0 ]; then
                touch ${tmpdir}/${process}.complete
                complete="$process $complete"
            else
                if [ "$process" == "zfs_send" ]; then
                    # zfs send will report a warning and return error if a new child folder was created.  
                    # Eliminate that condition as a failure  
                    # TODO: This bug has been fixed in https://www.illumos.org/issues/6111  
                    # It's worth adding a test here if that patch is active on this
                    # system.
                    cat $tmpdir/zfs_send.error | ${GREP} -q "WARNING: could not send.*does not exist" &&
                        cat $tmpdir/zfs_send.error | ${GREP} -q "^incremental"
                    if [ $? -eq 0 ]; then
                        # We will ignore the error state, assuming we had a successful send
                        touch ${tmpdir}/${process}.complete
                        complete="$process $complete"
                    else
                        touch ${tmpdir}/${process}.fail
                        running='false'
                        touch ${tmpdir}/running.false
                    fi
                else
                    touch ${tmpdir}/${process}.fail
                    running='false'
                    touch ${tmpdir}/running.false
                fi
            fi
        fi
        # Other threads may have created the .fail file
        if [ -f ${tmpdir}/${process}.fail ]; then
            running='false'
            touch ${tmpdir}/running.false
        fi
    done

    echo "$complete" > ${tmpdir}/complete.list
    echo "$watch" > ${tmpdir}/watch.list

    # Determine if all processes are complete
    finished='true'
    for process in $watch; do
        if [[ $complete != *${process}* ]]; then
            finished='false'
        fi
    done

    if [ "$remote_host" != "" ]; then
        # Check remote status
        remote_failed=`$remote_ssh_quick "ls -1 ${remote_tmp}/*.fail 2> /dev/null"`
        remote_finished=`$remote_ssh_quick "ls -1 ${remote_tmp}/remote.complete 2> /dev/null"`

        remote_reset=`$remote_ssh_quick "ls -1 ${remote_tmp} 2>&1 | grep 'No such file or directory'"`

        if [ "$remote_reset" != "" ]; then
            running='false'
            success='false'
            touch ${tmpdir}/running.false
            touch ${tmpdir}/remote.failed
            error "Failed to replicated ${job_name}. Remote receive has been lost"
        fi
    
        if [ "$remote_failed" != "" ]; then
            running='false'
            success='false'
            touch ${tmpdir}/running.false
            touch ${tmpdir}/remote.failed

            # Check if clones need destroyed remotely
            failed_clone=`$remote_ssh_quick "cat ${remote_tmp}/zfs_receive.error 2>/dev/null | \
                grep 'cannot receive new filesystem stream: destination has snapshots'"`
            if [ "$failed_clone" != '' ]; then
                destroy_clone=`echo $failed_clone | ${GREP} -oP '(?<=eg. ).*?(?=@)'`
                #TODO : Actually destroy the clone once we know this check is working properly all the time
                error "Failed to replicated ${job_name}.  Remote clone $destroy_clone must be destroyed"
            fi            
            
        fi
    fi

    if [ "$finished" == 'true' ]; then
        if [ "$remote_host" != "" ]; then
            if [ "$remote_finished" == "${remote_tmp}/remote.complete" ]; then
                running='false'
                touch ${tmpdir}/running.false
                success='true'
                touch ${tmpdir}/remote.complete
            fi
        else
            running='false'
            touch ${tmpdir}/running.false
            success='true'
        fi
    fi

    set > $tmpdir/environment.out

    sleep 2

done

##
# Push locally set zfs properties to the target
##

# TODO: this can be slow and should be religated to a separate process like job cleaning

#if [[ "$success" == 'true' && "$push_prop" == 'true' ]]; then
#
#    if [ "$replicate" == 'true' ]; then
#        folder_list=`zfs list -o name -H -t filesystem -r $source_folder`
#    else
#        folder_list="$source_folder"
#    fi
#
#    updates='false'
#
#    post_sync_file="${TMP}/replication/zfs_properties/${job_name}/local_zfs_properties"
#
#    if [[ "$push_prop_later" == 'true' && "$job_name" != '' ]]; then
#        if [ ! -f $post_sync_file ]; then
#            MKDIR ${TMP}/replication/zfs_properties/${job_name}
#            touch $post_sync_file
#            init_lock $post_sync_file
#        fi
#        wait_for_lock $post_sync_file
#        rm $post_sync_file
#        touch $post_sync_file
#        post_sync_lock='true'
#        # Lock is released in clean_up function.
#    fi
#
#    echo "#! /bin/bash" > ${TMP}/property_update_$$
#
#    for folder in $folder_list; do
#        child="${folder:${#source_folder}}"
#        local_properties=`zfs get -s local,default,inherited -o property -H all ${source_folder}${child} | ${GREP} -v '^quota$' | ${GREP} -v '^refquota$'`
#        for property in $local_properties; do
#            updates='true'
#            if [[ "$push_prop_later" == 'true' && "$job_name" != '' ]]; then
#                echo -e "${child:1}\t$property" >> $post_sync_file
#            fi
#            echo "zfs inherit -S $property ${target_folder}${child}" >> ${TMP}/property_update_$$
#            debug "${job_name}: Updating ${target_folder}${child}   $property"
#        done
#    done
#
#    if [ "$updates" == 'true' ]; then
#        if [[ "$push_prop_later" == 'true' && "$job_name" != '' ]]; then
#            rm ${TMP}/property_update_$$
#        else
#            if [ "$remote_host" != "" ]; then
#                $remote_ssh < ${TMP}/property_update_$$ 2>${TMP}/property_update_err_$$
#            else
#                chmod +x ${TMP}/property_update_$$
#                ${TMP}/property_update_$$ 2>${TMP}/property_update_err_$$
#            fi
#        fi
#    fi
#
#    if [ -f ${TMP}/property_update_err_$$ ]; then
#        err_lines=`cat ${TMP}/property_update_err_$$ | ${WC} -l`
#        if [ $err_lines -ge 1 ]; then
#            warning "${job_name}: Errors running property updates" ${TMP}/property_update_err_$$
#        fi
#    fi
#
#    rm -f ${TMP}/property_update_$$ ${TMP}/property_update_err_$$
#
#fi


##
# Report success/failure
##

if [ "$success" == 'true' ]; then
    debug "${job_name}: Job completed successfully."
    if [ "$gen_chksum" != "" ]; then
        cp "$tmpdir/md5sum" "$gen_chksum"
    fi

    if [ "$remote_chksum" != "" ]; then
        scp "$tmpdir/md5sum" "root@${remote_host}:/${remote_chksum}" &> /dev/null ||
            warning "${job_name}: Failed to push md5sum to ${remote_chksum} on ${remote_host}"
    fi    
else
    warning "${job_name}: zfs-send job failed.  Status left in $tmpdir and $remote_tmp"
fi


##
# Collect job component error levels and report failures
##

if [ -t 1 ]; then

    errorlevels=`ls -1 $tmpdir/*.errorlevel`
    for errorlevel in $errorlevels; do
        echo "local $errorlevel = $(cat $errorlevel)"
    done
    
    errors=`ls -1 $tmpdir/*.error`
    for error in $errors; do
        echo "local ${error}:"
        cat $error
    done
    
    if [ "$remote_host" != "" ]; then
        errorlevels=`$remote_ssh "ls -1 $remote_tmp/*.errorlevel"`
        for errorlevel in $errorlevels; do
            echo -n "remote $errorlevel = "
            $remote_ssh "cat $errorlevel"
        done
        
        errors=`$remote_ssh "ls -1 $remote_tmp/*.error"`
        for error in $errors; do
            echo "remote ${error}:"
            $remote_ssh "cat $error"
        done
    fi
    

fi


##
# Clean up
##

if [ "$success" == 'true' ]; then
    clean_up 0
else
    clean_up 1
fi


