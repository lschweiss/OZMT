#! /bin/bash

tcpdump -i $1 -nn -vvv -s 1500 -c 1 'ether[20:2] == 0x2000'
