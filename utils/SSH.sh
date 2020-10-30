#! /bin/bash

result=1
count=0
while [ $count -le 4 ]; do
    sleep $(( count * 10 ))
    $SSH_BIN $@
    result=$?
    [ $result -eq 0 ] && break
    count=$(( count + 1 ))
done
exit $result

