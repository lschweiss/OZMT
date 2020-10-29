#! /bin/bash

result=1
count=1
while [ $count -le 5 ]; do
    $SSH_BIN $@
    result=$?
    [ $result -eq 0 ] && break
    count=$(( count + 1 ))
    sleep 1
done
exit $result

