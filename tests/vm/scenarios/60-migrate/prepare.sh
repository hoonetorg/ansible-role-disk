# existing filesystem with the child subvolume (already in use), data in /t/data on the root fs
mkfs.btrfs -q -f -L t-mig $D1; settle
mkdir -p /t/.prep; mount $D1 /t/.prep
btrfs subvolume create /t/.prep/data_images > /dev/null
echo img > /t/.prep/data_images/disk.img
umount /t/.prep; rmdir /t/.prep
mkdir -p /t/data/sub/deeper /t/data/images
mount -o subvol=/data_images $D1 /t/data/images
echo a > /t/data/file; chmod 0640 /t/data/file
echo b > /t/data/sub/deeper/file
ln -s file /t/data/link
chown -R 1234:2345 /t/data/sub; chmod 0750 /t/data
canary_put /t/data
(cd /t/data && find . -xdev \( -type d -printf '%P|%y|%m|%U|%G|-|%l\n' \) -o -printf '%P|%y|%m|%U|%G|%s|%l\n' | sort) > /root/mig-before.txt
