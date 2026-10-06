not findmnt -n /t/data > /dev/null
canary_check /t/data
[ ! -e /t/data.pre-ansible ]
