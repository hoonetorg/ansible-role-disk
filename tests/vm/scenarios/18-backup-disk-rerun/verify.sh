[ "$(blkid -p -o value -s TYPE $D3)" = crypto_LUKS ]
[ ! -e /dev/mapper/t_backup ]
not findmnt -n /t/backup > /dev/null
grep -qE '^t_backup[[:space:]].*noauto' /etc/crypttab
grep -qE '[[:space:]]/t/backup[[:space:]].*noauto' /etc/fstab
