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

# update-cifs-property.sh
#
# A one time run utility to change cifs property to be relative and more
# readable.


# Find our source and change to the directory
if [ -f "${BASH_SOURCE[0]}" ]; then
    my_source=`readlink -f "${BASH_SOURCE[0]}"`
else
    my_source="${BASH_SOURCE[0]}"
fi
cd $( cd -P "$( dirname "${my_source}" )" && pwd )

. ../zfs-tools-init.sh


# Collect cifs:template

folders=`zfs get -r -s local -o name -H ${zfs_cifs_property}:template`

for folder in $folders; do
    template=`zfs get -o value -H ${zfs_cifs_property}:template $folder`

    IFS=':'
    read -r conf_type conf_name <<< "$template"
    unset IFS

    debug "Config type: $conf_type  Config name: $conf_name"
    case $conf_type in
        'dataset')
            #template_config_file="/${pool}/zfs_tools/etc/samba/${dataset_name}/${conf_name}"
            new_template="dataset:samba/etc/${conf_name}"
            ;;
        'pool')
            new_template="pool:zfs_tools/etc/samba/${conf_name}"
            ;;
        'system')
            new_template="system:/etc/ozmt/samba/${conf_name}"
            ;;
    esac

    echo -e "Updating $folder \t${zfs_cifs_property}:template \t${template} \t${new_template}"

    zfs set ${zfs_cifs_property}:template="${new_template}" $folder


done

echo 

folders=`zfs get -r -s local -o name -H ${zfs_cifs_property}:share`

for folder in $folders; do
    template=`zfs get -o value -H ${zfs_cifs_property}:share $folder`

    dataset_name=`zfs get -o value -H $zfs_dataset_property $folder`

    IFS=':'
    read -r conf_type conf_name <<< "$template"
    unset IFS
    case $conf_type in
        'dataset')
            new_template="pool:zfs_tools/etc/samba/${dataset_name}/${conf_name}"
            ;;
        'pool')
            new_template="pool:zfs_tools/etc/samba/${conf_name}"
            ;;
        'system')
            new_template="system:etc/ozmt/samba/${conf_name}"
            ;;
    esac

    echo -e "Updating $folder \t${zfs_cifs_property}:share \t${template} \t${new_template}"
    
    zfs set ${zfs_cifs_property}:share="${new_template}" $folder

done
