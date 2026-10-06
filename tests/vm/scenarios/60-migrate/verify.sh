findmnt -n -o SOURCE /t/data | grep -q '\[/data\]$'
findmnt -n -o SOURCE /t/data/images | grep -q '\[/data_images\]$'
[ "$(cat /t/data/images/disk.img)" = img ]
canary_check /t/data
# same tree as before (the mounted child shows the content of its subvolume, -xdev skips it)
diff /root/mig-before.txt <(cd /t/data && find . -xdev \( -type d -printf '%P|%y|%m|%U|%G|-|%l\n' \) -o -printf '%P|%y|%m|%U|%G|%s|%l\n' | sort)
# old directory kept (with the data, without the child mount)
[ -f /t/data.pre-ansible/canary ] && [ -d /t/data.pre-ansible/images ]
not findmnt -n /t/data.pre-ansible/images > /dev/null
grep -qE '[[:space:]]/t/data[[:space:]]+btrfs[[:space:]]' /etc/fstab
grep -qE '[[:space:]]/t/data/images[[:space:]]+btrfs[[:space:]]' /etc/fstab
