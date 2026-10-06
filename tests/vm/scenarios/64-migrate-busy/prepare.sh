mkdir -p /t/data; canary_put /t/data
# argv0 "disktest-busy": reset.sh kills it (pkill -f); the command name stays "sleep"
setsid bash -c 'exec -a disktest-busy sleep 600' < /t/data/canary > /dev/null 2>&1 &
sleep 1
