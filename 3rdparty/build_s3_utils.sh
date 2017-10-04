#! /bin/bash

# Expects version on command line


tar zxf sg3_utils-${1}.tgz
cd sg3_utils-${1}
./configure --bindir=/opt/ozmt/bin/$(uname) --libdir=/opt/ozmt/lib/$(uname) --mandir=/opt/ozmt/man  CFLAGS=-std=c99
make install
cd ..

