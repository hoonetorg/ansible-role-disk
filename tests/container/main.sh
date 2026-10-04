#!/bin/bash
# runs inside the test container: fixtures, checks playbook, summary
set -uo pipefail
here=/roles/ansible-role-disk/tests/container
bash "$here/fixtures.sh" /img || { echo "fixtures failed"; exit 1; }
rm -f /work/summary.txt
ANSIBLE_CONFIG=$here/ansible.cfg ansible-playbook "$here/checks.yml" > /work/checks.log 2>&1
rc=$?
if [ -s /work/summary.txt ]; then cat /work/summary.txt; else echo "no summary"; fi
[ $rc -eq 0 ] || { echo "--- FAILED (rc=$rc), last lines of /work/checks.log:"; tail -30 /work/checks.log; }
exit $rc
