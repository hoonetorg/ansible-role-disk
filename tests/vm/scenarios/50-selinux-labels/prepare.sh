[ -e /sys/fs/selinux/enforce ] || { echo "SELinux is not enabled in the test VM"; exit 1; }
semanage fcontext -a -t user_home_dir_t '/t/home(/.*)?'
