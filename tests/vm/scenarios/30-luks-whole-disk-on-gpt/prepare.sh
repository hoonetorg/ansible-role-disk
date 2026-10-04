gpt $D1 mkpart a 1MiB 512MiB mkpart b 512MiB 100%
mkfs.ext4 -q -F ${D1}-part1
mkfs.ext4 -q -F ${D1}-part2
