mkfs.btrfs -q -f -L t-mig $D1; settle
mkdir -p /t/.prep; mount $D1 /t/.prep
btrfs subvolume create /t/.prep/data > /dev/null; echo old > /t/.prep/data/old
umount /t/.prep; rmdir /t/.prep
mkdir -p /t/data; canary_put /t/data
