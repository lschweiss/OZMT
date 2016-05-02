# Open ZFS Management Tools #

A collection of tools for managing ZFS pools and folders on various OpenZFS platforms.

Historically started as aws_zfs_tools on bitbucket for managing backup replications to ZFS on Linux on EC2.  Evolved over time to manage many aspects of ZFS.

Almost entirely in bash scripting for portability and ease of extendability.  It does require many different GNU utilities such as sed, grep, etc.

There are few prebuilt binaries packaged along that are difficult to find on several distributions.

*It is currently in an alpha state of development.   Once all configuration scripts are complete a beta will be released.*

### What it does ###

* Manage ZFS datasets in a scalable fashion
    - Each dataset can have
        + Replication to one or more remote ZFS hosts * 
            * Can increase replication performance by utilizing, BBCP, LZ4 compression, gzip compression, and mbuffer.
            * Can encrypt the data in transport
            * Can replicate to AWS S3 or Glacier
        + Snapshot management on any zfs folder
        + Independent Samba server of any compiled from source version
        + Virtual IP address that follows the active copy of the dataset
    - Integrates with High Availablity's RSF-1 for ZFS
        + Adds parallel zpool import and export script to drastically improve pool import and export times
        + Auto starts/stops dataset virtual IPs and Samba services
    - Fail over to a replicated copy * 
* Has extensive reporting capabilities
* Version 0.2 alpha

### How do I get set up? [See the Wiki.](https://bitbucket.org/ozmt/ozmt/wiki/Setup%20Instructions) ###

* Create a config file
* Setup /etc/hosts
* Setup ssh keys
* Configure dataset(s) *
* Configure snapshot jobs
* Configure replication * 
* Configure virtual IP address(s) *


\* Development in progress.   Methods exist but are currently somewhat manual.