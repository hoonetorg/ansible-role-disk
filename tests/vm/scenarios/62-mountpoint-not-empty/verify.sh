not findmnt -n /t/data > /dev/null
canary_check /t/data
not grep -qE '[[:space:]]/t/data[[:space:]]' /etc/fstab
