# sourced by the run-*.sh scripts (host side)
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROLE_DIR=$(dirname "$TESTS_DIR")
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
TEST_IMAGE=${TEST_IMAGE:-localhost/ansible-role-disk-tests:latest}
WORK_DIR=${WORK_DIR:-${TMPDIR:-/var/tmp}/ansible-role-disk-tests}
CACHE_DIR=${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ansible-role-disk-tests}

ensure_image() {
  "$CONTAINER_ENGINE" image inspect "$TEST_IMAGE" >/dev/null 2>&1 || "$TESTS_DIR/build-image.sh"
}
