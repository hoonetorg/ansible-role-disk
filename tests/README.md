# Tests for ansible-role-disk

Two levels, both driven by plain bash; the exit code is the result (0 = all OK), so they also run in CI.

| | `run-container.sh` | `run-vm.sh` |
|---|---|---|
| what | safety checks (`parted_check.yml`, `check_data.yml`) and parted create/resize on image files | the whole role in a throwaway openSUSE Leap 16.1 VM: partitions, LUKS, btrfs, subvolumes, mounts |
| needs | podman (or docker) | podman (or docker), `/dev/kvm` (without: software emulation, much slower), network for the first image download |
| time | ~1 min | ~15 min |

```bash
tests/run-container.sh                  # level 1
tests/run-vm.sh                         # level 2, all scenarios
tests/run-vm.sh 30 31                   # scenarios starting with 30 / 31 (plus the ones they build on)
KEEP_LOGS=1 tests/run-vm.sh             # keep the logs also when everything is OK
HOLD_VM=1 tests/run-vm.sh 10            # keep the VM running afterwards for debugging:
                                        #   podman exec -it <container> ssh -i /work/id -p 2222 root@127.0.0.1
CONTAINER_ENGINE=docker QEMU_ACCEL=tcg tests/run-vm.sh
tests/build-image.sh                    # rebuild the test image after changing tests/Containerfile
```

## Where things live

- test image `localhost/ansible-role-disk-tests` (`Containerfile`: Debian with the same ansible as the
  nsbldr container, disk tools, qemu), built on first use
- base VM image (Leap 16.1 Minimal-VM Cloud, ~340 MB, sha256 checked): `~/.cache/ansible-role-disk-tests/`
  (`CACHE_DIR`)
- work dir `/var/tmp/ansible-role-disk-tests/` (`WORK_DIR`, not `/tmp`: that is RAM on many systems):
  - `container/summary.txt`, `container/checks.log`
  - `vm/summary.txt`, `vm/logs/` (one log per scenario, `ansible.log`, `hosts/`, `console.log`;
    deleted when everything is OK unless `KEEP_LOGS=1`)
  - while running: VM overlay (`os.qcow2`) and three sparse 1 GiB test disks (deleted at the end)
- `run-vm.sh` stops before it starts if less than 4 GB are free in the work dir (`MIN_FREE_GB`)

## VM tests

`run-vm.sh` starts the test container; inside it, `vm/main.sh` boots the VM with qemu (cloud-init seed: SSH
key for root, port 2222) and three extra disks with serials, i.e. `/dev/disk/by-id/virtio-tdisk1..3` - the
same by-id naming the role uses in production. Every scenario runs as its own `ansible-playbook` process
(`vm/apply.yml` with the scenario's `vars.yml`, `--diff -v`):

1. `vm/reset.sh` (skipped with `KEEP=1`): unmount `/t/*`, close `t_*` mappers, drop their crypttab/fstab
   lines, discard the test disks (and check that they read back as zeros)
2. `prepare.sh` (optional): foreign data, partitions, canary files
3. sha256 of the disks in `PRESERVE`
4. the role run, then the checks from `expect`, the `PRESERVE` checksums (must be unchanged) and
   `verify.sh` (optional, any failing command fails the scenario)

`expect` (shell variables):

| variable | meaning |
|---|---|
| `RESULT=ok\|fail` | the role run must succeed / fail |
| `MSG='<regex>'` | must appear in the output |
| `CHANGED=<n>` | changed count of the play recap (idempotency: `0`) |
| `PRESERVE="tdisk1 ..."` | these disks must be bit-identical after the run |
| `CHECK_MODE=1` | run with `-C` |
| `KEEP=1` | no reset, builds on the previous scenario |
| `VARS=<scenario>` | use the `vars.yml` of another scenario |
| `REBOOT=1` | reboot the VM after the role run, `verify.sh` runs after the reboot (e.g. autorelabel) |

Helpers for the scripts are in `vm/lib.sh` (`$D1..$D3`, `gpt`, `luks`, `mixed`, `canary_put/check`, `not`
(negated check: `! cmd` would not stop a script under `set -e`),
`sha_head`). Test names: mappers `t_*`, mount points `/t/...`, labels `t-*`.

After the scenarios:
- **negative control**: scenario 31 once more against a copy of the role without `check_data.yml` - the run
  must overwrite the disk and the `PRESERVE` check must notice (proves the tests cannot pass vacuously)
- **secrets**: the role's passphrase (random per run) must not appear in any output or log (screen output,
  `log_path`, `log_plays`, as configured in `vm/ansible.cfg` like in production)

Scenarios: `10`-`19` create/keep (fresh disk, rerun, check mode, subvolume removal, grow/add partitions,
whole-disk LUKS, backup disk, missing removable disk), `30`-`45` data preservation (each must stop with
the disks unchanged), `50`-`54` SELinux (labels through the mountpoint, `<<none>>` for the top-level view,
the relabel problem demonstrated without the rule, boot autorelabel with `/etc/selinux/.autorelabel` and with
`/.autorelabel`; need SELinux in the test VM), `60`-`66` mounts (migration of a
populated mountpoint with an already mounted child, rerun, stop on: data without `migrate`, leftover
`.pre-ansible`, process using the path or a file in its mounted child, non-empty subvolume).

## CI (not set up yet)

Both scripts run unchanged in CI with `CONTAINER_ENGINE=docker`. GitHub's standard Linux runners provide
KVM for public repositories after a udev rule:

```yaml
- run: |
    echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
    sudo udevadm control --reload-rules && sudo udevadm trigger --name-match=kvm
- uses: actions/cache@v4
  with: { path: ~/.cache/ansible-role-disk-tests, key: leap-16.1-cloud }
- run: CONTAINER_ENGINE=docker tests/run-container.sh
- run: CONTAINER_ENGINE=docker tests/run-vm.sh
```
