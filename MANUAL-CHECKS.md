# Manual checks for ansible-role-disk

Checks to run by hand on a real host (the automated tests are in `tests/`). Run them after a rollout, after a run
with `-e disk_allow_migrate=true`, after a reboot and after a reinstall of the root filesystem. All commands as
root. The paths are examples (top level of the data filesystem at `/cryptdata`, homes, libvirt, containers,
backup disk `cryptbackup`); use the ones from your inventory.

## 1. Idempotency

Run the playbook a second time, without `disk_allow_migrate`:

- expected: the disk role reports no `changed` tasks
- a mountpoint that still needs a migration stops the run with "… migrate is set for this mount, but migrations
  are not allowed in this run …" - nothing changed; run once with `-e disk_allow_migrate=true`

## 2. Devices and LUKS

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
cryptsetup status cryptdata          # type LUKS2, device = the data partition
grep -v '^#' /etc/crypttab           # backup disks: noauto,nofail
```

## 3. Subvolumes

```bash
btrfs subvolume list /cryptdata      # every subvolume of the inventory (plus snapshots in .snapshots)
```

## 4. Mounts and fstab

```bash
findmnt /home/john                   # SOURCE /dev/mapper/cryptdata[/john], for every mount of the inventory
findmnt --verify --verbose           # fstab: syntax, mountpoints, devices - no errors
grep -n cryptdata /etc/fstab         # the role's lines are one block sorted by mountpoint (parents first)
```

Optional, `mount -a` with nested mounts (nothing may be using them):

```bash
umount /var/lib/libvirt/images /var/lib/libvirt
mount -a
findmnt /var/lib/libvirt /var/lib/libvirt/images    # both mounted again, from their subvolumes
```

## 5. After a migration

```bash
find / /cryptdata -xdev -name '*.pre-ansible' 2>/dev/null   # old directories kept by the role
du -sh /etc/containers /etc/containers.pre-ansible          # same size (per migrated path)
ls -al /etc/libvirt /etc/libvirt.pre-ansible                # same entries
```

Then check the services that use the paths, e.g. `virsh list --all` and start a guest, `podman info`.
Only when everything works: delete the `<path>.pre-ansible` directories yourself (the role never deletes them; as
long as one exists, a migration of that path stops).

## 6. SELinux

```bash
semanage fcontext -l -C
#   /cryptdata(/.*)?      all files   <<None>>     (one line per top-level view, also the backup disks)
cat /etc/selinux/targeted/contexts/files/file_contexts.local   # the same rules as plain text

restorecon -Rnv /cryptdata
#   only "Warning no default label for /cryptdata", no "Would relabel"

restorecon -Rnv /home/john /home/jane /srv/anotherservice \
  /etc/libvirt /var/lib/libvirt /var/lib/libvirt/images /etc/containers /var/lib/containers
#   no output = all labels correct (-n: dry run, changes nothing)

ls -Zd /home/john /srv/anotherservice /etc/libvirt /var/lib/libvirt /var/lib/libvirt/images \
  /etc/containers /var/lib/containers
#   user_home_dir_t, var_t, virt_etc_t, virt_var_lib_t, virt_image_t, etc_t, container_var_lib_t

ls -Zd /home/john /cryptdata/john    # same inode: same label through both paths
matchpathcon /cryptdata/john         # <<none>> (package selinux-tools)
```

Boot autorelabel (`touch /etc/selinux/.autorelabel` or `touch /.autorelabel`, then reboot): on openSUSE Leap 16
both trigger a relabel of the root filesystem and one relabel unit per fstab mount; with the `<<none>>` rules the
labels are the same afterwards (run the checks above again).

## 7. Reboot

```bash
systemctl --failed                                   # empty
findmnt /home/john /var/lib/libvirt /var/lib/libvirt/images   # everything mounted
swapon --show                                        # swap active
systemctl show -p Requires -p After var-lib-libvirt-images.mount | tr ' ' '\n' | grep var-lib-libvirt.mount
#   the child mount waits for its parent (systemd orders nested mounts by path)
```

## 8. Backup disks

```bash
findmnt /cryptbackup                                 # not mounted after boot (noauto)
systemctl start btrbk-backup-backup                  # asks for the passphrase, opens, mounts, backs up
systemctl stop systemd-cryptsetup@cryptbackup.service   # unmounts and closes
```

(Unit names as configured in the btrbk role.)

## 9. If the host does not boot

- single user mode, no snapshot reset (the logs are the evidence):
  ```bash
  journalctl -b -p err | head -50
  systemctl --failed
  ```
- comment out (`#`) the fstab line of the failing mount, reboot, then fix the cause
- the role only renames old directories (`.pre-ansible`) and never deletes data, so nothing is lost
