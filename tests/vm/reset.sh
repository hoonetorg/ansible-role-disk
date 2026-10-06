# back to blank test disks: unmount /t/*, close t_* mappers, remove t_ / /t/ entries, zero all test disks
pkill -f disktest-busy || true
for m in $(findmnt -rn -o TARGET | grep -E '^/t(/|$)' | sort -r); do umount "$m"; done
for m in $(findmnt -rn -o TARGET | grep '^/run/ansible-disk/' | sort -r); do umount "$m"; done
for n in $(ls /dev/mapper | grep '^t_' || true); do cryptsetup close "$n"; done
sed -i '/^t_/d' /etc/crypttab 2>/dev/null || true
sed -i '\#[[:space:]]/t/#d' /etc/fstab
rm -rf /t /root/canary*.sha /root/*.sha
# local SELinux file context rules (the role's <<none>> rules for /t/..., test rules of prepare scripts)
if command -v semanage > /dev/null; then semanage fcontext -D; fi
systemctl daemon-reload
# discard (not -z: writing zeros would allocate the whole image file on the host); qemu (discard=unmap)
# punches holes into the sparse image files, which read back as zeros
for d in $D1 $D2 $D3; do
  blkdiscard -f "$d" 2> /dev/null
  [ "$(head -c 64M "$d" | tr -d '\0' | wc -c)" = 0 ] || { echo "reset: $d not zeroed"; exit 1; }
  blockdev --rereadpt "$d"
done
settle
