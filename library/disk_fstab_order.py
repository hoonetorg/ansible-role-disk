#!/usr/bin/python
# -*- coding: utf-8 -*-
# Apache-2.0
"""Keep the fstab lines of ansible-role-disk in one block sorted by mountpoint (parents before children)."""

DOCUMENTATION = r'''
module: disk_fstab_order
short_description: Sort the role's fstab lines by mountpoint
description:
  - ansible.posix.mount appends new lines, so a parent (/var/lib/libvirt) can end up behind its child
    (/var/lib/libvirt/images). systemd orders nested mounts by path anyway, but "mount -a" follows the file order.
  - The lines whose mountpoint is in I(paths) are taken out and inserted again as one block, sorted by
    mountpoint, at the position of the first of them. All other lines (comments included) stay unchanged and in
    place. The lines themselves are not modified.
options:
  paths:
    description: Mountpoints managed by the role.
    type: list
    elements: path
    required: true
  fstab:
    description: fstab file.
    type: path
    default: /etc/fstab
  backup:
    description: Keep a timestamped copy of the old file when it is changed.
    type: bool
    default: true
'''

import os

from ansible.module_utils.basic import AnsibleModule


def mountpoint(line):
    fields = line.split()
    if len(fields) < 2 or fields[0].startswith('#'):
        return None
    return os.path.normpath(fields[1].replace('\\040', ' '))


def reorder(lines, paths):
    """lines with the managed lines sorted by mountpoint, placed where the first of them was"""
    managed = [i for i, line in enumerate(lines) if mountpoint(line) in paths]
    if not managed:
        return lines
    block = sorted((lines[i] for i in managed), key=lambda line: mountpoint(line).split('/'))
    rest = [line for i, line in enumerate(lines) if i not in set(managed)]
    pos = managed[0]
    return rest[:pos] + block + rest[pos:]


def main():
    module = AnsibleModule(
        argument_spec=dict(
            paths=dict(type='list', elements='path', required=True),
            fstab=dict(type='path', default='/etc/fstab'),
            backup=dict(type='bool', default=True),
        ),
        supports_check_mode=True,
    )
    fstab = module.params['fstab']
    paths = set(os.path.normpath(p) for p in module.params['paths'])
    with open(fstab) as f:
        lines = f.readlines()
    if lines and not lines[-1].endswith('\n'):
        lines[-1] += '\n'
    new = reorder(lines, paths)
    result = dict(changed=new != lines)
    if result['changed']:
        result['diff'] = dict(before=''.join(lines), after=''.join(new), before_header=fstab, after_header=fstab)
        if not module.check_mode:
            if module.params['backup']:
                result['backup_file'] = module.backup_local(fstab)
            tmp = fstab + '.ansible-tmp'
            with open(tmp, 'w') as f:
                f.writelines(new)
            module.atomic_move(tmp, fstab)
    module.exit_json(**result)


if __name__ == '__main__':
    main()
