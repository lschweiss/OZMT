#! /bin/bash

# Expects version on command line


tar zxf sdparm-${1}.tgz
cd sdparm-${1}
./configure --bindir=/opt/ozmt/bin/$(uname) --libdir=/opt/ozmt/lib/$(uname) --mandir=/opt/ozmt/man  CFLAGS=-std=c99
make install
cd ..

