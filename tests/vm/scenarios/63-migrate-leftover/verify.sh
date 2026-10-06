not findmnt -n /t/data > /dev/null
canary_check /t/data
[ -d /t/data.pre-ansible ]
