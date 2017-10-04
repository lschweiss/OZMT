#! /bin/bash

# Expects version on command line


tar zxf flock-${1}.tgz
cd flock-${1}
./configure --bindir=/opt/ozmt/bin/$(uname) --libdir=/opt/ozmt/lib/$(uname) --mandir=/opt/ozmt/man  CFLAGS=-std=c99
make install
cd ..

