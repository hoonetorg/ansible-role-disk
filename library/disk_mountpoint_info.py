#!/usr/bin/python
# -*- coding: utf-8 -*-
# Apache-2.0
"""Read-only state of a mountpoint before ansible-role-disk mounts a subvolume on it."""

DOCUMENTATION = r'''
module: disk_mountpoint_info
short_description: State of a mountpoint before mounting (read-only)
description:
  - Reports whether I(path) is a mountpoint, which entries would be hidden by a mount, which mounts lie
    below it and which processes use files below it. Changes nothing.
options:
  path:
    description: Mountpoint.
    type: path
    required: true
  managed:
    description:
      - All mountpoints managed by the role. A managed child that is mounted or an empty directory does not
        count as content (it is mounted again later in the run).
    type: list
    elements: path
    default: []
'''

RETURN = r'''
mounted: {description: path is a mountpoint, type: bool}
exists: {description: path exists, type: bool}
content: {description: entries directly below path that a mount would hide, type: list}
children: {description: managed mounts below path, deepest first, type: list}
unmanaged_children: {description: mounts below path that are not managed by the role, type: list}
busy: {description: "processes using files below path: pid, command, file", type: list}
pre_ansible_exists: {description: "<path>.pre-ansible (left over by a migration) exists", type: bool}
'''

import os
import re

from ansible.module_utils.basic import AnsibleModule


def mountpoints():
    """targets of all mounts (octal escapes of /proc/self/mountinfo decoded)"""
    result = []
    with open('/proc/self/mountinfo') as f:
        for line in f:
            target = line.split()[4]
            result.append(re.sub(r'\\([0-7]{3})', lambda m: chr(int(m.group(1), 8)), target))
    return result


def below(p, base):
    return p == base or p.startswith(base.rstrip('/') + '/')


def busy(base):
    """processes with cwd/root/exe, an open file or a mapped file below base"""
    found = []
    for pid in os.listdir('/proc'):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        proc = os.path.join('/proc', pid)
        try:
            with open(os.path.join(proc, 'comm')) as f:
                comm = f.read().strip()
        except OSError:
            continue
        links = [os.path.join(proc, n) for n in ('cwd', 'root', 'exe')]
        try:
            links += [os.path.join(proc, 'fd', fd) for fd in os.listdir(os.path.join(proc, 'fd'))]
        except OSError:
            pass
        targets = []
        for link in links:
            try:
                targets.append(os.readlink(link))
            except OSError:
                pass
        try:
            with open(os.path.join(proc, 'maps')) as f:
                targets += [line.split(None, 5)[5].strip() for line in f if len(line.split(None, 5)) == 6]
        except OSError:
            pass
        for t in targets:
            if t.startswith('/') and below(t, base):
                found.append('%s %s %s' % (pid, comm, t))
                break
    return sorted(set(found))


def main():
    module = AnsibleModule(
        argument_spec=dict(
            path=dict(type='path', required=True),
            managed=dict(type='list', elements='path', default=[]),
        ),
        supports_check_mode=True,
    )
    path = os.path.normpath(module.params['path'])
    managed = set(os.path.normpath(m) for m in module.params['managed'])
    result = dict(changed=False, mounted=False, exists=os.path.lexists(path), content=[], children=[],
                  unmanaged_children=[], busy=[], pre_ansible_exists=os.path.lexists(path + '.pre-ansible'))

    if os.path.ismount(path):
        result['mounted'] = True
        module.exit_json(**result)
    if not result['exists']:
        module.exit_json(**result)
    if not os.path.isdir(path) or os.path.islink(path):
        module.fail_json(msg='%s exists but is not a directory' % path, **result)

    mounts = mountpoints()
    children = sorted(set(m for m in mounts if below(m, path) and m != path), key=len, reverse=True)
    result['children'] = [m for m in children if m in managed]
    result['unmanaged_children'] = [m for m in children if m not in managed]

    for name in sorted(os.listdir(path)):
        entry = os.path.join(path, name)
        if entry in managed and os.path.isdir(entry) and not os.path.islink(entry):
            if os.path.ismount(entry) or not os.listdir(entry):
                continue
        result['content'].append(entry)

    result['busy'] = busy(path)
    module.exit_json(**result)


if __name__ == '__main__':
    main()
