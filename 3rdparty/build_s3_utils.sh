#! /bin/bash

# Expects version on command line


tar zxf sg3_utils-${1}.tgz
cd sg3_utils-${1}
./configure CFLAGS=-std=c99
make install
cd ..
cp -rv /usr/local/share/man/man8/ /usr/share/man/
cp /usr/local/bin/sg* /opt/ozmt/bin/$(uname)/
cp /usr/local/bin/scsi* /opt/ozmt/bin/$(uname)/
