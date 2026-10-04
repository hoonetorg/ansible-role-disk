parted -s -m $D2 unit MiB print | grep -q '^2:768MiB:'
[ -b ${D2}-part2 ]
[ "$(sha_head ${D2}-part1 511)" = "$(cat /root/p1.sha)" ]
