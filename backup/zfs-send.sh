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

while getopts s:t:f:l:h:mbeg:zrpFk:L:R: opt; do
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
    debug "zfs_send: first_snap no specified, set to origin"
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

###
# Verify remote host
###


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
    $timeout 1m $remote_ssh mkfifo ${remote_tmp}/${1} || \
        die "zfs_send: Could not setup remote fifo $1 on host $remote_host"
    target_fifos="${remote_tmp}/${1} $target_fifos"
    echo -n "${remote_tmp}/${1}"
}

local_fifo () {
    mkfifo $1 || \
        die "zfs_send: Could not setup fifo ${tmpdir}/${1}"
    local_fifos="${tmpdir}/${1} $local_fifos"
    echo -n "${tmpdir}/${1}"
}


#TODO: Build from target to source connecting fifos as we build


##
# zfs receive or flat file
##

if [ "$flat_file" == 'true' ]; then
    # To flat file
    if [ "$remote_host" == "" ]; then
        target_fifo=`local_fifo flat_file.in`
        ( cat $target_fifo 1> $flat_file 2> $tmpdir/flat_file.error ; echo $? > $tmpdir/flat_file.errorlevel ) &       
    else
        target_fifo=`remote_fifo flat_file.in`
        $remote_ssh "nohup cat $target_fifo 1> $flat_file 2> $remote_tmp/flat_file.error &"
    fi
else
    # To zfs receive
    if [ "$remote_host" == "" ]; then
        # Local
        target_fifo=`local_fifo zfs_receive.in`
        ( cat $target_fifo | zfs receive -F -vu ${target_prop} ${target_folder} \
            2> $tmpdir/zfs_receive.error ; echo $? > $tmpdir/zfs_receive.errorlevel ) &
    else
        # Remote
        target_fifo=`remote_fifo zfs_receive.in`
        $remote_ssh "( nohup cat $target_fifo | zfs receive -F -vu ${target_prop} ${target_folder} \
            2> $remote_tmp/zfs_receive.error ; echo $? > $remote_tmp/zfs_receive.errorlevel ) &"
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
    if [ [ "$flat_file" == 'false' ] && [ "$remote_host" != "" ] ]; then
        target_mbuffer_fifo=`remote_fifo target.mbuffer.in`
        $remote_ssh "( nohup mbuffer -q -s 128k -m 128M --md5 -l $remote_tmp/target.mbuffer.log \
            -i $target_mbuffer_fifo -o $target_fifo 1>/dev/null \
            2> $remote_tmp/target.mbuffer.error \
            < /dev/null ; echo $? > $remote_tmp/target.mbuffer.errorlevel ) &"
        target_fifo="$target_mbuffer_fifo"
    fi
fi

##
# gzip - Decompress
##

if [ [ "$gzip_level" -ne 0 ] && [ "$flat_file" == 'false' ] && [ "$remote_host" != "" ] ]; then
    target_gzip_fifo=`remote_fifo target.gzip`
    $remote_ssh "( nohup gzip -d $target_gzip_fifo 1> $target_fifo 2> $remote_tmp/target.gzip.error ; \
        echo $? > $remote_tmp/target.gzip.errorlevel ) &"
    target_fifo="$target_gzip_fifo"
fi

##
# LZ4     
##

if [ [ "$lz4_level" -ne 0 ] && [ "$flat_file" == 'false' ] && [ "$remote_host" != "" ] ]; then
    target_lz4_fifo=`remote_fifo target.lz4`
    $remote_ssh "( nohup $lz4 -d $target_lz4_fifo $target_fifo 2> $remote_tmp/target.lz4.error ; \
        echo $? > $remote_tmp/target.lz4.errorlevel ) &"
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
    target_ssl_fifo=`remote_fifo target_ssl`

    # Start openssl
    $remote_ssh "( nohup openssl aes-256-cbc -d -pass file:$bbcp_key <$target_ssl_fifo 1> $target_fifo \
        2> $remote_tmp/target_ssl.error ; echo $? > $remote_tmp/target_ssl.errorlevel ) &"

    target_fifo="$target_ssl_fifo"
fi


##
# BBCP
##

if [ "$bbcp_streams" -ne 0 ]; then
    # Source FIFO
    target_bbcp_fifo=`local_fifo bbcp_fifo`
    ( $bbcp -s $bbcp_streams --progress 300 --pipe i $target_bbcp_fifo root@${remote_host}:${target_fifo} 1> $tmpdir/bbcp.log \
        2> $tmpdir/bbcp.error < /dev/null ; echo $? > $tmpdir/bbcp.errorlevel ) &
fi
    

##
# SSH
##

if [ [ "$bbcp_streams" -eq 0 ] && [ "$remote_host" != "" ] ]; then
    target_ssh_fifo=`local_fifo ssh_fifo`
        ( cat $target_ssh_fifo | $remote_ssh "cat > $target_fifo" 2> /$tmpdir/ssh.error ; echo $? > /tmpdir/ssh.errorlevel ) &
    target_fifo="$target_ssh_fifo"
fi

##
# OpenSSL Encrypt
##

if [ "$bbcp_encrypt" == 'true' ]; then
    # Setup was handled when target decrypt was configured
    source_ssl_fifo=`local_fifo source_ssl`
    ( openssl aes-256-cbc -pass file:$bbcp_key <$source_ssl_fifo 1> $target_fifo \
        2> $tmpdir/source_ssl.error ; echo $? > $tmpdir/source_ssl.errorlevel ) &
    target_fifo="$target_ssl_fifo"
fi

##
# gpg Encrypt
##

#TODO: Redo backup to glacier to use this send routine.

##
# LZ4
##

if [ "$lz4_level" -ne 0 ]; then
    source_lz4_fifo=`local_fifo source_lz4`
    ( $lz4 -${lz4_level} $source_lz4_fifo $target_fifo 2> /$tmpdir/lz4.error ; echo $? > /tmpdir/lz4.errorlevel ) &
    target_fifo="$source_lz4_fifo"
fi

##
# gzip
##

if [ "$gzip_level" -ne 0 ]; then
    source_gzip_fifo=`local_fifo source_gzip`
    ( $gzip -${gzil_level} --stdout $source_gzip_fifo > $target_fifo 2> /tmpdir/gzip.error ; echo $? /tmpdir/gzip.errorlevel ) &
    target_fifo="$source_gzip_fifo"
fi


##
# mbuffer - Send end
##

if [ "$mbuffer_use" == 'true' ]; then
    # Source end
    if [ "$flat_file" == 'false' ]; then
        source_mbuffer_fifo=`remote_fifo target.mbuffer.in`
        ( mbuffer -q -s 128k -m 128M --md5 -l $tmpdir/source_mbuffer.log \
            -i $source_mbuffer_fifo -o $target_fifo 1>/dev/null \
            2> $tmpdri/source_mbuffer.error \
            < /dev/null ; echo $? > $tmpdir/source_mbuffer.errorlevel ) &
        target_fifo="$source_mbuffer_fifo"
    fi
fi

##
# zfs send
##






