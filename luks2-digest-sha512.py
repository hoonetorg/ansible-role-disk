#!/usr/bin/python3
"""Switch the volume key digest of a LUKS2 device to sha512 without touching the data.

How: the LUKS2 header is recreated with the SAME volume key (luksFormat --volume-key-file) and the same UUID,
cipher, key size, sector size, data offset and metadata sizes, with --hash sha512. The data area is not
written; the volume key is compared before/after. Does nothing if all digests are already sha512.

The new header has ONE keyslot (the passphrase you enter) with the PBKDF type of the old keyslot (e.g. argon2id)
and cryptsetup's default unlock time, unless --pbkdf / --iter-time are given; add/convert keyslots afterwards
(luksAddKey, luksConvertKey).

Refuses (nothing changed): device open/in use, more than one keyslot (unless --single-keyslot), tokens
(TPM2/FIDO2), several or integrity segments, unfinished reencryption, detached headers. Always writes a header
backup first; on any mismatch after the change the old header is restored automatically.

stdlib only; needs cryptsetup >= 2.4 (luksDump --dump-json-metadata). Run as root, device closed:
  luks2-digest-sha512.py /dev/disk/by-id/<disk> [--dry-run] [--backup FILE] [--pbkdf argon2id --iter-time 5000]
"""

import argparse
import datetime
import getpass
import hmac
import json
import os
import re
import subprocess
import sys
import tempfile

SHM = "/dev/shm"


def die(msg):
    sys.exit("ERROR: " + msg + " - nothing changed")


def run(args, stdin=None, check=True):
    p = subprocess.run(args, input=stdin, capture_output=True)
    if check and p.returncode != 0:
        raise RuntimeError("%s failed (rc %d): %s" % (" ".join(args[:2]), p.returncode,
                                                     p.stderr.decode(errors="replace").strip()))
    return p


def header(dev):
    meta = json.loads(run(["cryptsetup", "luksDump", "--dump-json-metadata", dev]).stdout)
    text = run(["cryptsetup", "luksDump", dev]).stdout.decode()
    field = lambda name: (re.search(r"^%s:\s*(.*)$" % name, text, re.M) or [None, ""])[1].strip()
    meta["_uuid"] = field("UUID")
    meta["_label"] = "" if field("Label") == "(no label)" else field("Label")
    meta["_subsystem"] = "" if field("Subsystem") == "(no subsystem)" else field("Subsystem")
    return meta


def in_use(dev):
    real = os.path.realpath(dev)
    holders = "/sys/class/block/%s/holders" % os.path.basename(real)
    return os.path.isdir(holders) and bool(os.listdir(holders))


def dump_volume_key(dev, passphrase, path):
    run(["cryptsetup", "luksDump", "-q", "--dump-volume-key", "--volume-key-file", path, "--key-file", "-", dev],
        stdin=passphrase)
    with open(path, "rb") as f:
        return f.read()


def shred(path):
    if os.path.exists(path):
        with open(path, "r+b") as f:
            f.write(os.urandom(os.path.getsize(path)))
            f.flush()
            os.fsync(f.fileno())
        os.unlink(path)


