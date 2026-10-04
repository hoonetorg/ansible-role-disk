gpt $D1 mkpart t-p1 1MiB 300MiB mkpart old 300MiB 400MiB
luks ${D1}-part2
parted -s $D1 rm 2
partprobe $D1
settle
