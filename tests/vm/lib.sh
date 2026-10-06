# helpers for prepare.sh / verify.sh / reset.sh (prepended to the script, runs as root in the test VM)
set -euo pipefail
D1=/dev/disk/by-id/virtio-tdisk1
D2=/dev/disk/by-id/virtio-tdisk2
D3=/dev/disk/by-id/virtio-tdisk3
# passphrase of "foreign" LUKS containers created by prepare scripts (not the role's test passphrase)
FOREIGN_PW=foreign-luks-passphrase

settle() { udevadm settle; }
# negated check that also works under set -e ("! cmd" never stops a script): not <command...>
not() { if "$@"; then echo "check failed, command succeeded: $*" >&2; return 1; fi; }
# gpt <disk> <parted mkpart args...>: new GPT with partitions, e.g. gpt $D1 mkpart a 1MiB 300MiB
gpt()  { local d=$1; shift; parted -s "$d" mklabel gpt "$@"; partprobe "$d"; settle; }
luks() { printf %s "$FOREIGN_PW" | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 -q "$1" -; }
# two filesystems at once: btrfs plus an ext4 superblock at the start (blkid -p reports nothing for this)
mixed() {
  mkfs.btrfs -q -f "$1"
  truncate -s 64M /root/e4.img; mkfs.ext4 -q -F /root/e4.img
  dd if=/root/e4.img of="$1" bs=4096 count=1 conv=notrunc status=none; rm -f /root/e4.img; settle
}
# canary files: put writes random data into <dir> and remembers its checksum, check compares
canary_put()   { head -c 1M /dev/urandom > "$1/canary"; sha256sum "$1/canary" > "/root/canary$(echo "$1" | tr / _).sha"; }
canary_check() { sha256sum -c --quiet "/root/canary$(echo "$1" | tr / _).sha"; }
# checksum of the first <MiB> of a device (data of a partition that must survive)
sha_head() { head -c "${2}M" "$1" | sha256sum | cut -d' ' -f1; }
