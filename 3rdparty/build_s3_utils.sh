#! /bin/bash

# Expects version on command line


tar zxf sg3_utils-${1}.tgz
cd sg3_utils-${1}
./configure --prefix=/opt/ozmt/sg3_utils CFLAGS=-std=c99
make install
cd ..
cp -rv sg3_utils/share/man/man8/ /usr/share/man/
