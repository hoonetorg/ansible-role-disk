findmnt -n -o SOURCE /t/data/images | grep -q '\[/data_images\]$'
not findmnt -n /t/data > /dev/null
canary_check /t/data
[ ! -e /t/data.pre-ansible ]
pkill -f disktest-busy || true
