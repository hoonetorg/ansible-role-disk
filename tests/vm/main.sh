#!/bin/bash
# runs inside the test container: test VM up, scenarios, negative control, secrets check, VM down
set -uo pipefail
T=/roles/ansible-role-disk/tests/vm
W=/work
IMG_URL=${IMG_URL:-https://download.opensuse.org/distribution/leap/16.1/appliances/Leap-16.1-Minimal-VM.x86_64-Cloud.qcow2}
BASE=/cache/$(basename "$IMG_URL")
ACCEL=${QEMU_ACCEL:-kvm}
export ANSIBLE_CONFIG=$T/ansible.cfg
export TEST_PASSPHRASE=leakcheck-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
SSH=(ssh -i $W/id -p 2222 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR
     -o ConnectTimeout=5 root@127.0.0.1)

log()   { echo "[$(date +%T)] $*"; }
vmsh()  { "${SSH[@]}" "$@"; }
# runs lib.sh + <script> as root in the VM
vmscript() { cat "$T/lib.sh" "$1" | vmsh bash -s; }

# screen of the VM (PPM) for debugging boot problems
screenshot() {
  python3 - "$W/monitor" "$W/logs/screen.ppm" <<'PY' 2>/dev/null
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.5); s.recv(65536)
s.send(("screendump %s\n" % sys.argv[2]).encode()); time.sleep(2)
PY
}

stop_vm() {
  [ -f $W/qemu.pid ] || return 0
  local pid; pid=$(cat $W/qemu.pid)
  vmsh poweroff >/dev/null 2>&1; sleep 3
  kill "$pid" 2>/dev/null; rm -f $W/qemu.pid $W/monitor $W/os.qcow2 $W/tdisk*.img $W/seed.iso
}
trap stop_vm EXIT

# --- base image (cached, sha256 checked against the mirror)
fetch_image() {
  local want have
  want=$(curl -fsSL "$IMG_URL.sha256" | cut -d' ' -f1) || want=""
  if [ -f "$BASE" ]; then
    [ -z "$want" ] && { log "checksum not reachable, using cached $BASE"; return 0; }
    have=$(sha256sum "$BASE" | cut -d' ' -f1)
    [ "$have" = "$want" ] && return 0
    log "cached image outdated"
  fi
  [ -n "$want" ] || { log "image checksum not reachable"; return 1; }
  log "downloading $IMG_URL"
  curl -fsSL -o "$BASE.part" "$IMG_URL" || return 1
  [ "$(sha256sum "$BASE.part" | cut -d' ' -f1)" = "$want" ] || { log "checksum mismatch"; rm -f "$BASE.part"; return 1; }
  mv "$BASE.part" "$BASE"
}

