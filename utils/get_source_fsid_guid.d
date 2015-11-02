fbt::zfs_ioc_dataset_list_next:entry
{
    self->zfs_cmd = args[0];
}

fbt::dsl_dataset_fast_stat:entry
{
    printf("zc_name:-%s- guid:-%#lx-\n",
    stringof(self->zfs_cmd->zc_name),
    args[0]->ds_fsid_guid);
}

fbt::zfs_ioc_dataset_list_next:return
/self->zfs_cmd != NULL/
{
    self->zfs_cmd = NULL;
}

