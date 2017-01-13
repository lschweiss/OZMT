#! /bin/bash

# zfs-tools-init.sh
#
# Chip Schweiss - chip.schweiss@wustl.edu
#
# Copyright (C) 2012 - 2015  Chip Schweiss

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


. ../zfs-tools-init.sh

if [ "x$samba_logfile" != "x" ]; then
    logfile="$samba_logfile"
else
    logfile="$default_logfile"
fi

if [ "x$samba_report" != "x" ]; then
    report_name="$samba_report"
else
    report_name="$default_report_name"
fi

now=`${DATE} +"%F %H:%M:%S%z"`

pools="$(pools)"

source ./samba-functions.sh

samba_populate_datasets

datasets=`samba_datasets $1`

if [ "$datasets" == "" ]; then
    echo "Must input a valid dataset name or pool name with CIFS configured datasets"
    exit 1
fi

if [ "$zlib_version" == "" ]; then
    zlib_version="1.2.8"
fi



build_dataset_samba () {

    local dataset="$1"
    local dataset_folder=`cat $smb_datasets_dir/$dataset`
    local dataset_root=`zfs get -o value -H mountpoint $dataset_folder`
    local build_dir=
    local version=
    local build_options=
    local prefix="${dataset_root}/samba"

    local STMP="${prefix}/build/tmp"
    local zfs_exec=

    MKDIR $STMP


    ##
    # Setup build our environment
    ##

    build_dir="${dataset_root}/samba/build"

    if [ "$samba_version" == "" ]; then
        # See if it is dataset defined
        version=`zfs get -H -o value ${zfs_cifs_property}:sambaversion $dataset_folder`
        if [ "$version" == '-' ]; then
            version="$zfs_samba_default_version" 
            echo "Using default samba version: $version"
        else
            echo "Using dataset defined samba version: $version"
        fi
    else
        version="$samba_version"
        echo "Using environment specified samba version: $version"
    fi      

    # If the dataset has exec off, samba needs to be its own zfs folder with exec on
    zfs_exec=`zfs get -H -o value exec $dataset_folder`
    if [ "$zfs_exec" == 'off' ]; then
        echo "Creating samba zfs folder so things can execute"
        zfs get name ${dataset_folder}/samba 1>/dev/null 2>/dev/null
        if [ $? -ne 0 ]; then
            # Create a zfs folder for samba
            if [ -d ${dataset_root}/samba ]; then
                echo "Dataset is sent with exec=off.  Must create a zfs folder ${dataset_folder}/samba, however a directory already exists."
                return 1
            fi
            zfs create -o exec=on ${dataset_folder}/samba
        fi
    fi

    MKDIR "$build_dir"
    cd $build_dir

    # Get and build zlib
    # zlib not needed unless building Samba with --with-ads

#    echo "Building zlib.."
#
#    if [ -f "$TOOLS_ROOT/3rdparty/zlib-${zlib_version}.tar.gz" ]; then
#        zlib_tar="$TOOLS_ROOT/3rdparty/zlib-${zlib_version}.tar.gz"
#    else
#        wget http://zlib.net/zlib-${zlib_version}.tar.gz
#        zlib_tar="${build_dir}/zlib-${zlib_version}.tar.gz"
#    fi
#
#
#    tar zxf $zlib_tar
#
#    cd zlib-${zlib_version}
#
#    ./configure 2>${STMP}/zlib_configure_${zlib_version}_err_$$.txt 1>${STMP}/zlib_configure_${zlib_version}_out_$$.txt
#    if [ $? -ne 0 ]; then
#        echo "Failed to configure zlib build for $dataset.  Output in ${STMP}/zlib_configure_${zlib_version}_err_$$.txt and ${STMP}/zlib_configure_${zlib_version}_out_$$.txt"
#        return 1
#    else
#        echo "Success!"
#    fi
#
#    make 2>${STMP}/zlib_make_${zlib_version}_err_$$.txt 1>${STMP}/zlib_make_${zlib_version}_out_$$.txt
#    if [ $? -ne 0 ]; then
#        echo "Failed to build zlib for $dataset.  Output in ${STMP}/zlib_make_${zlib_version}_err_$$.txt and ${STMP}/zlib_make_${zlib_version}_out_$$.txt"
#        return 1
#    else
#        echo "Success!"
#    fi
#
#    cp /usr/local/lib/pkgconfig/zlib.pc /opt/csw/lib/pkgconfig/zlib.pc


    # Download Samba
    

    if [ ! -f "${build_dir}/samba-${version}.tar.gz" ]; then
        cd $build_dir
        wget https://download.samba.org/pub/samba/stable/samba-${version}.tar.gz
    fi
    if [ ! -d "${build_dir}/samba-${version}" ]; then
        cd $build_dir
        ${TAR} zxf samba-${version}.tar.gz
    fi

    cd "${build_dir}/samba-${version}"

    if [ "$samba_build_options" == "" ]; then
        # See if it is dataset defined
        build_options=`zfs get -H -o value ${zfs_cifs_property}:buildoptions $dataset_folder`  
        if [ "$build_options" == '-' ]; then
            build_options="--prefix=${prefix} --with-acl-support --with-ldap --with-profiling-data --with-shared-modules=nfs4_acls,vfs_zfsacl,acl_xattr"
        fi
    else
        build_options="$samba_build_options"
    fi

    # Configure and make Samba

    cd ${build_dir}/samba-${version}
    echo "Configuring Samba version $version for $dataset"
    echo "Using configure options: $build_options"
    ./configure $build_options 2>${STMP}/configure_${version}_err_$$.txt 1>${STMP}/configure_${version}_out_$$.txt
    if [ $? -ne 0 ]; then
        echo "Failed to configure samba build for $dataset.  Output in ${STMP}/configure_${version}_err_$$.txt and ${STMP}/configure_${version}_out_$$.txt"
        return 1
    else
        echo "Success!"
        #rm -f ${STMP}/configure_${version}_err_$$.txt ${STMP}/configure_${version}_out_$$.txt
    fi

    echo "Compiling Samba version $version for $dataset"
    make 2>${STMP}/make_${version}_err_$$.txt 1>${STMP}/make_${version}_out_$$.txt
    if [ $? -ne 0 ]; then
        echo "Failed to build samba for $dataset.  Output in ${STMP}/make_${version}_err_$$.txt and ${STMP}/make_${version}_out_$$.txt"
        return 1
    else
        echo "Success!"
        #rm -f ${STMP}/make_${version}_err_$$.txt ${STMP}/make_${version}_out_$$.txt
    fi

    echo "Stopping Samba on $dataset"
    ozmt-samba-service.sh stop $dataset
    echo

    echo "Installing Samba version $version for $dataset"
    make install 2>${STMP}/make_install_${version}_err_$$.txt 1>${STMP}/make_install_${version}_out_$$.txt
    if [ $? -ne 0 ]; then
        echo "Failed to install samba for $dataset.  Output in ${STMP}/make_install_${version}_err_$$.txt and ${STMP}/make_install_${version}_out_$$.txt"
        return 1
    else
        echo "Success!"
        #rm -f ${STMP}/make_${version}_err_$$.txt ${STMP}/make_${version}_out_$$.txt
    fi

    echo "Starting Samba on $dataset"
    ozmt-samba-service.sh start $dataset
    echo



    zfs set ${zfs_cifs_property}:smbd="${prefix}/sbin/smbd" $dataset_folder
    zfs set ${zfs_cifs_property}:nmbd="${prefix}/sbin/nmbd" $dataset_folder
    zfs set ${zfs_cifs_property}:winbindd="${prefix}/sbin/winbindd" $dataset_folder
    zfs set ${zfs_cifs_property}:lib="${prefix}/lib" $dataset_folder
    zfs set ${zfs_cifs_property}:smbcontrol="${prefix}/bin/smbcontrol" $dataset_folder


}


for dataset in $datasets; do

    launch build_dataset_samba $dataset

done

