parted -s $D1 mklabel msdos mkpart primary 1MiB 100%
partprobe $D1
settle
