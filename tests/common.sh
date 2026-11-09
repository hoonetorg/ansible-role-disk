# sourced by the run-*.sh scripts (host side)
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROLE_DIR=$(dirname "$TESTS_DIR")
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
TEST_IMAGE=${TEST_IMAGE:-localhost/ansible-role-disk-tests:latest}
WORK_DIR=${WORK_DIR:-${TMPDIR:-/var/tmp}/ansible-role-disk-tests}
CACHE_DIR=${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ansible-role-disk-tests}

source "$TESTS_DIR/controller.sh"

# test image with the ansible of the nsbldr image (see controller.sh), rebuilt when that changes
ensure_image() {
  mkdir -p "$WORK_DIR"
  controller_prepare "$TESTS_DIR/Containerfile"
}
