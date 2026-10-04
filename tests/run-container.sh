#!/bin/bash
# tier 1: safety checks of the disk role on image files - no root, no KVM, about 1 minute
# result: $WORK_DIR/container/summary.txt, full log: $WORK_DIR/container/checks.log; exit code 0 = all OK
source "$(dirname "$0")/common.sh"
ensure_image
mkdir -p "$WORK_DIR/container"
"$CONTAINER_ENGINE" run --rm --security-opt label=disable \
  -v "$ROLE_DIR:/roles/ansible-role-disk:ro" -v "$WORK_DIR/container:/work" \
  "$TEST_IMAGE" bash /roles/ansible-role-disk/tests/container/main.sh
