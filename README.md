# ansible-role-disk

Partitions (parted), LUKS2 containers + crypttab, btrfs filesystems, subvolumes and mounts,
driven by the `disk` dict. Order: parted → LUKS → btrfs (filesystems, subvolumes, mounts).

## Variables

```yaml
disk:
  parted:
    disks:
      - device: /dev/disk/by-id/EXAMPLE_DISK
        partitions:
          - { number: 3, name: data, start: 100GiB, end: 100% }
  luks:
    devices:
      - device: /dev/disk/by-id/EXAMPLE_DISK-part3
        name: data
        cryptpw: "{{ vault_data_passphrase }}"
  btrfs:
    filesystems:
      - device: /dev/mapper/data
        label: data
        subvolumes:
          - name: /home
        mounts:
          - { path: /home, subvol: /home, opts: "compress=zstd" }
```

## Optional keys

| key | default | description |
|-----|---------|-------------|
| `disk.luks.devices[].crypttab_opts` | `luks,discard` | crypttab options, e.g. `luks,discard,noauto,nofail` for a backup disk |
| `disk.luks.devices[].close` | `false` | open the device only temporarily during the run (to create filesystem/subvolumes) and close it again afterwards; a device that was already open before the run is left open |
| `disk.btrfs.filesystems[].mounts[].state` | `mounted` | `present` writes the fstab entry only (for `noauto` mounts) |
| `disk.btrfs.filesystems[].mounts[].migrate` | `false` | this mountpoint may be migrated (existing data moved into the subvolume), see Mounts |
| `disk_allow_migrate` (top-level, not in `disk`) | `false` | allow migrations in this run: `-e disk_allow_migrate=true` |
| `disk.btrfs.filesystems[].mounts[].migrate_stop` | `[]` | systemd units stopped during a migration (started again afterwards if they were active) |
| `disk.selinux` | `auto` | SELinux labels/rules (see SELinux); `auto`: when the kernel runs SELinux |
| `disk.btrfs.filesystems[].subvolumes[].owner` / `group` / `mode` | unset | ownership/permissions of the subvolume root; use numeric ids (the disk role runs before the user role) and quote the mode (`"0700"`) |
| `removable` (on `parted.disks[]`, `luks.devices[]`, `btrfs.filesystems[]`) | inherited, else `false` | device may be missing, see below |
| `disk.parted.disks[].partitions[].force_resize` | `false` | allow growing an existing partition (see Partitioning safety) |

## Partitioning safety

Before parted writes anything, every connected disk is checked; any violation stops the run and nothing is
changed:

- partition table: only GPT; a disk without partition table is only accepted if it is empty (no LUKS,
  signature found by `wipefs`, see Formatting safety); `msdos`, `loop` (filesystem directly on the disk), … stop
- `start` / `end`: `<number><KiB|MiB|GiB|TiB|%>`; absolute values must be whole MiB; `%` values are compared
  with ±1 MiB (parted aligns them, `100%` ends 1 MiB before the disk end because of the GPT backup header)
- existing partition with the requested number: start and end must match; moving or shrinking is never done;
  growing the end only with `force_resize: true` and only into free space directly behind the partition
- new partition: must lie inside the disk, must not overlap any existing partition (also partitions not managed
  by the inventory, e.g. another OS), and `blkid -p -O <start>` must find no leftover data (old LUKS header,
  filesystem) at its start (early check; `blkid` misses several signatures at one place, the final check is
  `wipefs` on the new partition before it is formatted, see Formatting safety)

