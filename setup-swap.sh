#! /bin/bash

fdisk /dev/xvdb < fdisk.input
mkswap /dev/xvdb1
swapon /dev/xvdb1
