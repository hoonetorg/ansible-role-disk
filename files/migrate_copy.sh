#!/bin/bash
# migrate_copy.sh <src> <dst>: copies the content of <src> into the empty directory <dst> (ansible-role-disk,
# mounts[].migrate) and compares both trees afterwards; exit 0 only if the copy is complete and identical.
# cp -a keeps owner, mode, timestamps, links, xattrs and SELinux labels, "<src>/." also the attributes of
# <src> itself; --one-file-system: mounts below <src> are not copied (only their mountpoint directory)
set -euo pipefail
src=${1%/}
dst=${2%/}
[ -d "$src" ] && [ -d "$dst" ] || { echo "migrate_copy: $src and $dst must be directories" >&2; exit 2; }
[ -z "$(ls -A "$dst")" ] || { echo "migrate_copy: $dst is not empty" >&2; exit 2; }

cp -a --one-file-system "$src/." "$dst/"

# content: checksums of all regular files ...
sums() { (cd "$1" && find . -xdev -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum); }
if ! cmp -s <(sums "$src") <(sums "$dst"); then
  diff <(sums "$src") <(sums "$dst") >&2 || true
  echo "migrate_copy: content differs" >&2
  exit 1
fi
# ... and metadata of every entry: type, mode, owner, group, size (not of directories: depends on the
# filesystem), link target, SELinux context ("?" without SELinux)
meta() {
  (cd "$1" && find . -xdev \( -type d -printf '%P|%y|%m|%U|%G|-|%l|%Z\n' \) -o -printf '%P|%y|%m|%U|%G|%s|%l|%Z\n' \
     | LC_ALL=C sort)
}
if ! cmp -s <(meta "$src") <(meta "$dst"); then
  diff <(meta "$src") <(meta "$dst") >&2 || true
  echo "migrate_copy: metadata differs" >&2
  exit 1
fi
echo "migrate_copy: $(meta "$dst" | wc -l) entries copied and verified"
