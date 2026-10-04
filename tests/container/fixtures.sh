#!/bin/bash
# disk images for the checks (1000 MiB, sparse), created in $1
set -euo pipefail
mkdir -p "$1"; cd "$1"
mk()   { truncate -s 1000M "$1"; }
luks() { printf x | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 -q "$1" -; }

mk blank.img
mk ext4.img;  mkfs.ext4 -q -F ext4.img
mk luks.img;  luks luks.img
mk btrfs.img; mkfs.btrfs -q btrfs.img
mk swap.img;  mkswap -q swap.img
# two filesystems at once (blkid -p reports nothing for this, wipefs lists both)
mk mixed.img; mkfs.btrfs -q mixed.img; dd if=ext4.img of=mixed.img bs=4096 count=1 conv=notrunc status=none
mk msdos.img; parted -s msdos.img mklabel msdos mkpart primary 1MiB 300MiB
mk gpt1.img;  parted -s gpt1.img mklabel gpt mkpart data 1MiB 300MiB
mk gpt2.img;  parted -s gpt2.img mklabel gpt mkpart data 1MiB 300MiB mkpart rest 300MiB 100%
# old LUKS header in the free space behind partition 1 (leftover of a deleted partition)
cp gpt1.img gpt1_left.img; truncate -s 20M l.tmp; luks l.tmp
dd if=l.tmp of=gpt1_left.img bs=1M seek=300 conv=notrunc status=none; rm l.tmp
# for the create/resize run
mk e2e_new.img; cp gpt1.img e2e_grow.img
