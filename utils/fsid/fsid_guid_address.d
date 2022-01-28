#!/usr/sbin/dtrace -s -q



fbt::dsl_dataset_sync:entry
{
    printf("fsid_guid: #%a# address:#%a#", args[0]->ds_fsid_guid,
    &args[0]->ds_fsid_guid);
}


