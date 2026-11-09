#!/bin/bash
# rebuilds the test image (ansible of the nsbldr image, disk tools, qemu); rerun after changing the Containerfile
# (a changed nsbldr image is picked up by the run scripts without this)
source "$(dirname "$0")/common.sh"
FORCE_BUILD=1 ensure_image
