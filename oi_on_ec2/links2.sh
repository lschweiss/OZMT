#!/bin/bash

DISK=$1
DEVICE_ID=$2

if ! [ $2 ] ; then
  echo "$0 DISK DEVICE_ID"
  exit 1
fi

DROOT="../../devices/xpvd/xdf@"

#c0t0d0p0 -> ../../devices/xpvd/xdf@2048:q
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:q" "${DISK}p0"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:q,raw" "${DISK}p0"

#c0t0d0p1 -> ../../devices/xpvd/xdf@2048:r
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:r" "${DISK}p1"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:r,raw" "${DISK}p1"

#c0t0d0p2 -> ../../devices/xpvd/xdf@2048:s
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:s" "${DISK}p2"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:s,raw" "${DISK}p2"

#c0t0d0p3 -> ../../devices/xpvd/xdf@2048:t
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:t" "${DISK}p3"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:t,raw" "${DISK}p3"

#c0t0d0p4 -> ../../devices/xpvd/xdf@2048:u
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:u" "${DISK}p4"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:u,raw" "${DISK}p4"

#c0t0d0s0 -> ../../devices/xpvd/xdf@2048:a
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:a" "${DISK}s0"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:a,raw" "${DISK}s0"

#c0t0d0s1 -> ../../devices/xpvd/xdf@2048:b
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:b" "${DISK}s1"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:b,raw" "${DISK}s1"

#c0t0d0s10 -> ../../devices/xpvd/xdf@2048:k
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:k" "${DISK}s10"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:k,raw" "${DISK}s10"

#c0t0d0s11 -> ../../devices/xpvd/xdf@2048:l
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:l" "${DISK}s11"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:l,raw" "${DISK}s11"

#c0t0d0s12 -> ../../devices/xpvd/xdf@2048:m
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:m" "${DISK}s12"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:m,raw" "${DISK}s12"

#c0t0d0s13 -> ../../devices/xpvd/xdf@2048:n
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:n" "${DISK}s13"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:n,raw" "${DISK}s13"

#c0t0d0s14 -> ../../devices/xpvd/xdf@2048:o
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:o" "${DISK}s14"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:o,raw" "${DISK}s14"

#c0t0d0s15 -> ../../devices/xpvd/xdf@2048:p
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:p" "${DISK}s15"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:p,raw" "${DISK}s15"

#c0t0d0s2 -> ../../devices/xpvd/xdf@2048:c
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:c" "${DISK}s2"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:c,raw" "${DISK}s2"

#c0t0d0s3 -> ../../devices/xpvd/xdf@2048:d
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:d" "${DISK}s3"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:d,raw" "${DISK}s3"

#c0t0d0s4 -> ../../devices/xpvd/xdf@2048:e
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:e" "${DISK}s4"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:e,raw" "${DISK}s4"

#c0t0d0s5 -> ../../devices/xpvd/xdf@2048:f
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:f" "${DISK}s5"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:f,raw" "${DISK}s5"

#c0t0d0s6 -> ../../devices/xpvd/xdf@2048:g
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:g" "${DISK}s6"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:g,raw" "${DISK}s6"

#c0t0d0s7 -> ../../devices/xpvd/xdf@2048:h
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:h" "${DISK}s7"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:h,raw" "${DISK}s7"

#c0t0d0s8 -> ../../devices/xpvd/xdf@2048:i
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:i" "${DISK}s8"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:i,raw" "${DISK}s8"

#c0t0d0s9 -> ../../devices/xpvd/xdf@2048:j
cd /dev/dsk/
ln -fs "${DROOT}${DEVICE_ID}:j" "${DISK}s9"
cd /dev/rdsk/
ln -fs "${DROOT}${DEVICE_ID}:j,raw" "${DISK}s9"
