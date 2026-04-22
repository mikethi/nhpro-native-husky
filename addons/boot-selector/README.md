# boot-selector — optional boot target addon
### Google Pixel 8 Pro (husky / zuma SoC)

An **optional, self-contained addon** for [nhpro-native-husky](../../README.md).
It wraps any existing `boot.img` with a tiny prepend-initrd that lets you choose
which OS to boot on every power-on — without touching the `bootloader` partition
or anything Google's ABL verifies.

---

## Why this works (and why custom bootloaders don't)

```
[Titan M2] ──── verifies ────► [bootloader partition]   ← hardware-locked; cannot be replaced
                                        │
                                        ▼
                               [Google ABL / fastboot]   ← pass-through only after unlock
                                        │
                             verifies your signed boot.img
                                        │
                                        ▼
                    ┌─────────── [boot partition] ───────────┐
                    │   kernel (Sultan / zuma)               │  ← you own this
                    │   initrd (boot-selector prepend)       │  ← this addon
                    └────────────────────────────────────────┘
                                        │
                              boot-selector /init runs
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
              linux (default)       android            recovery
           extract real initrd    kexec → Android    kexec → recovery
           exec its /init         kernel on userdata  kernel on userdata
           (NetHunter Pro)
```

Titan M2 verifies the `bootloader` partition using factory-fused keys that
cannot be changed.  The `boot` partition is entirely yours after
`fastboot flashing unlock`.  The selector sits in the `boot` partition's
initrd — Google ABL never sees it.

---

## Boot target priority

On every boot the selector checks these sources in order, using the first
non-empty result:

| Priority | Source | Example |
|---|---|---|
| 1 | Kernel cmdline | `fastboot boot -c 'boot_target=android' boot.img` |
| 2 | `/userdata/.boot_target` | persistent; survives reboot |
| 3 | Built-in default | `linux` |

---

## Built-in targets

| Target | What it does |
|---|---|
| `linux` | Extracts the original NetHunter Pro initrd on top of the current tmpfs, then execs its `/init`.  No kexec needed.  This is the default. |
| `android` | Loads `/userdata/.android/kernel` (and optionally `initrd`, `cmdline`) via `kexec`. |
| `recovery` | Loads `/userdata/.recovery/kernel` (and optionally `initrd`, `cmdline`) via `kexec`. |

---

## Adding a new boot target

Drop a shell script in `boot-targets/` that defines a `run_target()` function,
then rebuild with `scripts/build.sh`.  That's it — no other changes needed.

```sh
# boot-targets/myos.sh
run_target() {
    echo "boot-selector[myos]: booting my custom OS" >/dev/console
    # ... mount, kexec, switch_root, whatever you need ...
}
```

Rebuild:
```bash
./scripts/build.sh -i nethunterpro-YYYYMMDD-husky-phosh-boot.img \
                   -b /path/to/busybox-arm64 \
                   -k /path/to/kexec-arm64
```

Select it:
```bash
./scripts/set-target.sh set myos
```

---

## Prerequisites

### Host tools

| Tool | Package |
|---|---|
| `unpack_bootimg` | `android-tools-mkbootimg` |
| `mkbootimg` | `android-tools-mkbootimg` |
| `cpio`, `gzip` | `coreutils` |

```bash
sudo apt install android-tools-mkbootimg cpio gzip
```

### Binaries to embed (arm64 static)

The selector initrd is a minimal rootfs — it needs its own static binaries
because it runs before any rootfs is mounted.

