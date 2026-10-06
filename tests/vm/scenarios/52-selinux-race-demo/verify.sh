set -x
type_of() { stat -c %C "$1" | cut -d: -f3; }
semanage fcontext -l -C > /root/fcontext.txt
grep -qE '^/t/top\(/\.\*\)\?[[:space:]]+all files[[:space:]]+<<None>>' /root/fcontext.txt
[ "$(type_of /t/home)" = user_home_dir_t ]
# nothing would be relabeled (for the <<none>> path restorecon only warns "no default label")
rn=$(restorecon -Rnv /t/top /t/home 2>&1); echo "$rn"; not grep -q "Would relabel" <<< "$rn"
canary_check /t/home/user
