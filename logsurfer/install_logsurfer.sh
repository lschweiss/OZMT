#! /bin/bash

cd $( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
. ../zfs-tools-init.sh

rm -rf logsurfer-1.8

tar zxf logsurfer-1.8.tar.gz

cd logsurfer-1.8

./configure --prefix=/usr && \
make && \
make install
