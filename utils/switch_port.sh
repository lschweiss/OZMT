#! /bin/bash

tcpdump -i $1 -c 1 -vvv -nn ether proto 0x88cc 