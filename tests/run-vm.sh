#!/bin/bash
# tier 2: the whole role in a throwaway Leap 16.1 VM (qemu inside the test container) - about 15 minutes
#   tests/run-vm.sh            all scenarios
#   tests/run-vm.sh 30 31      scenarios whose name starts with 30 or 31 (plus the scenarios they build on)
# result: $WORK_DIR/vm/summary.txt, logs: $WORK_DIR/vm/logs/; exit code 0 = all OK
# HOLD_VM=1 keeps the VM running afterwards (debugging), KEEP_LOGS=1 keeps the logs also on success
# QEMU_ACCEL=kvm|tcg (default: kvm if /dev/kvm is usable, else tcg = slow software emulation)
source "$(dirname "$0")/common.sh"
ensure_image
mkdir -p "$WORK_DIR/vm" "$CACHE_DIR"
# the test disks are sparse, but a test that writes a lot must not fill the host disk
free_gb=$(df --output=avail -BG "$WORK_DIR" | tail -1 | tr -dc 0-9)
[ "$free_gb" -ge "${MIN_FREE_GB:-4}" ] || { echo "only ${free_gb} GB free in $WORK_DIR, need ${MIN_FREE_GB:-4}"; exit 1; }
if [ -z "${QEMU_ACCEL:-}" ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then QEMU_ACCEL=kvm; else QEMU_ACCEL=tcg; fi
fi
args=(--rm --security-opt label=disable -e QEMU_ACCEL="$QEMU_ACCEL" -e KEEP_LOGS="${KEEP_LOGS:-}" -e HOLD_VM="${HOLD_VM:-}"
      -v "$ROLE_DIR:/roles/ansible-role-disk:ro" -v "$WORK_DIR/vm:/work" -v "$CACHE_DIR:/cache")
[ "$QEMU_ACCEL" = kvm ] && args+=(--device /dev/kvm)
"$CONTAINER_ENGINE" run "${args[@]}" "$TEST_IMAGE" bash /roles/ansible-role-disk/tests/vm/main.sh "$@"
