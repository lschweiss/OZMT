#! /bin/bash 

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

_DEBUG="on"

function DEBUG()
{
 [ "$_DEBUG" == "on" ] &&  $@
}

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

result=
verify='true'
remote_ssh=
target_fifo=
target_fifos=
source_fifo=
local_fifos=

die () {
    error "$1"
    if [ "$tmpdir" != "" ]; then
        rm -rf $tmpdir
    fi
    exit 1
}

# show function usage
show_usage() {
    echo
    echo "Usage: $0 -s {source_zfs_folder} -t {target_zfs_folder}"
    echo "  [-f {first_snap}]   First snapshot.  Defaults to 'origin'"
    echo "  [-l {last_snap}]    Last snapshot.  Defaults to latest snapshot."
    echo "  [-h host]           Send to a remote host.  Defaults to via SSH."
    echo "  [-m]                Use mbuffer."
    echo "  [-b n]              Use BBCP, n connections.  "
    echo "     [-e]             Encrypt traffic w/ openssl.  Only for BBCP."
    echo "  [-g n]              Compress with gzip level n."
    echo "  [-z n]              Compress with LZ4.  Specify 1 for standard LZ4.  Specify 4 - 9 for LZ4HC compression level."
    echo "  [-r]                Use a replication stream"
    echo "  [-p {prop_string} ] Reset properties on target"
    echo "  [-F]                Target is a flat file.  No zfs receive will be used."
    echo "  [-k {file} ]        Generate a md5 sum.  Store it in {file}."
    echo "  [-L]                Overide default log file location."
    echo "  [-R]                Overide default report name."
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
remote_host=
mbuffer_use='false'
bbcp_streams=0
bbcp_encrypt='false'
gzip_level=0
lz4_level=0
replicate='false'
target_prop=
flat_file='false'
gen_chksum=

while getopts s:t:f:l:h:mb:eg:z:rpFk:L:R: opt; do
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
        h)  # Remote host
            remote_host="$OPTARG"
            debug "zfs_send: Remote host:   $remote_host"
            ;;
        m)  # Use mbuffer
            mbuffer_use='true'
            debug "zfs_send: Using mbuffer"
            ;;
        b)  # Use BBCP
            bbcp_streams="$OPTARG"
            debug "zfs_send: Using BBCP, $bbcp_streams connections."
            ;;
        e)  # Encrypt BBCP traffic
            bbcp_encrypt='true'
            debug "zfs_send: Encrypting BBCP traffic"
            ;;
        g)  # Compress with gzip
            gzip_level="$OPTARG"
            debug "zfs_send: Gzip compression level $gzip_level"
            ;;
        z)  # Compress with LZ4
            lz4_level="$OPTARG"
            debug "zfs_send: lz4 set to: $lz4_level"
            case $lz4_level in
                1) 
                    debug "zfs_send: Using LZ4 standard" ;;
                [4-9])
                    debug "zfs_send: Using LZ4HC level $lz4_level" ;;
                *)
                    die "zfs_send: Invalid LZ4 specified" ;;
            esac
            ;;
        r)  # Use a replication stream
            replicate='true'
            debug "zfs_send: Using a replication stream."
            ;;
        p)  # Reset properties on target
            target_prop="-o $OPTARG"
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
        L)  # Overide default log file
            log_file="$OPTARG"
            debug "zfs_send: Log file set to $log_file"
            ;;
        R)  # Overide default report name
            report_name="$OPTARG"
            debug "zfs_send: Report name set to $report_name"
            ;;   
        ?)  # Show program usage and exit
            show_usage
            exit 0
            ;;
        :)  # Mandatory arguments not specified
            die "zfs_send: Option -$OPTARG requires an argument."
            ;;
    esac
done

tmpdir=$TMP/zfs_send_$$
remote_tmp=/tmp/zfs_send_$$

mkdir $tmpdir

###
#
# Verify all input is valid
#
###

if [ "$source_folder" == "" ]; then
    die "zfs_send: no source folder specified"
fi

if [ "$target_folder" == "" ]; then
    die "zfs_send: not target specified"
fi


if [ "$first_snap" == "" ]; then
    first_snap='origin'
    debug "zfs_send: first_snap not specified, set to origin"
fi

if [ "$flat_file" == 'false' ]; then
    # Split into pool / folder
    target_pool=`echo $target_folder | awk -F "/" '{print $1}'`
fi