start_vm() {
  rm -rf $W/logs $W/id* $W/inventory; mkdir -p $W/logs $W/seed
  ssh-keygen -q -t ed25519 -N '' -f $W/id
  sed "s|@SSH_KEY@|$(cat $W/id.pub)|g" $T/user-data.tmpl > $W/seed/user-data
  printf 'instance-id: disktest-%s\nlocal-hostname: disktest\n' "$(date +%s)" > $W/seed/meta-data
  xorriso -as mkisofs -quiet -o $W/seed.iso -V cidata -J -r $W/seed/user-data $W/seed/meta-data 2>/dev/null || return 1
  qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" $W/os.qcow2 20G || return 1
  local disks=() i
  for i in 1 2 3; do
    rm -f $W/tdisk$i.img; truncate -s "${DISK_SIZE:-1G}" $W/tdisk$i.img
    # werror/rerror=report: I/O errors (e.g. host disk full) reach the guest instead of pausing the VM
    disks+=(-drive "file=$W/tdisk$i.img,if=none,id=t$i,format=raw,discard=unmap,detect-zeroes=unmap,werror=report,rerror=report"
            -device "virtio-blk-pci,drive=t$i,serial=tdisk$i")
  done
  local cpu=host; [ "$ACCEL" = tcg ] && cpu=max
  qemu-system-x86_64 -name disktest -machine "q35,accel=$ACCEL" -cpu $cpu -smp 2 -m "${VM_MEM:-1536}" \
    -display none -daemonize -pidfile $W/qemu.pid -serial file:$W/logs/console.log \
    -monitor unix:$W/monitor,server,nowait \
    -drive "file=$W/os.qcow2,if=none,id=os,format=qcow2" -device virtio-blk-pci,drive=os,bootindex=0 \
    -drive "file=$W/seed.iso,if=none,id=seed,format=raw,readonly=on" -device virtio-blk-pci,drive=seed \
    "${disks[@]}" \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n0 || return 1
  echo "testvm ansible_host=127.0.0.1 ansible_port=2222 ansible_user=root ansible_ssh_private_key_file=$W/id" > $W/inventory
  local timeout=${BOOT_TIMEOUT:-600}; [ "$ACCEL" = tcg ] && timeout=2400
  log "waiting for ssh (accel=$ACCEL)"
  local t0=$SECONDS
  until vmsh true 2>/dev/null; do
    (( SECONDS - t0 > timeout )) && { screenshot; log "VM did not come up, see logs/console.log + logs/screen.ppm"; return 1; }
    sleep 5
  done
  log "VM up after $((SECONDS - t0))s, installing disk tools"
  ansible-playbook $T/bootstrap.yml > $W/logs/bootstrap.log 2>&1 || { log "bootstrap failed, see logs/bootstrap.log"; return 1; }
}

# --- one scenario: reset, prepare, checksums, role run, expectations
# sets PROBLEMS (empty = OK) and SUMMARY_LINE; roles_path can be overridden for the negative control
run_scenario() {
  local dir=$1 name; name=$(basename "$dir")
  local RESULT=ok MSG="" CHANGED="" PRESERVE="" CHECK_MODE="" KEEP="" VARS=""
  source "$dir/expect"
  local vars=$dir/vars.yml; [ -n "$VARS" ] && vars=$T/scenarios/$VARS/vars.yml
  local out=$W/logs/$name.log
  PROBLEMS=()
  : > "$out"
  if [ -z "$KEEP" ]; then vmscript $T/reset.sh >> "$out" 2>&1 || PROBLEMS+=("reset failed"); fi
  if [ -f "$dir/prepare.sh" ]; then vmscript "$dir/prepare.sh" >> "$out" 2>&1 || PROBLEMS+=("prepare failed"); fi
  declare -A before=()
  local d
  for d in $PRESERVE; do before[$d]=$(vmsh sha256sum /dev/disk/by-id/virtio-$d | cut -d' ' -f1); done
  local rc
  echo "### ansible-playbook apply.yml -e @$vars ${CHECK_MODE:+-C}" >> "$out"
  ansible-playbook $T/apply.yml -e "@$vars" --diff -v ${CHECK_MODE:+-C} >> "$out" 2>&1; rc=$?
  local changed; changed=$(grep -E '^testvm +:' "$out" | tail -1 | sed -nE 's/.*changed=([0-9]+).*/\1/p')
  case $RESULT in
    ok)   [ $rc -eq 0 ] || PROBLEMS+=("role failed (rc=$rc), expected success") ;;
    fail) [ $rc -ne 0 ] || PROBLEMS+=("role succeeded, expected failure") ;;
  esac
  if [ -n "$MSG" ] && ! grep -qE -- "$MSG" "$out"; then PROBLEMS+=("message /$MSG/ not found"); fi
  if [ -n "$CHANGED" ] && [ "$changed" != "$CHANGED" ]; then PROBLEMS+=("changed=$changed, expected $CHANGED"); fi
  for d in $PRESERVE; do
    [ "$(vmsh sha256sum /dev/disk/by-id/virtio-$d | cut -d' ' -f1)" = "${before[$d]}" ] || PROBLEMS+=("$d was modified")
  done
  if [ -f "$dir/verify.sh" ]; then
    echo "### verify.sh" >> "$out"
    vmscript "$dir/verify.sh" >> "$out" 2>&1 || PROBLEMS+=("verify.sh failed")
  fi
  SUMMARY_LINE=$(printf '%-30s %-4s changed=%-3s%s' "$name" "$RESULT" "${changed:-?}" \
                 "${PRESERVE:+ unchanged: $PRESERVE}")
}

