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

snapjobdir="$TOOLS_ROOT/snapshots/jobs"
stagingjobdir="$TOOLS_ROOT/backup/jobs/staging"
ec2backupjobdir="$TOOLS_ROOT/backup/jobs/ec2"
glacierjobdir="$TOOLS_ROOT/backup/jobs/glacier/active"
glacierjobstatus="$TOOLS_ROOT/backup/jobs/glacier/status"

    mkdir -p $snapjobdir
    mkdir -p ${stagingjobdir}
    mkdir -p ${ec2backupjobdir}
    mkdir -p ${glacierjobdir}
    mkdir -p ${glacierjobstatus}

setupzfs () {

    zfspath="$1"
    options="$2"
    snapshots="$3"

    if [ ! -e "/$pool" ]; then
        echo "ERROR: ZFS pool \"$pool\" does not exist!"
        exit 1
    fi

    if [ -e "/$pool/$zfspath" ]; then
        echo "${pool}/${zfspath} already exists, resetting options"
        setzfs "${pool}/${zfspath}" "$options"
    else
        echo "Creating ${pool}/${zfspath} and setting options"
        zfs create -p $pool/$zfspath
        setzfs "${pool}/${zfspath}" "$options"
    fi

    if [ "x$staging" != "x" ]; then
        if [ ! -e "/$staging" ]; then
            echo "ERROR: ZFS Folder for staging backup must be created first!"
            exit 1
        fi
        
        if [ ! -e "/$staging/$pool" ]; then
            zfs create -p $staging/$pool
        fi   
     
        if [ ! -e "/$staging/$pool/$zfspath" ]; then
            zfs create -p $staging/$pool/$zfspath
        fi
        
        setzfs "$staging/$pool/$zfspath" "atime=off checksum=sha256 ${stagingoptions}"
        stagingjobname=`echo "${staging}/${pool}/${zfspath}" | sed s,/,%,g`
        
        echo "crypt=\"$crypt\"" > ${stagingjobdir}/${stagingjobname}
        echo "source_folder=\"$pool/$zfspath\"" >> ${stagingjobdir}/${stagingjobname}
        echo "target_folder=\"${staging}/${pool}/${zfspath}\"" >> ${stagingjobdir}/${stagingjobname}

    fi

    # Setup EC2 backup

    if [ "x$backup" != "x" ]; then
        ec2backupjobname=`echo "${backup}/${pool}/${zfspath}" | sed s,/,%,g`
        echo "source_folder=\"${pool}/${zfspath}\"" > ${ec2backupjobdir}/${ec2backupjobname}
        echo "target_folder=\"${ec2_zfspool}/${pool}/${zfspath}\"" >> ${ec2backupjobdir}/${ec2backupjobname}
    fi

    # Setup Amazon Glacier backup

    if [ "x$glacier" != "x" ]; then
        glacierjobname=`echo "${glacier}/${pool}/${zfspath}" | sed s,/,%,g`
        #TODO: Add logic to make sure this zfs folder is not a decendant of another
        #      that is already being backed up via glacier
        echo "job_name=\"${pool}/${zfspath}\"" | sed s,/,%,g > ${glacierjobdir}/${glacierjobname}
        echo "source_folder=\"${pool}/${zfspath}\"" >> ${glacierjobdir}/${glacierjobname}
        echo "glacier_vault=\"${glacier}\"" >> ${glacierjobdir}/${glacierjobname}
        if [ "x$glacier_rotation" == "x" ]; then
            echo "glacier_rotation=\"${glacier_rotation_days}\"" >> ${glacierjobdir}/${glacierjobname}
        else
            echo "glacier_rotation=\"${glacier_rotation}\"" >> ${glacierjobdir}/${glacierjobname}
        fi
    fi

    # Setup Amazon Glacier file level backup

    if [ "x$glacier_files" != "x" ]; then
        glacierjobname=`echo "FILES%${glacier_files}/${pool}/${zfspath}" | sed s,/,%,g`
        echo "job_name=\"FILES/${pool}/${zfspath}\"" | sed s,/,%,g > ${glacierjobdir}/${glacierjobname}
        echo "source_folder=\"${pool}/${zfspath}\"" >> ${glacierjobdir}/${glacierjobname}
        echo "glacier_vault=\"${glacier_files}\"" >> ${glacierjobdir}/${glacierjobname}
        if [ "x$glacier_rotation" == "x" ]; then
            echo "glacier_rotation=\"${glacier_rotation_days}\"" >> ${glacierjobdir}/${glacierjobname}
        else
            echo "glacier_rotation=\"${glacier_rotation}\"" >> ${glacierjobdir}/${glacierjobname}
        fi
    fi


    jobname=`echo "${pool}/${zfspath}" | sed s,/,%,g`

    # Prep the jobs folders
    for snaptype in $snaptypes; do
        if [ ! -d $snapjobdir/$snaptype ]; then
            mkdir $snapjobdir/$snaptype
        fi
        rm -f $snapjobdir/$snaptype/${jobname}
        if [ "$staging" != "" ]; then
            rm -f $snapjobdir/$snaptype/${stagingjobname}
        fi
    done

    # Create the jobs
    echo "Creating jobs for ${pool}/${zfspath}:"
    echo -e "Job\t\tType\t\tQuantity"
    if [ "$snapshots" != "" ]; then
        for snap in $snapshots; do
            snaptype=`echo $snap|cut -d "|" -f 1`
            snapqty=`echo $snap|cut -d "|" -f 2`
            echo -e "${jobname}\t${snaptype}\t\t${snapqty}"
            echo $snapqty > $snapjobdir/$snaptype/$jobname
            if [ "$staging" != "" ]; then
                echo "x${snapqty}" > $snapjobdir/$snaptype/${stagingjobname}
            fi
        done
    fi
    echo
}

setzfs () {

    local zfsfolder="$1"
    local options="$2"
    local option=""

    if [ ! -e "/$pool" ]; then
        echo "ERROR: ZFS pool \"$pool\" does not exist!"
        exit 1
    fi

    for option in $options; do
        eval zfs set $option $zfsfolder
    done
}