def layout(meta):
    seg = meta["segments"]["0"]
    return {"uuid": meta["_uuid"], "cipher": seg["encryption"], "sector_size": seg["sector_size"],
            "offset": int(seg["offset"]), "json_size": int(meta["config"]["json_size"]),
            "keyslots_size": int(meta["config"]["keyslots_size"])}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("device")
    ap.add_argument("--dry-run", action="store_true", help="only check and show what would be done")
    ap.add_argument("--backup", help="header backup file (default: /root/<device>-luks-header-<time>.img)")
    ap.add_argument("--key-file", help="read the passphrase from this file instead of asking (tests)")
    ap.add_argument("--single-keyslot", action="store_true",
                    help="allow a device with several keyslots (only the entered passphrase is kept)")
    ap.add_argument("--pbkdf", help="PBKDF of the new keyslot (default: the PBKDF type of the old keyslot)")
    ap.add_argument("--iter-time", help="unlock time of the new keyslot in ms (default: cryptsetup's default)")
    a = ap.parse_args()

    if os.geteuid() != 0:
        die("run as root")
    dev = a.device
    if run(["cryptsetup", "isLuks", "--type", "luks2", dev], check=False).returncode != 0:
        die("%s is not a LUKS2 device" % dev)

    meta = header(dev)
    hashes = sorted({d["hash"] for d in meta["digests"].values()})
    print("digest hash(es): %s" % ", ".join(hashes))
    if hashes == ["sha512"]:
        print("already sha512 - nothing to do")
        return 0

    # refuse everything this simple header rewrite cannot preserve
    if in_use(dev):
        die("%s is open/in use (close it first: umount, cryptsetup close)" % dev)
    if len(meta["segments"]) != 1 or meta["segments"]["0"]["type"] != "crypt":
        die("unexpected data segments (unfinished reencryption?): %s" % list(meta["segments"]))
    if "integrity" in meta["segments"]["0"]:
        die("integrity segments are not supported")
    if meta["config"].get("requirements"):
        die("header has requirements (e.g. reencryption in progress): %s" % meta["config"]["requirements"])
    if meta.get("tokens"):
        die("tokens present (TPM2/FIDO2/...): they would be lost")
    if len(meta["keyslots"]) > 1 and not a.single_keyslot:
        die("%d keyslots: the new header gets only one (the passphrase you enter); "
            "use --single-keyslot to accept that" % len(meta["keyslots"]))
    if len(meta["digests"]) != 1:
        die("unexpected number of digests: %d" % len(meta["digests"]))
    key_size = {ks["key_size"] for ks in meta["keyslots"].values()}
    if len(key_size) != 1:
        die("keyslots with different key sizes: %s" % key_size)
    key_bits = key_size.pop() * 8
    old = layout(meta)
    flags = meta["config"].get("flags", [])
    if old["offset"] % 512:
        die("data offset %d is not a multiple of 512" % old["offset"])

    fmt = ["cryptsetup", "luksFormat", "--type", "luks2", "--batch-mode",
           "--uuid", old["uuid"], "--cipher", old["cipher"], "--key-size", str(key_bits),
           "--sector-size", str(old["sector_size"]), "--offset", str(old["offset"] // 512),
           "--luks2-metadata-size", str(old["json_size"] + 4096),
           "--luks2-keyslots-size", str(old["keyslots_size"]), "--hash", "sha512"]
    if meta["_label"]:
        fmt += ["--label", meta["_label"]]
    if meta["_subsystem"]:
        fmt += ["--subsystem", meta["_subsystem"]]
    # without --pbkdf, cryptsetup would pick pbkdf2 because of --hash: keep the PBKDF type of the old keyslot
    old_pbkdf = sorted({ks["kdf"]["type"] for ks in meta["keyslots"].values()})[0]
    fmt += ["--pbkdf", a.pbkdf or old_pbkdf]
    if a.iter_time:
        fmt += ["--iter-time", a.iter_time]

    print("layout kept: %s" % old)
    if flags:
        print("NOTE: persistent flags %s are not kept; set them again after the change "
              "(cryptsetup open ... then cryptsetup refresh --persistent --allow-discards ...)" % flags)
    print("new header: %s --volume-key-file <RAM> --key-file - %s" % (" ".join(fmt), dev))
    if a.dry_run:
        print("dry run - nothing changed")
        return 0

    backup = a.backup or "/root/%s-luks-header-%s.img" % (
        os.path.basename(os.path.realpath(dev)), datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    if os.path.exists(backup):
        die("backup file %s exists" % backup)
    if a.key_file:
        with open(a.key_file, "rb") as f:
            passphrase = f.read()
    else:
        passphrase = getpass.getpass("passphrase of %s: " % dev).encode()

    # private directory in RAM (0700); cryptsetup refuses to write the key into an existing file
    vk_dir = tempfile.mkdtemp(dir=SHM, prefix="luks2-digest-")
    vk_before = os.path.join(vk_dir, "before")
    vk_after = os.path.join(vk_dir, "after")
    try:
        key_before = dump_volume_key(dev, passphrase, vk_before)   # also proves the passphrase
        run(["cryptsetup", "luksHeaderBackup", dev, "--header-backup-file", backup])
        print("header backup: %s (contains the keyslots: keep it on encrypted storage only)" % backup)

        try:
            run(fmt + ["--volume-key-file", vk_before, "--key-file", "-", dev], stdin=passphrase)
        except RuntimeError as e:
            run(["cryptsetup", "luksHeaderRestore", "-q", dev, "--header-backup-file", backup])
            sys.exit("ERROR: %s - old header restored from %s" % (e, backup))

        problems = []
        new = header(dev)
        if layout(new) != old:
            problems.append("layout differs: %s" % layout(new))
        if sorted({d["hash"] for d in new["digests"].values()}) != ["sha512"]:
            problems.append("digest is not sha512")
        if not hmac.compare_digest(dump_volume_key(dev, passphrase, vk_after), key_before):
            problems.append("volume key differs")
        if problems:
            run(["cryptsetup", "luksHeaderRestore", "-q", dev, "--header-backup-file", backup])
            sys.exit("ERROR: %s - old header restored from %s" % ("; ".join(problems), backup))
        print("OK: digest sha512, same volume key, UUID and data layout; data untouched")
        print("keyslot: %s" % ", ".join("%s %s" % (k, ks["kdf"]["type"]) for k, ks in new["keyslots"].items()))
    finally:
        shred(vk_before)
        shred(vk_after)
        os.rmdir(vk_dir)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as e:
        sys.exit("ERROR: %s" % e)
