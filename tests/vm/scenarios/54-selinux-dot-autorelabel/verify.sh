set -x
rpm -q selinux-autorelabel selinux-tools || true
journalctl -b -o cat | grep -i relabel || true
type_of() { stat -c %C "$1" | cut -d: -f3; }
[ "$(systemctl show -P ActiveState t-top-relabel.service)" = active ]
[ "$(systemctl show -P ActiveState t-home-relabel.service)" = active ]
[ "$(type_of /t/home/user/file)" = user_home_dir_t ]
echo "/.autorelabel after the boot: $(ls -la /.autorelabel 2>&1)"
rm -f /.autorelabel
canary_check /t/home/user
