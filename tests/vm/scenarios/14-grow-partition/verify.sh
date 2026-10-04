parted -s -m $D2 unit MiB print | grep -q '^1:1.00MiB:768MiB:'
[ "$(sha_head ${D2}-part1 511)" = "$(cat /root/p1.sha)" ]