re='^[0-9]+$'
if ! [[ $gzip_level =~ $re ]] ; then
   die "zfs_send: -g expects a number between 0 and9"
fi

if ! [[ $lz4_level =~ $re ]] ; then
    if [ [ $lz4_level -gt 9 ] || [ $lz4_level -lt 4 ] ]; then
        die "zfs_send: -z expects a number between 4 and 9"
    fi
fi

##
# Verify remote host
##


if [ "$remote_host" != "" ]; then
    $timeout 30s $ssh root@${remote_host} mkdir $remote_tmp
    result=$?
    if [ $result -ne 0 ]; then
        error "zfs_send: Cannot connect to remote host at root@${remote_host}"
        verify='fail'
    else
        debug "zfs_send: Remote host connection verified."
    fi
else
    if [ "$bbcp_streams" != "0" ]; then
        error "zfs_send: Cannot use bbcp for local jobs"
    fi
fi

##
# Verify source folder
##

zfs list $source_folder &> /dev/null
result=$?
if [ $result -ne 0 ]; then
    error "zfs_send: Source zfs folder $source_folder not found."
    verify='fail'
else
    debug "zfs_send: Source zfs folder $source_foldeer verified."
fi

##
# Verify last snapshot
##

if [ "$last_snap" != "" ]; then
    zfs list -t snapshot -H -o name -s creation | $grep "^${source_folder}@" | grep -q "$last_snap"
    if [ $? -ne 0 ]; then
        die "zfs_send: Last snapshot $last_snap not found in source folder $source_folder"
    fi
else
    debug "zfs_send: Last snap not specified.  Looking up last snapshot for folder $source_folder"
    last_snap=`zfs list -t snapshot -H -o name -s creation | $grep "^${source_folder}@" | tail -1`
fi

debug "zfs_send: Last snap set to $last_snap"


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
            $timeout 2m $remote_ssh zfs list $target_pool #&> /dev/null
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
else
    debug "zfs_send: Input valdation succeeded.  Proceeding."
fi

##
# Functions
##

remote_fifo () {
    local fifo="${remote_tmp}/${1}.fifo"
    debug "zfs_send: Creating remote fifo ${fifo}"
    $timeout 1m $remote_ssh "mkfifo ${fifo}" || \
        die "zfs_send: Could not setup remote fifo $1 on host $remote_host"
    target_fifos="${fifo} $target_fifos"
    result="${fifo}"
}

local_fifo () {
    local fifo="${tmpdir}/${1}.fifo"
    debug "zfs_send: Creating local fifo $fifo"
    mkfifo "${fifo}" || \
        die "zfs_send: Could not setup fifo $fifo"
    local_fifos="${fifo} $local_fifos"
    result="${fifo}"
}

