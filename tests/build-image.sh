#!/bin/bash
# builds the test image (ansible, disk tools, qemu); rerun after changing the Containerfile
source "$(dirname "$0")/common.sh"
"$CONTAINER_ENGINE" build -t "$TEST_IMAGE" -f "$TESTS_DIR/Containerfile" "$TESTS_DIR"