Values are compared in sectors (parted's MiB output is rounded). After a changed parted run the role waits for
udev (`udevadm settle`) and for the new partition devices (`<disk>-partN` for `/dev/disk/by-*` paths,
`<disk>pN` / `<disk>N` otherwise).

## Formatting safety (LUKS, btrfs)

Before a LUKS container or a btrfs filesystem is created (and before a disk without partition table gets one),
every connected device is probed with `wipefs --no-act`, which lists every signature on it (`blkid -p` reports
"nothing found" when it finds several filesystems). The formatting tools are not relied on:
`cryptsetup luksFormat -q` overwrites anything. Allowed are only:

- an empty device (no signature found)
- a device that already holds the requested type (`crypto_LUKS` resp. `btrfs`): it is opened/used, not formatted

Anything else stops the run before anything is written: another filesystem, a ZFS/RAID member, swap, a
partition table (e.g. LUKS directly on a disk that still has GPT partitions), or several signatures at once.
Remove obsolete data yourself first, e.g. `wipefs -a <partition>` for every old partition, then
`wipefs -a <disk>`.

Limit: only data with a signature known to libblkid can be detected; content without one (e.g. the encrypted payload of a
LUKS container whose header is gone) looks like free space.

## Subvolumes

Subvolumes are created sorted by name, so parents are created before nested children
(`/home` before `/home/projects`, independent of the inventory order) and removed after them.
Names must start with `/`. A missing parent is not created automatically (no `recursive`).

`owner`/`group`/`mode` are applied through a temporary mount of the top level (subvolid=5) under
`/run/ansible-disk/<label>` without fstab changes; skipped in check mode.

## Mounts

Mounts are processed sorted by path, so a parent (`/var/lib/libvirt`) is mounted before its children
(`/var/lib/libvirt/images`), independent of the inventory order. A mount never hides data: before a
mountpoint that is not mounted yet gets its subvolume, the role checks it (module `disk_mountpoint_info`,
read-only) and stops - nothing changed - if

- it contains data (entries that are not managed mountpoints; a managed child that is mounted or an empty
  directory does not count) and `migrate` is not set
- a mount below it is not managed by the role

Managed mounts below it (e.g. `/var/lib/libvirt/images` is mounted, `/var/lib/libvirt` gets its own subvolume)
are unmounted first and mounted again on the new parent later in the same run.

fstab: the role's lines are kept as one block sorted by mountpoint (module `disk_fstab_order`, at the position of
the first of them; other lines stay untouched; backup copy `fstab.<...>~` when reordered), so `mount -a` mounts
parents before children too (systemd does this at boot anyway).

### Migration (`migrate: true` + `disk_allow_migrate`)

Two keys: `migrate: true` in the inventory says which mountpoints may be migrated, `disk_allow_migrate=true`
allows it for one run (`ansible-playbook ... -e disk_allow_migrate=true`; AWX/Ascender/AAP: extra variable or
survey). Without the switch a mountpoint that would need a migration stops the run (nothing changed) and the
message says how to run it. Mounted or empty mountpoints never need it, so normal runs work without it.

For directories that already hold data when the subvolume is introduced (e.g. `/var/lib/containers` created by
the installer, `/etc/libvirt` of an installed libvirt):

1. stop if `<path>.pre-ansible` exists (leftover of an earlier migration) or a process uses files below the path
   (cwd, open file, mapped file; the message lists pid, command and file); units in `migrate_stop` are stopped
2. the subvolume must be empty (checked through a temporary top-level mount)
3. `cp -a --one-file-system <path>/. <subvolume>/` (owner, mode, timestamps, links, xattrs, SELinux labels,
   also of the directory itself), then both trees are compared (checksums of all files, type/mode/owner/size/
   link target/SELinux label of every entry); any difference stops the run, nothing is renamed
4. `<path>` is renamed to `<path>.pre-ansible` (never deleted by the role - delete it yourself when everything
   works), an empty mountpoint is created, the subvolume is mounted, the stopped units are started again

Rerun: the path is mounted, nothing happens. Check mode: only the checks.

```yaml
mounts:
  - { path: /var/lib/containers, subvol: /var_containers, migrate: true }
  - { path: /etc/libvirt, subvol: /etc_libvirt, migrate: true, migrate_stop: [virtqemud.socket, virtqemud.service] }
```

## SELinux

With SELinux (`disk.selinux: auto` and `/sys/fs/selinux` present, or `true`) the role installs
`policycoreutils` + `policycoreutils-python-utils` and

- **top-level views** (`subvol: /` or `subvolid=5`, e.g. `/cryptdata`, also `noauto` backup disks) get the local
  rule `semanage fcontext -a -t '<<none>>' '<path>(/.*)?'`: restorecon never relabels anything through them
- **all other mounts** are labeled through their mountpoint after mounting: `restorecon -v <path>` (root only,
  cheap); recursively (`restorecon -R`) when the mount is new, was migrated or its root had a wrong label
  (e.g. existing subvolumes from before this feature)

