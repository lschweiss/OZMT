#! /bin/bash
dtrace -qn '
        BEGIN
        {
                last = walltimestamp;
        }

        zfs-dbgmsg
        /walltimestamp - last > 10000000000/
        {
                printf("\n");
        }

        zfs-dbgmsg
        {
                printf("%Y  %s\n", walltimestamp, stringof(arg0));
                last = walltimestamp;
        }
'
