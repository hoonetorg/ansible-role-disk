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
| `disk.btrfs.filesystems[].subvolumes[].owner` / `group` / `mode` | unset | ownership/permissions of the subvolume root; use numeric ids (the disk role runs before the user role) and quote the mode (`"0700"`) |
| `removable` (on `parted.disks[]`, `luks.devices[]`, `btrfs.filesystems[]`) | inherited, else `false` | device may be missing, see below |

## Subvolumes

Subvolumes are created sorted by name, so parents are created before nested children
(`/home` before `/home/projects`, independent of the inventory order) and removed after them.
Names must start with `/`. A missing parent is not created automatically (no `recursive`).

`owner`/`group`/`mode` are applied through a temporary mount of the top level (subvolid=5) under
`/run/ansible-disk/<label>` without fstab changes; skipped in check mode.

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
          - name: "/{{ inventory_hostname }}"
        mounts:
          - path: /mnt/backup-a
            subvol: "/"
            state: present
            opts: "noauto,nofail,x-systemd.requires=systemd-cryptsetup@backup_a.service,compress=zstd"
```

`systemctl start /mnt/backup-a` asks for the passphrase, opens and mounts;
`systemctl stop systemd-cryptsetup@backup_a.service` unmounts and closes.

## License

Apache-2.0

Created with the help of AI