# scenario selection: prefixes from the command line, plus the scenarios a KEEP scenario builds on
select_scenarios() {
  local all=() d sel=() i j
  for d in $T/scenarios/*/; do all+=("${d%/}"); done
  if [ $# -eq 0 ]; then SELECTED=("${all[@]}"); return; fi
  for i in "${!all[@]}"; do
    for p in "$@"; do
      if [[ $(basename "${all[$i]}") == "$p"* ]]; then
        j=$i
        while (( j > 0 )) && grep -q '^KEEP=1' "${all[$j]}/expect"; do j=$((j - 1)); done
        for ((; j <= i; j++)); do sel[$j]=${all[$j]}; done
      fi
    done
  done
  SELECTED=("${sel[@]}")
}

# ---------------------------------------------------------------------------------------------------------
select_scenarios "$@"
fetch_image || { log "no base image"; exit 1; }
start_vm || exit 1
results=()
failed=0
for dir in "${SELECTED[@]}"; do
  run_scenario "$dir"
  if [ ${#PROBLEMS[@]} -eq 0 ]; then line="OK   $SUMMARY_LINE"
  else line="BAD  $SUMMARY_LINE | $(IFS='; '; echo "${PROBLEMS[*]}")"; failed=$((failed + 1)); fi
  echo "$line"; results+=("$line")
done

# debugging: keep the VM running (ssh: podman exec -it <container> ssh -i /work/id -p 2222 root@127.0.0.1)
if [ -n "${HOLD_VM:-}" ]; then log "HOLD_VM set: VM keeps running until the container is stopped"; sleep infinity; fi

# negative control: the same data-preservation scenario against a role without check_data.yml must
# destroy data - proves that the PRESERVE check really detects writes
neg=$T/scenarios/31-luks-on-ext4-partition
if [ $# -eq 0 ] && [ -d "$neg" ]; then
  rm -rf $W/roles-nocheck; mkdir -p $W/roles-nocheck
  cp -r /roles/ansible-role-disk $W/roles-nocheck/; printf -- '---\n[]\n' > $W/roles-nocheck/ansible-role-disk/tasks/check_data.yml
  ANSIBLE_ROLES_PATH=$W/roles-nocheck run_scenario "$neg"
  if printf '%s\n' "${PROBLEMS[@]}" | grep -q 'tdisk1 was modified'; then
    line="OK   negative control: role without check_data.yml overwrote tdisk1, the check detects it"
  else
    line="BAD  negative control: no modification detected ($(IFS='; '; echo "${PROBLEMS[*]}"))"; failed=$((failed + 1))
  fi
  echo "$line"; results+=("$line"); rm -rf $W/roles-nocheck
fi

# secrets: the role's passphrase must not appear in any output or log
hits=$(grep -rlF -- "$TEST_PASSPHRASE" $W/logs 2>/dev/null | wc -l)
if [ "$hits" -eq 0 ]; then line="OK   secrets: test passphrase in 0 log files (screen output, ansible.log, log_plays)"
else line="BAD  secrets: test passphrase found in $hits log file(s): $(grep -rlF -- "$TEST_PASSPHRASE" $W/logs | xargs -n1 basename | tr '\n' ' ')"; failed=$((failed + 1)); fi
echo "$line"; results+=("$line")

total=${#results[@]}
{ printf '%s\n' "${results[@]}"; echo "summary: $((total - failed))/$total OK"; } > $W/summary.txt
echo "summary: $((total - failed))/$total OK"
[ -n "${KEEP_LOGS:-}" ] || [ $failed -gt 0 ] || rm -rf $W/logs
[ $failed -eq 0 ]