remote_launch () {

    local name="$1"
    local script_content="$2"
    local script="$remote_tmp/${name}.script"

    ##
    # Push the script to the remote host
    ##

    debug "zfs_send: Remote launching: $script_content"

    echo "$script_content" | $remote_ssh "cat >$script; chmod +x $script"

    $remote_ssh "/usr/bin/screen -d -m $script"

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
        debug "zfs_send: Starting local cat from $target_fifo to $flat_file"
        ( cat $target_fifo 1> $flat_file 2> $tmpdir/flat_file.error ; echo $? > $tmpdir/flat_file.errorlevel ) &
        local_watch="flat_file $local_watch"
        
    else
        remote_fifo flat_file
        target_fifo="$result"
        debug "zfs_send: Starting remote cat from $target_fifo to $flat_file"
        remote_launch "flat_file" "cat $target_fifo 1> $flat_file 2> $remote_tmp/flat_file.error ; echo $? > $tmpdir/flat_file.errorlevel"
        remote_watch="flat_file $remote_watch"
    fi
else
    # To zfs receive
    if [ "$remote_host" == "" ]; then
        # Local
        local_fifo zfs_receive
        target_fifo="$result"
        debug "zfs_send: Starting local zfs receive $target_fifo to ${target_folder}"
        ( cat $target_fifo | zfs receive -F -vu ${target_prop} ${target_folder} \
            2> $tmpdir/zfs_receive.error ; echo $? > $tmpdir/zfs_receive.errorlevel ) &
        local_watch="$zfs_receive $local_watch"
    else
        # Remote
        remote_fifo zfs_receive
        target_fifo="$result"
        debug "zfs_send: Starting remote zfs receive $target_fifo to ${target_folder}"
        remote_launch "zfs_receive" "cat $target_fifo | zfs receive -F -vu ${target_prop} ${target_folder} \
            2> $remote_tmp/zfs_receive.error ; echo $? > $remote_tmp/zfs_receive.errorlevel"
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
        debug "zfs_send: Starting remote mbuffer from $target_mbuffer_fifo to $target_fifo"
        remote_launch "mbuffer" "cat $target_mbuffer_fifo | \
            /opt/csw/bin/mbuffer -q -s 128k -m 128M --md5 -l $remote_tmp/mbuffer.log \
            2> $remote_tmp/mbuffer.error \
            | cat > $target_fifo ; \
            echo \$? > $remote_tmp/mbuffer.errorlevel"
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
    debug "zfs_send: Starting remote gzip decompression from $target_gzip_fifo to $target_fifo"
    remote_launch "gzip" "cat $target_gzip_fifo | \
        gzip -d --stdout 2> $remote_tmp/gunzip.error | \
        cat > $target_fifo ; \
        echo \$? > $remote_tmp/gunzip.errorlevel "
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
    debug "zfs_send: Starting remote lz4 decompression from $target_lz4_fifo to $target_fifo"
    remote_launch "lz4" "cat $target_lz4_fifo | \
        $lz4 -d 2> $remote_tmp/lz4.error | \
        cat > $target_fifo ; \
        echo \$? > $remote_tmp/lz4.errorlevel"
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
    debug "zfs_send: Starting remote openssl decrypt from $target_ssl_fifo to $target_fifo"
    remote_launch "openssl" "openssl aes-256-cbc -d -pass file:$bbcp_key <$target_ssl_fifo 1> $target_fifo \
        2> $remote_tmp/openssl.error ; echo $? > $remote_tmp/openssl.errorlevel"
    remote_watch="openssl $remote_watch"
    sleep 2
    target_fifo="$target_ssl_fifo"
fi


##
# BBCP
##

if [ "$bbcp_streams" -ne 0 ]; then
    # Source FIFO
    local_fifo bbcp
    target_bbcp_fifo="$result"
    debug "zfs_send: Starting bbcp pipe from local $target_bbcp_fifo to remote $target_fifo"
    ( $bbcp -V -o -s $bbcp_streams -P 300 -N io "$target_bbcp_fifo" "root@${remote_host}:${target_fifo}" 1> $tmpdir/bbcp.log \
        2> $tmpdir/bbcp.error ; echo $? > $tmpdir/bbcp.errorlevel ) &
    target_fifo="$target_bbcp_fifo"
    local_watch="bbcp $local_watch"
    sleep 10
fi
    

##
# SSH
##

if [ "$bbcp_streams" -eq 0 ] && [ "$remote_host" != "" ]; then
    local_fifo ssh
    target_ssh_fifo="$result"
    debug "zfs_send: Starting ssh pipe from local $target_ssh_fifo to remote $target_fifo"
        ( cat $target_ssh_fifo | $remote_ssh "cat > $target_fifo" 2> /$tmpdir/ssh.error ; echo $? > $tmpdir/ssh.errorlevel ) &
    target_fifo="$target_ssh_fifo"
    local_watch="ssh $local_watch"
    sleep 3
fi

##
# OpenSSL Encrypt
##

if [ "$bbcp_encrypt" == 'true' ]; then
    # Setup was handled when target decrypt was configured
    local_fifo openssl
    source_ssl_fifo="$result"
    debug "zfs_send: Starting local openssl encrypt from $source_ssl_fifo to $target_fifo"
    ( cat "$source_ssl_fifo" | \
        openssl aes-256-cbc -pass file:$bbcp_key \
        2> "$tmpdir/openssl.error" | \
        cat > "$target_fifo" ; echo $? > $tmpdir/openssl.errorlevel ) &
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
    debug "zfs_send: Starting local lz4 compression from $source_lz4_fifo to $target_fifo"
    ( cat "$source_lz4_fifo" | \
        $lz4 -${lz4_level} 2> "$tmpdir/lz4.error" | \
        cat > "$target_fifo" ; \
        echo $? > "$tmpdir/lz4.errorlevel" ) &
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
    debug "zfs_send: Starting local gzip compression from $source_gzip_fifo to $target_fifo"
    ( cat "$source_gzip_fifo" | \
        gzip -${gzip_level} --stdout 2> "$tmpdir/gzip.error" | \
        cat > "$target_fifo" ; echo $? > "$tmpdir/gzip.errorlevel" ) &
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
    debug "zfs_send: Starting local mbuffer from $source_mbuffer_fifo to $target_fifo"
    ( cat "$source_mbuffer_fifo" | \
        $mbuffer -q -s 128k -m 128M --md5 -l "$tmpdir/mbuffer.log" \
        2> $tmpdir/mbuffer.error | \
        cat > "$target_fifo" ; \
        echo $? > "$tmpdir/mbuffer.errorlevel" ) &
    target_fifo="$source_mbuffer_fifo"
    local_watch="mbuffer $local_watch"
    sleep 2
fi

##
# zfs send
##

if [ "$replicate" == 'true' ]; then
    send_options="-R"
else
    send_options=
fi

DEBUG set -x

debug "zfs_send: Starting zfs send to $target_fifo"
echo "zfs send $send_options $last_snap 2> $tmpdir/zfs_send.error 1> $target_fifo ; echo $? > $tmpdir/zfs_send.errorlevel"
( zfs send -P $send_options $last_snap 1> $target_fifo ; echo $? > $tmpdir/zfs_send.errorlevel ) &

local_watch="zfs_send $local_watch"

debug "zfs_send: Starting watch loop"

##
# Watch the running processes for completion or failure
##
if [ "$remote_host" != "" ]; then
    # Launch remote monitor script
    
    cat << 'MONITOR' > $tmpdir/remote_monitor.sh
#!/bin/bash

running='true'
remote_tmp="$1"
watch="$2"

while [ "$running" == 'true' ]; do
    for process in $watch; do
        errfile="${remote_tmp}/${process}.errorlevel"
        if [ ! -f ${remote_tmp}/${process}.complete ] && [ -f $errfile ]; then
            # This process has ended
            errlvl=`cat $errfile`
            if [ $errlvl -eq 0 ]; then
                touch ${remote_tmp}/${process}.complete
                complete="$process $complete"
            else
                touch ${remote_tmp}/${process}.fail
                running='false'
            fi
        fi
    done

    # Determine if all processes are complete
    finished='true'
    for process in $watch; do
        if [[ $complete != *${process}* ]]; then
            finished='false'
        fi
    done

    if [ "$finished" == 'true' ]; then
        touch ${remote_tmp}/remote.complete
        running='false'
    fi

    sleep 5

done
MONITOR


    scp $tmpdir/remote_monitor.sh "root@${remote_host}:/${remote_tmp}/monitor.sh"

    $remote_ssh "chmod +x $remote_tmp/monitor.sh"
    remote_launch "monitor" "$remote_tmp/monitor.sh \"$remote_tmp\" \"$remote_watch\" ; echo $? $remote_tmp/monitor.errorlevel"

fi

# Local monitor script

running='true'
watch="$local_watch"
success='false'

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
                touch ${tmpdir}/${process}.fail
                running='false'
            fi
        fi
    done

    # Determine if all processes are complete
    finished='true'
    for process in $watch; do
        if [[ $complete != *${process}* ]]; then
            finished='false'
        fi
    done

    # Check remote status
    remote_failed=`$remote_ssh "ls -1 ${remote_tmp}/*.fail 2> /dev/null"`
    remote_finished=`$remote_ssh "ls -1 ${remote_tmp}/remote.complete 2> /dev/null"`

    if [ "$remote_failed" != "" ]; then
        running='false'
    fi

    if [ "$finished" == 'true' ] && [ "$remote_finished" == "${remote_tmp}/remote.complete" ]; then
        running='false'
        success='true'
    fi

    sleep 5

done

DEBUG set +x

##
# Report success/failure
##

if [ "$success" == 'true' ]; then
    notice "zfs_send: Job completed successfully."
else
    error "zfs_send: Job failed."
fi

##
# Clean up 
##

if [ "$success" == 'false' ]; then
    # Kill running processes

    /bin/true


else
    # Clean up temp space

    /bin/true




fi
    




##
# Collect job component error levels and report failures
##

errorlevels=`ls -1 $tmpdir/*.errorlevel`
for errorlevel in $errorlevels; do
    echo "local $errorlevel = $(cat $errorlevel)"
done

errors=`ls -1 $tmpdir/*.error`
for error in $errors; do
    echo "local ${error}:"
    cat $error
done

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