Why: a top-level view shows the same inodes as the subvolume mounts (`/cryptdata/john` = `/home/john`).
Relabeling through the top-level path gives them the label of that path (`default_t`), so `/home/john` would
lose `user_home_dir_t` (sshd cannot read `authorized_keys` any more, confined services are denied). The boot
autorelabel of openSUSE Leap 16 (`touch /etc/selinux/.autorelabel`, `touch /.autorelabel` or kernel option
`autorelabel`; all tested: the initrd relabels the root filesystem, then a generated unit per fstab mount) runs
`restorecon -R` for every fstab mount in parallel, so without the rule the result would
depend on the order. A new subvolume has no label at all (`ls -Z` shows `?`, the kernel reports `unlabeled_t`).

Check:

```bash
semanage fcontext -l -C          # local rules: /cryptdata(/.*)?  all files  <<None>>
cat /etc/selinux/targeted/contexts/files/file_contexts.local   # generated from the policy store
                                 # (/var/lib/selinux/targeted/active/file_contexts.local)
restorecon -Rnv /cryptdata       # -n: dry run; only "Warning no default label for /cryptdata", no "Would relabel"
restorecon -Rnv /home/john       # no output = labels correct
ls -Zd /home/john /cryptdata/john    # same inode, same label
```

The rules survive reboots and policy updates; after a reinstall of the root filesystem the role sets them again.

## Removable devices

Every device is checked before its stage (parted disks before parted, LUKS devices after parted,
btrfs devices after the LUKS open): present = exists and is a block device.

- missing and **not removable**: the host fails (`<stage>: <device> is missing ... and not marked removable`)
- missing and **removable**: provisioning is skipped (parted, luksFormat/open, mkfs, subvolumes) with a
  message `<stage>: <device> not connected - provisioning skipped`; **configuration is still written**
  (crypttab, mountpoint directories, fstab), so the disk can be unlocked/mounted as soon as it is plugged in.
  The next run with the disk connected provisions it.

`removable` is inherited, so it is usually only set on one entry:
- a LUKS device `<disk>-part<N>` inherits it from the parted disk `<disk>` (by-id `-partN` naming)
- a btrfs filesystem on `/dev/mapper/<name>` inherits it from the LUKS device `<name>`

Boot safety is validated before anything is changed. For removable devices:
- `crypttab_opts` must contain `noauto` and `nofail`
- every mount of the filesystem must have `noauto` and `nofail` in `opts` and `state: present`

(crypttab(5), systemd.mount(5): without `nofail` the boot waits for the missing device and ends in emergency
mode; without `noauto` the device is unlocked/mounted at boot, and a crypttab `noauto` is overridden by a
mount point without `noauto`.)

Check mode: only the parted stage fails on missing non-removable devices; later stages only report them,
because partitions and mappers are not created in check mode.

crypttab and fstab changes trigger a `systemctl daemon-reload`, so the generated
`systemd-cryptsetup@<name>.service` and `<path>.mount` units are available right away.

## Backup disk example

```yaml
disk:
  luks:
    devices:
      - device: /dev/disk/by-id/usb-EXAMPLE_DISK
        name: backup_a             # no '-': it would be escaped in systemd-cryptsetup@<name>.service
        cryptpw: "{{ vault_backup_passphrase }}"
        crypttab_opts: "luks,discard,noauto,nofail"
        close: true
        removable: true            # inherited by the btrfs filesystem below
  btrfs:
    filesystems:
      - device: /dev/mapper/backup_a
        label: backup-a
        subvolumes:
          - name: "/{{ inventory_hostname_short }}"
        mounts:
          - path: /mnt/backup-a
            subvol: "/"
            state: present
            opts: "noauto,nofail,x-systemd.requires=systemd-cryptsetup@backup_a.service,compress=zstd"
```

`systemctl start /mnt/backup-a` asks for the passphrase, opens and mounts;
`systemctl stop systemd-cryptsetup@backup_a.service` unmounts and closes.

## Tests

`tests/run-container.sh` (safety checks on image files, mountpoint checks, migration copy/verify, SELinux
rules on the policy store, ~1 min) and `tests/run-vm.sh` (the whole role in a
throwaway Leap 16.1 VM: creation, idempotency and data-preservation scenarios, ~15 min); see
[tests/README.md](tests/README.md).

Manual checks on a real host after a rollout, a migration, a reboot or a reinstall:
[MANUAL-CHECKS.md](MANUAL-CHECKS.md).

## License

Apache-2.0

Created with the help of AI
