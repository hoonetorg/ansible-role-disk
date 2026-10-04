gpt $D2 mkpart t-data 1MiB 512MiB
mkfs.ext4 -q -F ${D2}-part1
mkdir -p /root/m && mount ${D2}-part1 /root/m && head -c 1M /dev/urandom > /root/m/canary && umount /root/m
sha_head ${D2}-part1 511 > /root/p1.sha
