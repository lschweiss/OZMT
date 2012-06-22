#! /bin/bash

zpool create -o ashift=12 -o autoexpand=on -o listsnaps=on ctspool \
	raidz1 /dev/xvdf1 /dev/xvdf2 /dev/xvdf3 /dev/xvdf4 /dev/xvdf5 /dev/xvdf6 /dev/xvdf7 /dev/xvdf8 \
	raidz1 /dev/xvdg1 /dev/xvdg2 /dev/xvdg3 /dev/xvdg4 /dev/xvdg5 /dev/xvdg6 /dev/xvdg7 /dev/xvdg8 \
	raidz1 /dev/xvdh1 /dev/xvdh2 /dev/xvdh3 /dev/xvdh4 /dev/xvdh5 /dev/xvdh6 /dev/xvdh7 /dev/xvdh8 \
	raidz1 /dev/xvdi1 /dev/xvdi2 /dev/xvdi3 /dev/xvdi4 /dev/xvdi5 /dev/xvdi6 /dev/xvdi7 /dev/xvdi8 \
	raidz1 /dev/xvdj1 /dev/xvdj2 /dev/xvdj3 /dev/xvdj4 /dev/xvdj5 /dev/xvdj6 /dev/xvdj7 /dev/xvdj8 

