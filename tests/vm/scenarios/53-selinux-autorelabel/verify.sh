set -x
rpm -q selinux-autorelabel selinux-tools || true
journalctl -b -o cat | grep -i relabel || true
type_of() { stat -c %C "$1" | cut -d: -f3; }
# the generated relabel units ran in this boot
[ "$(systemctl show -P ActiveState t-top-relabel.service)" = active ]
[ "$(systemctl show -P ActiveState t-home-relabel.service)" = active ]
[ ! -e /etc/selinux/.autorelabel ]
findmnt -n /t/home > /dev/null
[ "$(type_of /t/home)" = user_home_dir_t ]
# nothing would be relabeled (for the <<none>> path restorecon only warns "no default label")
rn=$(restorecon -Rnv /t/top /t/home 2>&1); echo "$rn"; not grep -q "Would relabel" <<< "$rn"
canary_check /t/home/user
