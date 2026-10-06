type_of() { stat -c %C "$1" | cut -d: -f3; }
semanage fcontext -d '/t/top(/.*)?'
restorecon -R -T 0 /t/top
echo "after restorecon through /t/top: /t/home is $(type_of /t/home), /t/home/user/file is $(type_of /t/home/user/file)"
[ "$(type_of /t/home)" = default_t ]
[ "$(type_of /t/home/user/file)" = default_t ]