| Binary | Purpose | Where to get |
|---|---|---|
| `busybox` (arm64 static) | sh, mount, blkid, cpio, gzip, … | [busybox.net](https://busybox.net/downloads/binaries/) or build from source |
| `kexec` (arm64 static) | android / recovery targets | [kexec-tools](https://kernel.org/pub/linux/utils/kernel/kexec/) built with `--host=aarch64-linux-gnu` |

> **linux target only?**  If you only need the default `linux` target you can
> skip `kexec`.  Pass only `--busybox`.

---

## Workflow

### 1 — Build the normal nhpro image first

```bash
cd nethunter-pro
./build.sh -d          # or ./kali-build.sh
```

This produces `nethunterpro-YYYYMMDD-husky-phosh-boot.img` in `.upstream/`.

### 2 — Wrap with the boot selector

```bash
cd ../addons/boot-selector

./scripts/build.sh \
    --boot-img ../../nethunter-pro/.upstream/nethunterpro-YYYYMMDD-husky-phosh-boot.img \
    --busybox  /path/to/busybox-armv8l-static \
    --kexec    /path/to/kexec-arm64-static
```

Output: `nethunterpro-YYYYMMDD-husky-phosh-boot-selector.img`

Preview without writing output:
```bash
./scripts/build.sh --boot-img <path> --dry-run
```

### 3 — Flash

```bash
fastboot flash boot nethunterpro-YYYYMMDD-husky-phosh-boot-selector.img
fastboot reboot
```

The device boots NetHunter Pro by default — identical to the non-selector image.

### 4 — Set a persistent boot target

```bash
# Requires ADB (auto-detected) or --direct when running on the device

./scripts/set-target.sh set android     # next boot → android
./scripts/set-target.sh set linux       # next boot → NetHunter Pro
./scripts/set-target.sh get             # read current target
./scripts/set-target.sh clear           # remove flag (reverts to linux)
```

### 5 — One-shot target via fastboot (no persistent flag)

```bash
fastboot boot -c 'boot_target=android' nethunterpro-YYYYMMDD-husky-phosh-boot-selector.img
```

Boots android once.  The flag file on userdata is unchanged.

---

## Storing Android / recovery kernels on userdata

The `android` and `recovery` targets read kernel files from hidden directories
on the userdata partition.  Use `set-target.sh store-android` / `store-recovery`
to place them there:

```bash
# Store Android kernel (extract from a factory image or a boot.img dump)
./scripts/set-target.sh store-android \
    --kernel  /path/to/android-kernel \
    --initrd  /path/to/android-vendor-ramdisk.img \
    --cmdline /path/to/android-cmdline.txt

# Then activate the target
./scripts/set-target.sh set android
```

Expected file layout on userdata:
```
/userdata/.android/
    kernel      ← required  (Image.gz-dtb or Image.gz with appended DTB)
    initrd      ← optional  (vendor_ramdisk / combined ramdisk)
    cmdline     ← optional  (one line; falls back to husky default if absent)

/userdata/.recovery/
    kernel      ← required
    initrd      ← optional
    cmdline     ← optional
```

Default cmdline (used when `cmdline` file is absent):
```
earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8 \
clk_ignore_unused swiotlb=noforce androidboot.hardware=zuma
```
Recovery appends: `androidboot.mode=recovery`

---

## How the selector initrd is structured

```
/init                     ← selector PID-1 script (this addon)
/boot-targets/
    linux.sh              ← extract real-initrd.cpio.gz, exec its /init
    android.sh            ← kexec /tmp/android-kernel
    recovery.sh           ← kexec /tmp/recovery-kernel
    <custom>.sh           ← your additions
/real-initrd.cpio.gz      ← original NetHunter Pro initrd (embedded by build.sh)
/bin/busybox              ← static arm64 busybox (all shell utilities)
/bin/sh → busybox
/bin/mount → busybox
/bin/umount → busybox
/bin/blkid → busybox
/bin/cpio → busybox
/bin/gzip → busybox
/sbin/kexec               ← static arm64 kexec (for android/recovery targets)
/proc/ /sys/ /dev/ /tmp/ /run/
```

The selector is a **prepend-initrd**: it is the sole `/init`.  For the `linux`
target it extracts `real-initrd.cpio.gz` on top of the current tmpfs (which
overwrites `/init` with the real one) then `exec`s it.  This is a standard
Linux initramfs chaining technique — no kexec required for the default path.

---

## Reverting to the standard boot.img

Flash the original image at any time to remove the selector entirely:

```bash
fastboot flash boot nethunterpro-YYYYMMDD-husky-phosh-boot.img
fastboot reboot
```
