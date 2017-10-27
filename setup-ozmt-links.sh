#! /bin/bash

#
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
. zfs-tools-init.sh


# Create symlinks in /usr/sbin for ozmt tools

rm -f /usr/sbin/ozmt-*

ln -s ${TOOLS_ROOT}/snapshots/snapjobs-mod.sh /usr/sbin/ozmt-snapjobs-mod.sh
ln -s ${TOOLS_ROOT}/snapshots/snapjobs-mod.sh /usr/sbin/ozmt-snapjobs-add.sh
ln -s ${TOOLS_ROOT}/snapshots/snapjobs-del.sh /usr/sbin/ozmt-snapjobs-del.sh
ln -s ${TOOLS_ROOT}/snapshots/snapjobs-show.sh /usr/sbin/ozmt-snapjobs-show.sh

ln -s ${TOOLS_ROOT}/pools_filesystems/setup-filesystems.sh /usr/sbin/ozmt-setup-filesystems.sh

ln -s ${TOOLS_ROOT}/rsync/sync_snap_folder.sh /usr/sbin/ozmt-sync-snap-folder.sh

ln -s ${TOOLS_ROOT}/utils/fast-zpool-export.sh /usr/sbin/ozmt-fast-zpool-export.sh
ln -s ${TOOLS_ROOT}/utils/fast-zpool-import.sh /usr/sbin/ozmt-fast-zpool-import.sh
ln -s ${TOOLS_ROOT}/utils/zpool-cache-detach.sh /usr/sbin/ozmt-zpool-cache-detach.sh
ln -s ${TOOLS_ROOT}/utils/zpool-cache-attach.sh /usr/sbin/ozmt-zpool-cache-attach.sh
ln -s ${TOOLS_ROOT}/utils/zfs-cache-refresh.sh /usr/sbin/ozmt-zfs-cache-refresh.sh
ln -s ${TOOLS_ROOT}/utils/zfs-rollback-folders.sh /usr/sbin/ozmt-zfs-rollback-folders.sh
ln -s ${TOOLS_ROOT}/utils/remove-quota.sh /usr/sbin/ozmt-remove-quota.sh
ln -s ${TOOLS_ROOT}/utils/watch-jobs.sh /usr/sbin/ozmt-watch-jobs.sh
ln -s ${TOOLS_ROOT}/utils/watch-zfs-debug.sh /usr/sbin/ozmt-watch-zfs-debug.sh
ln -s ${TOOLS_ROOT}/utils/locate-disks/locate-inuse-disks.sh /usr/sbin/ozmt-locate-inuse-disks.sh
ln -s ${TOOLS_ROOT}/utils/locate-disks/locate-unused-disks.sh /usr/sbin/ozmt-locate-unused-disks.sh
ln -s ${TOOLS_ROOT}/utils/locate-disks/show-disk-map.sh /usr/sbin/ozmt-show-disk-map.sh
ln -s ${TOOLS_ROOT}/utils/datasets/create-dev-clone.sh /usr/sbin/ozmt-clone-create.sh 
ln -s ${TOOLS_ROOT}/utils/datasets/destroy-dev-clone.sh /usr/sbin/ozmt-clone-destroy.sh 
ln -s ${TOOLS_ROOT}/utils/extended-zpool-status.sh /usr/sbin/ozmt-zpool-status.sh
ln -s ${TOOLS_ROOT}/utils/new-dataset.sh /usr/sbin/ozmt-new-dataset.sh


#ln -s ${TOOLS_ROOT}/samba/samba-trigger.sh /usr/sbin/ozmt-samba-trigger.sh
if [ -f /usr/sbin/ozmt-samba-trigger.sh ]; then
    rm -f /usr/sbin/ozmt-samba-trigger.sh
fi
ln -s ${TOOLS_ROOT}/samba/samba-service.sh /usr/sbin/ozmt-samba-service.sh

ln -s ${TOOLS_ROOT}/vip/vip-trigger.sh /usr/sbin/ozmt-vip-trigger.sh

ln -s ${TOOLS_ROOT}/replication/schedule-replication.sh /usr/sbin/ozmt-schedule-replication.sh
ln -s ${TOOLS_ROOT}/replication/reset-replication.sh /usr/sbin/ozmt-reset-replication.sh
ln -s ${TOOLS_ROOT}/replication/status-sync.sh /usr/sbin/ozmt-status-sync.sh
ln -s ${TOOLS_ROOT}/replication/trigger-replication.sh /usr/sbin/ozmt-trigger-replication.sh
ln -s ${TOOLS_ROOT}/replication/replication-job-runner.sh /usr/sbin/ozmt-replication-job-runner.sh
ln -s ${TOOLS_ROOT}/replication/replication-job-cleaner.sh /usr/sbin/ozmt-replication-job-cleaner.sh

ln -s ${TOOLS_ROOT}/network/enable-network.sh /usr/sbin/ozmt-enable-network.sh
ln -s ${TOOLS_ROOT}/network/disable-network.sh /usr/sbin/ozmt-disable-network.sh

ln -s ${TOOLS_ROOT}/3rdparty/tools/arcstat.pl /usr/sbin/ozmt-arcstat.pl
ln -s ${TOOLS_ROOT}/3rdparty/tools/nfssvrtop /usr/sbin/ozmt-nfssvrtop
ln -s ${TOOLS_ROOT}/3rdparty/tools/zilstat /usr/sbin/ozmt-zilstat

ln -s ${TOOLS_ROOT}/3rdparty/setLEDs.sh /usr/sbin/ozmt-setLEDs.sh



