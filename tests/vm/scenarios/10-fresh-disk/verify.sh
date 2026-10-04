[ "$(blkid -o value -s TYPE ${D1}-part1)" = btrfs ]
[ "$(blkid -o value -s TYPE ${D1}-part2)" = crypto_LUKS ]
[ "$(blkid -o value -s TYPE /dev/mapper/t_crypt)" = btrfs ]
grep -qE '^t_crypt[[:space:]]' /etc/crypttab
grep -qE '[[:space:]]/t/home[[:space:]]+btrfs[[:space:]]' /etc/fstab
grep -qE '[[:space:]]/t/plain[[:space:]]+btrfs[[:space:]]' /etc/fstab
findmnt -n /t/home > /dev/null
findmnt -n /t/plain > /dev/null
btrfs subvolume show /t/home/projects > /dev/null
[ "$(stat -c '%u:%g %a' /t/home/projects)" = "1234:1234 750" ]
canary_put /t/home
canary_put /t/plain
