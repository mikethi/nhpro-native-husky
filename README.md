# nhpro-native-husky

**Google Pixel 8 Pro (husky) — Kali NetHunter Pro, dual-boot Android, GSI, U-Boot, and Magisk**

> 📸 **[SCREENSHOT PLACEHOLDER: Hero banner — Pixel 8 Pro showing NetHunter Pro and Android boot menu side by side]**

---

## ⚠️ WARNING — READ THIS FIRST

> **These procedures VOID YOUR WARRANTY and carry real risk of data loss or device damage. Proceed only if you understand and accept the risks.**

| Risk | Detail |
|------|--------|
| 🔒 **WARRANTY VOID** | Unlocking the bootloader permanently voids your Google warranty |
| 🗑️ **DATA WIPE** | `fastboot flashing unlock` erases ALL data on the device |
| 🧱 **BRICK RISK** | Flashing wrong images can render the device unbootable |
| 🔄 **ARP (Anti-Rollback)** | Flashing a newer ABL permanently prevents downgrading — see §9 |
| ⚡ **dm-verity** | Android may refuse to boot if vbmeta is not flashed correctly — see §8 |

---

## Table of Contents

1. [What is this?](#1-what-is-this)
2. [Hardware overview](#2-hardware-overview)
3. [Prerequisites](#3-prerequisites)
4. [Unlock the bootloader](#4-unlock-the-bootloader)
5. [Build NetHunter Pro](#5-build-nethunter-pro)
   - [5A. Bare metal (Linux)](#5a-bare-metal-linux)
   - [5B. Docker](#5b-docker)
   - [5C. Windows / WSL2](#5c-windows--wsl2)
   - [5D. postmarketOS](#5d-postmarketos)
6. [Flash NetHunter Pro (basic)](#6-flash-nethunter-pro-basic)
7. [Boot selector — 6 targets overview](#7-boot-selector--6-targets-overview)
8. [Dual-boot setup (Android + NetHunter Pro)](#8-dual-boot-setup-android--nethunter-pro)
9. [dm-verity and Anti-Rollback Protection (ARP)](#9-dm-verity-and-anti-rollback-protection-arp)
10. [GSI — Generic System Image](#10-gsi--generic-system-image)
11. [Magisk — Android root via U-Boot function](#11-magisk--android-root-via-u-boot-function)
12. [U-Boot — non-ABL boot with 6-target menu](#12-u-boot--non-abl-boot-with-6-target-menu)
13. [Switching boot targets](#13-switching-boot-targets)
14. [Troubleshooting](#14-troubleshooting)
15. [References](#15-references)

---

## 1. What is this?

This repository provides everything needed to:

- Run **Kali NetHunter Pro** natively on the Google Pixel 8 Pro with full kernel hardware control (no Android HAL)
- Set up **dual-boot**: switch between NetHunter Pro and Android without re-flashing
- Boot any of **6 OS variants** (NetHunter Pro, Android slot A/B, GSI, Recovery A/B) from a single boot menu
- Apply **Magisk root** to Android targets directly from U-Boot — no PC required after initial setup
- Use **U-Boot as a non-ABL boot manager** that reads the A/B slot from the device itself

The key components are:

| Component | What it does |
|-----------|-------------|
| `nethunter-pro/` | Build system — produces the NetHunter Pro boot and rootfs images |
| `addons/boot-selector/` | Prepend-initrd that runs before the real OS, selects boot target |
| `scripts/` | Host tools: flash, U-Boot build, Magisk setup, factory setup |
| `nethunter-pro/devices/zuma/configs/uboot/` | U-Boot board files (defconfig, header, boot script) |

---

## 2. Hardware overview

| Item | Detail |
|------|--------|
| Device | Google Pixel 8 Pro |
| Codename | **husky** |
| SoC | Google Tensor G3 (zuma / Samsung GS301, Exynos-derived) |
| RAM | 12 GB LPDDR5 (2 banks: 8 GB @ 0x80000000, 4 GB @ 0x880000000) |
| Storage | 128 / 256 / 1024 GB UFS 3.1 @ 0x13200000 |
| Display | 6.7" LTPO OLED 1344×2992, 1–120 Hz |
| Boot | Android v4 boot image, A/B partition scheme, Titan M2 security chip |
| UART | ttySAC0 @ 0x10870000, 115200 8N1 (Exynos UART0) |

> 📸 **[SCREENSHOT PLACEHOLDER: Photo of Pixel 8 Pro front and back]**

For the full hardware component table (drivers, kernel modules, firmware paths), see **[HARDWARE_SPECS.md](HARDWARE_SPECS.md)**.

---

## 3. Prerequisites

### Tools you need on your computer

| Tool | How to get it | Used for |
|------|---------------|----------|
| `git` | `sudo apt install git` | Clone this repo |
| `fastboot` | [platform-tools](https://developer.android.com/tools/releases/platform-tools) | Flash images to the phone |
| `adb` | Same package as fastboot | Push files to device, ADB shell |
| `unzip` | `sudo apt install unzip` | Extract factory ZIPs and Magisk APK |

### For building NetHunter Pro

| Build method | Extra tools |
|--------------|-------------|
| **A: bare metal** | `debos xz-utils android-sdk-libsparse-utils mkbootimg` |
| **B: Docker** | Docker Engine, `kali-archive-keyring` |
| **C: Windows/WSL2** | PowerShell 7, WSL2, `usbipd-win` |
| **D: postmarketOS** | `pmbootstrap` |

### For U-Boot build

```bash
sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
                 libssl-dev python3-pyelftools bison flex bc cpio
```

### For Magisk patching

```bash
sudo apt install unzip cpio gzip
# Plus a Magisk APK from: https://github.com/topjohnwu/Magisk/releases
```

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal showing all prerequisite tools installed successfully]**

---

## 4. Unlock the bootloader

> ⚠️ **This erases ALL data on the device. Back up everything first.**

### Step 4.1 — Enable Developer Options

1. Open **Settings** → **About phone**
2. Tap **Build number** 7 times until you see "You are now a developer!"

> 📸 **[SCREENSHOT PLACEHOLDER: Settings → About phone → Build number highlighted]**

### Step 4.2 — Enable OEM unlocking

1. Open **Settings** → **System** → **Developer options**
2. Toggle **OEM unlocking** ON

> 📸 **[SCREENSHOT PLACEHOLDER: Developer options with "OEM unlocking" toggle turned ON]**

### Step 4.3 — Boot into fastboot mode

Hold **Power + Volume Down** for 10 seconds, or run:

```bash
adb reboot bootloader
```

> 📸 **[SCREENSHOT PLACEHOLDER: Phone screen showing "Fastboot Mode" with the Android robot and "LOCKED" text]**

### Step 4.4 — Unlock

```bash
fastboot flashing unlock
```

On the phone screen, use **Volume buttons** to select **Unlock** and press **Power** to confirm.

> 📸 **[SCREENSHOT PLACEHOLDER: Phone screen showing unlock confirmation dialog with "Unlock the bootloader?" prompt]**

> 📸 **[SCREENSHOT PLACEHOLDER: Phone screen after unlock showing "UNLOCKED" status in fastboot mode]**

The device will wipe and reboot. After setup, re-enable Developer Options (repeat step 4.1).

---

## 5. Build NetHunter Pro

Choose the build method that matches your setup. All methods produce the same output images.

### 5A. Bare metal (Linux)

**Prerequisites:** `debos xz-utils android-sdk-libsparse-utils mkbootimg fastboot`

```bash
# 1. Clone the repository
git clone https://github.com/mikethi/nhpro-native-husky.git
cd nhpro-native-husky/nethunter-pro

# 2. Install build dependencies
sudo apt update
sudo apt install -y git debos xz-utils android-sdk-libsparse-utils \
                    android-tools-mkbootimg fastboot

# 3. Build
./build.sh
```

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal showing `./build.sh` running with progress output]**

Output files appear in `nethunter-pro/.upstream/`:

```
nethunterpro-YYYYMMDD-husky-phosh-boot.img   ← kernel + boot-selector initrd
nethunterpro-YYYYMMDD-husky-phosh.img         ← NetHunter Pro rootfs
```

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal showing build output directory listing with the two .img files]**

### 5B. Docker

```bash
git clone https://github.com/mikethi/nhpro-native-husky.git
cd nhpro-native-husky/nethunter-pro

sudo apt install -y docker.io kali-archive-keyring fastboot
./build.sh -d
```

### 5C. Windows / WSL2

**Step 1 — Install WSL2 and Kali (PowerShell 7 as Administrator):**

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\setup-wsl-kali.ps1
```

> 📸 **[SCREENSHOT PLACEHOLDER: PowerShell window running setup-wsl-kali.ps1 with progress bars]**

Reboot if prompted, then re-run the script.

**Step 2 — Build in Kali WSL:**

```bash
# Open "kali-linux" from Start menu, then:
cd ~/nhpro-native-husky/nethunter-pro
./kali-build.sh
```

**Step 3 — Attach phone and flash (PowerShell as Administrator):**

Put phone in fastboot mode (Power + Volume Down), then:

```powershell
usbipd list                          # find BUSID of "Android Bootloader Interface"
usbipd bind   --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

> 📸 **[SCREENSHOT PLACEHOLDER: usbipd list output showing the Pixel 8 Pro entry]**

### 5D. postmarketOS

```bash
# Install pmbootstrap
python3 -m pip install --user pmbootstrap

# Clone pmaports and this repo's device files
git clone https://gitlab.postmarketos.org/postmarketOS/pmaports.git ~/pmaports
git clone https://github.com/mikethi/nhpro-native-husky.git
cp -r nhpro-native-husky/device/google-husky ~/pmaports/device/community/

# Bootstrap and build
pmbootstrap init    # select device: google-husky
pmbootstrap install
```

See [nethunter-pro/README.md](nethunter-pro/README.md) for full build options and flags.

---

## 6. Flash NetHunter Pro (basic)

This is the minimal flash to get NetHunter Pro running. For dual-boot, see §8.

```bash
cd nethunter-pro/.upstream

# Replace YYYYMMDD with your build date shown in the filename
VERSION="$(ls -1t nethunterpro-*-husky-phosh-boot.img | head -1 \
           | sed -E 's/nethunterpro-(.*)-husky-phosh-boot.img/\1/')"

fastboot flashing unlock         # first time only — WIPES DEVICE
fastboot flash boot     nethunterpro-${VERSION}-husky-phosh-boot.img
fastboot flash userdata nethunterpro-${VERSION}-husky-phosh.img
fastboot reboot
```

Or use the flash script (recommended — validates the config and prevents accidental ABL flash):

```bash
./scripts/flash-husky.sh --image nethunterpro-${VERSION}-husky-phosh
```

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal showing fastboot flash commands completing successfully]**

> 📸 **[SCREENSHOT PLACEHOLDER: Phone booted into Kali NetHunter Pro Phosh desktop]**

---

## 7. Boot selector — 6 targets overview

The **boot-selector** is a prepend-initrd that runs before the real OS. It reads a boot target and dispatches to the correct OS. Think of it as a bootloader running inside the kernel's initrd.

### The 6 boot targets

| # | Target name | OS | Kernel store on userdata |
|---|------------|-----|--------------------------|
| 1 | `linux` | **NetHunter Pro** (default) | embedded in boot.img initrd |
| 2 | `android-a` | Android slot\_a | `/data/.android-a/` |
| 3 | `android-b` | Android slot\_b | `/data/.android-b/` |
| 4 | `gsi` | Android GSI (system\_a replaced) | `/data/.gsi/` |
| 5 | `recovery-a` | Android Recovery slot\_a | `/data/.recovery-a/` |
| 6 | `recovery-b` | Android Recovery slot\_b | `/data/.recovery-b/` |

Plus two special targets:

| Target | What it does |
|--------|-------------|
| `menu` | Shows interactive ASCII boot menu with 10 s countdown |
| `magisk-patch` | Runs Magisk patching on a stored kernel, then reboots |

### How to switch targets

```bash
# Persistent — survives reboots until changed
./addons/boot-selector/scripts/set-target.sh set android-a
./addons/boot-selector/scripts/set-target.sh set linux
./addons/boot-selector/scripts/set-target.sh set menu

# One-shot — only affects the next boot
fastboot boot -c 'boot_target=android-a' boot-selector.img
fastboot boot -c 'boot_target=menu'      boot-selector.img
```

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal running set-target.sh set android-a with success message]**

---

## 8. Dual-boot setup (Android + NetHunter Pro)

This section sets up full dual-boot so you can switch between NetHunter Pro and Android (or GSI / Recovery) without re-flashing.

### What you need

- The NetHunter Pro boot image (from §6)
- A Google Pixel 8 Pro factory image ZIP for your current ABL version
  - Download from: <https://developers.google.com/android/images#husky>
  - ⚠️ **Match the factory ZIP to your current ABL version** — see §9 for ARP

> 📸 **[SCREENSHOT PLACEHOLDER: Google factory images download page with Pixel 8 Pro (husky) row highlighted]**

### Step 8.1 — Flash the boot-selector

The boot-selector wraps your NetHunter Pro boot.img so it can dispatch to other OSes:

```bash
cd addons/boot-selector

# Build the selector-wrapped boot image
./scripts/build.sh \
  --boot-img ../../nethunter-pro/.upstream/nethunterpro-${VERSION}-husky-phosh-boot.img \
  --kexec   /path/to/kexec-arm64-static \
  --busybox /path/to/busybox-arm64-static \
  --output  nethunterpro-${VERSION}-husky-phosh-selector.img
```

Then flash it:

```bash
fastboot flash boot nethunterpro-${VERSION}-husky-phosh-selector.img
```

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal showing boot-selector build.sh output with "Done" message]**

### Step 8.2 — Run the full Android setup script

The `setup-android.sh` script does everything needed for Android dual-boot in one command:

```bash
./addons/boot-selector/scripts/setup-android.sh \
  --factory-zip husky-ap3a.240905.015.e2-factory-*.zip
```

This automatically:
1. ✅ Extracts the factory ZIP
2. ✅ Flashes `vbmeta` with `--disable-verity --disable-verification`
3. ✅ Flashes `system`, `vendor`, `product`, `system_ext`
4. ✅ Extracts the Android kernel + vendor\_boot initrd from `boot.img`
5. ✅ Stores kernels for all 6 targets on userdata (`.android-a/`, `.android-b/`, `.recovery-a/`, `.recovery-b/`)
6. ✅ Displays ARP and rollback index information

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal running setup-android.sh with progress output for each step]**

### Step 8.3 — Verify the setup

```bash
# Check what targets are populated on the device
./addons/boot-selector/scripts/set-target.sh get

# Test Android boot (one-shot, no flag file)
fastboot boot -c 'boot_target=android-a' \
    nethunterpro-${VERSION}-husky-phosh-selector.img
```

> 📸 **[SCREENSHOT PLACEHOLDER: Phone booting into Android with orange "Your device software can't be checked for corruption" warning screen, then continuing to boot]**

> 📸 **[SCREENSHOT PLACEHOLDER: Android fully booted on Pixel 8 Pro (Settings → About phone showing Android version)]**

### Step 8.4 — Switch between OSes

```bash
# Boot NetHunter Pro next time
./addons/boot-selector/scripts/set-target.sh set linux

# Boot Android slot A next time
./addons/boot-selector/scripts/set-target.sh set android-a

# Show boot menu (interactive, 10 s countdown)
./addons/boot-selector/scripts/set-target.sh set menu
```

> 📸 **[SCREENSHOT PLACEHOLDER: Phone UART console showing the ASCII boot menu with 6 options and countdown]**

---

## 9. dm-verity and Anti-Rollback Protection (ARP)

### dm-verity explained

**dm-verity** is Android's block-level integrity verification. It checks that the system and vendor partitions haven't been modified. On an unlocked device:

- The ABL injects `androidboot.verifiedbootstate=orange` into the kernel cmdline
- Android's init sees this and **relaxes** dm-verity enforcement
- The device shows a 5-second orange warning screen on every boot
- Android then boots normally

The boot-selector **automatically inherits** these ABL-injected params from `/proc/cmdline` and forwards them to the Android kernel via kexec. This means dm-verity behaviour is identical to what it would be if the ABL had booted Android directly.

**To fully disable dm-verity** (eliminates the warning screen):

```bash
fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
```

> 📸 **[SCREENSHOT PLACEHOLDER: Orange Android warning screen showing "Your device software can't be checked for corruption" — this is NORMAL on an unlocked device]**

### Anti-Rollback Protection (ARP)

**ARP** prevents downgrading firmware to versions with known security vulnerabilities. Here's what you need to know:

| Situation | What happens |
|-----------|-------------|
| Flash factory image with **same** rollback index | Safe — ABL boots normally |
| Flash factory image with **higher** rollback index | Titan M2 programs new counter, **cannot be undone** |
| Try to boot image with **lower** rollback index | ABL refuses to boot — device shows error screen |
| Kexec-boot Android from boot-selector | ARP **not** re-evaluated — ABL already ran |

> ⚠️ **CRITICAL**: Always use factory images that match your current ABL version. Never flash an older bootloader (`bootloader-husky-ripcurrent-*.img`).

To check your current ABL version:

```bash
fastboot getvar version-bootloader
```

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal showing `fastboot getvar version-bootloader` output with version string like "ripcurrent-16.4-14540574"]**

---

## 10. GSI — Generic System Image

A **GSI (Generic System Image)** is a standardized Android system image that runs on any compatible device. It lets you run stock AOSP or custom ROMs without full firmware.

### What GSI replaces

| Partition | GSI | Stock Android |
|-----------|-----|--------------|
| `system_a` | GSI image | Factory system |
| `vendor_a` | **Unchanged** (keeps hardware drivers) | Factory vendor |
| `vendor_boot_a` | **Unchanged** | Factory vendor\_boot |
| `boot_a` | **Unchanged** (Sultan kernel) | Factory boot |

### Step 10.1 — Flash the GSI

```bash
# Download a GSI from: https://developer.android.com/topic/generic-system-image/releases
# Example: AOSP 14 arm64 A-only
fastboot flash system gsi_arm64_ab.img --disable-verity
```

> 📸 **[SCREENSHOT PLACEHOLDER: AOSP GSI releases download page]**

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal flashing GSI with fastboot flash system command]**

### Step 10.2 — Set up the GSI boot target

```bash
./addons/boot-selector/scripts/set-target.sh store-gsi \
  --kernel /path/to/android-kernel.img \
  --initrd /path/to/vendor_boot.img
./addons/boot-selector/scripts/set-target.sh set gsi
```

Or via `setup-android.sh`:

```bash
./addons/boot-selector/scripts/setup-android.sh \
  --factory-zip husky-*.zip \
  --gsi-image gsi_arm64_ab.img
```

> 📸 **[SCREENSHOT PLACEHOLDER: Phone booted into AOSP GSI (generic Android interface without Google apps)]**

---

## 11. Magisk — Android root via U-Boot function

**Magisk** is the standard Android root solution. In this setup, you can apply Magisk to any Android target **directly from the U-Boot boot menu** — no PC connection needed after initial setup.

### How the U-Boot Magisk function works

```
U-Boot boot menu
    └── "Magisk: patch android-a"
           │
           ▼
    U-Boot loads Sultan kernel
    + Magisk patch-initrd (.magisk/patch-initrd.cpio.gz)
           │
           ▼
    patch-initrd /init runs:
      1. Mount userdata
      2. magiskboot unpack .android-a/kernel
      3. Inject magiskinit + magisk64 into ramdisk
      4. magiskboot repack → write back to .android-a/kernel
      5. Save original as .android-a/kernel.orig
      6. reboot
           │
           ▼
    U-Boot shows menu again
    Select "Android slot_a" → boots with Magisk root!
```

> 📸 **[SCREENSHOT PLACEHOLDER: U-Boot serial console showing the boot menu with Magisk patch options highlighted]**

### Step 11.1 — Download Magisk APK

Download the latest release from: <https://github.com/topjohnwu/Magisk/releases>

> 📸 **[SCREENSHOT PLACEHOLDER: Magisk GitHub releases page with latest APK download highlighted]**

### Step 11.2 — Prepare the Magisk patch environment

Run this once on your PC to build the patch environment and push it to the device:

```bash
./addons/boot-selector/scripts/patch-magisk.sh \
  --apk Magisk-v27.0.apk \
  --push-adb
```

This:
1. Extracts `magiskboot` (x86\_64 for your PC), `magiskinit`, `magisk64` (arm64 for device) from the APK
2. Builds a `patch-initrd.cpio.gz` containing those binaries + the patch init script
3. Pushes it to `/data/.magisk/` on the device via ADB

```
════════════════════════════════════════════════════════
 patch-magisk.sh — Magisk patch environment builder
════════════════════════════════════════════════════════
[1/4] Extracting Magisk binaries from APK...
      extracted: magiskboot (host, x86_64)
      extracted: magiskinit (arm64)
      extracted: magisk64 (arm64)
[2/4] Building patch-initrd staging area...
[3/4] Packing patch-initrd.cpio.gz...
[4/4] Pushing to device via ADB...
      pushed to device:/data/.magisk/
════════════════════════════════════════════════════════
 Done!
```

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal showing patch-magisk.sh running with all 4 steps completing successfully]**

### Step 11.3 — Patch a target via U-Boot boot menu

1. Reboot into U-Boot (or trigger with `fastboot boot husky-boot.img`)
2. Select **"Magisk: patch android-a"** from the menu
3. Wait ~30 seconds for patching to complete
4. Device reboots back to U-Boot menu
5. Select **"Android slot\_a"** — it now has root!

> 📸 **[SCREENSHOT PLACEHOLDER: U-Boot console during Magisk patch showing "unpacking kernel... injecting Magisk... repacking... rebooting"]**

> 📸 **[SCREENSHOT PLACEHOLDER: Magisk app on Android showing "Installed" with version number after successful patch]**

### Step 11.4 — Patch via boot-selector (alternative, no UART needed)

```bash
# One-shot patch (patches android-a, then reboots to linux)
fastboot boot -c \
  'boot_target=magisk-patch patch_target=.android-a patch_reboot=1' \
  boot-selector.img
```

### Step 11.5 — Supported Magisk combinations

All combinations are supported. Mix and match as needed:

| Setup | Targets to patch |
|-------|-----------------|
| Root Android slot\_a only | Patch `.android-a` |
| Root Android slot\_b only | Patch `.android-b` |
| Root both Android slots | Patch `.android-a` AND `.android-b` |
| Root GSI | Patch `.gsi` |
| Magisk recovery (for OTA management) | Patch `.recovery-a` |
| Root everything | Patch all 5 targets |
| NetHunter Pro + Rooted Android | Patch `.android-a` (Linux target unaffected) |

### Restore unpatched kernel

```bash
# ADB shell — swap back to original
adb shell "cp /data/.android-a/kernel.orig /data/.android-a/kernel"
```

### dm-verity + Magisk interaction

Magisk patches the kernel ramdisk with its own init overlay that handles dm-verity disabling at the Android init level. For maximum reliability, use all three layers:

| Layer | How to set it | What it does |
|-------|--------------|-------------|
| vbmeta `--disable-verity` | `fastboot flash vbmeta --disable-verity vbmeta.img` | Disables dm-verity at partition level |
| `androidboot.verifiedbootstate=orange` | Inherited from ABL via boot-selector | Relaxes AVB enforcement in Android init |
| Magisk ramdisk patch | `patch-magisk.sh` or U-Boot menu | Disables forceencrypt and dm-verity at init level |

`setup-android.sh` handles the first layer automatically.

---

## 12. U-Boot — non-ABL boot with 6-target menu

U-Boot is an open-source bootloader that can replace the kernel payload in the Android `boot_a`/`boot_b` partition. In this setup, Google ABL loads U-Boot as if it were the Linux kernel, then U-Boot takes full control.

### What "non-ABL" means here

```
Normal Android boot:
  Titan M2 → ABL → selects A/B slot → loads Android kernel → Android

This project (boot-selector mode):
  Titan M2 → ABL → loads Sultan kernel → boot-selector initrd → any of 6 targets

This project (U-Boot mode):
  Titan M2 → ABL → loads U-Boot → U-Boot reads BCB → boot menu → any of 6 targets
```

In **U-Boot mode**, U-Boot reads the BCB (Bootloader Control Block) from the `misc` partition itself — independently of ABL's slot decision.

> ⚠️ **U-Boot porting status**: The zuma SoC (Tensor G3) does not have full upstream U-Boot support. The config files in this repo (`husky_defconfig`, `husky.h`, `husky-boot.cmd`) are a research/porting starting point. UART, DRAM layout, and Fastboot are documented; UFS PHY initialisation, USB, and GIC require further porting work.

### U-Boot boot menu

When running, U-Boot shows a 5-second countdown boot menu:

```
  nhpro-native-husky — Google Pixel 8 Pro (husky)
  SoC: Tensor G3 (zuma / Samsung GS301)
  Slot: _a

  1  NetHunter Pro (Linux)       ← default, auto-boots after 5 s
  2  Android  slot_a
  3  Android  slot_b
  4  Android  GSI  (system_a)
  5  Recovery slot_a
  6  Recovery slot_b
  -- Magisk: patch android-a     ← roots android-a then reboots
  -- Magisk: patch android-b
  -- Magisk: patch GSI
  -- U-Boot shell
```

> 📸 **[SCREENSHOT PLACEHOLDER: UART console showing U-Boot boot menu with 5-second countdown]**

### U-Boot files in this repository

| File | Purpose |
|------|---------|
| `nethunter-pro/devices/zuma/configs/uboot/husky_defconfig` | U-Boot Kconfig for the husky board |
| `nethunter-pro/devices/zuma/configs/uboot/husky.h` | Board header: DRAM layout, load addresses, 6-target env, Magisk patch commands |
| `nethunter-pro/devices/zuma/configs/uboot/husky-boot.cmd` | U-Boot boot script source (compile with `mkimage -T script`) |

### Building U-Boot

```bash
./scripts/build-uboot.sh
```

This:
1. Clones upstream U-Boot from <https://source.denx.de/u-boot/u-boot>
2. Copies `husky_defconfig` and `husky.h` into the source tree
3. Builds with `aarch64-linux-gnu-` toolchain
4. Wraps the `u-boot.bin` in an Android v4 boot.img → `uboot-husky-boot.img`

### Flashing U-Boot

```bash
# Flash U-Boot to the boot partition
# ⚠ Android will not boot until you reflash a standard boot.img
fastboot flash boot nethunter-pro/.upstream/uboot-husky-boot.img
```

> ⚠️ **WARRANTY VOID** — Flashing U-Boot replaces the kernel in the boot partition.
> To restore: `fastboot flash boot` with any standard Android or NetHunter Pro boot.img.

> 📸 **[SCREENSHOT PLACEHOLDER: Terminal showing build-uboot.sh build output, then fastboot flash boot completing]**

### References

- Upstream U-Boot: <https://source.denx.de/u-boot/u-boot>
- Factory ABL / BCB analysis: <https://github.com/mikethi/zuma-husky-homebootloader>
- FBPK v2 format: `device/google-husky/bootloader/ALGORITHM.txt`

---

## 13. Switching boot targets

Quick reference for all ways to control boot targets:

### Via ADB (device booted into Android or NetHunter Pro)

```bash
# Set persistent target
./addons/boot-selector/scripts/set-target.sh set linux
./addons/boot-selector/scripts/set-target.sh set android-a
./addons/boot-selector/scripts/set-target.sh set android-b
./addons/boot-selector/scripts/set-target.sh set gsi
./addons/boot-selector/scripts/set-target.sh set recovery-a
./addons/boot-selector/scripts/set-target.sh set recovery-b
./addons/boot-selector/scripts/set-target.sh set menu        # shows menu on next boot

# Read current target
./addons/boot-selector/scripts/set-target.sh get

# Clear (reverts to default: linux)
./addons/boot-selector/scripts/set-target.sh clear
```

### Via fastboot (one-shot, device in fastboot mode)

```bash
# Boot a specific target once without changing the persistent flag
fastboot boot -c 'boot_target=android-a'   boot-selector.img
fastboot boot -c 'boot_target=gsi'         boot-selector.img
fastboot boot -c 'boot_target=menu'        boot-selector.img
fastboot boot -c 'boot_target=magisk-patch patch_target=.android-a' boot-selector.img
```

### Via U-Boot interactive menu

Power cycle → U-Boot shows menu → press number key within 5 seconds.

> 📸 **[SCREENSHOT PLACEHOLDER: set-target.sh set android-a output showing "Boot target set to: android-a. Takes effect on next reboot."]**

---

## 14. Troubleshooting

### Android won't boot — black screen or bootloop

**Cause:** dm-verity is blocking boot because vbmeta was not flashed with `--disable-verity`.

**Fix:**
```bash
# Re-run setup with vbmeta disabled
fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
fastboot reboot
```

> 📸 **[SCREENSHOT PLACEHOLDER: Fastboot output showing vbmeta flash with --disable-verity completing]**

### Orange warning screen on Android boot

This is **normal** on an unlocked device. It appears because `androidboot.verifiedbootstate=orange`. It disappears after 5 seconds. To remove it permanently, flash vbmeta with `--disable-verity`.

> 📸 **[SCREENSHOT PLACEHOLDER: Orange Android warning screen — annotated to show this is expected]**

### `fastboot flashing unlock` is greyed out

**Cause:** OEM unlocking was not enabled in Developer Options.

**Fix:** Go to Settings → System → Developer Options → enable OEM unlocking, then try again.

### `kexec -e` failed — boot-selector falls back to linux

**Cause:** The stored kernel binary in the target's userdata store is missing, corrupt, or incompatible.

**Fix:**
```bash
# Re-populate the target store
./addons/boot-selector/scripts/setup-android.sh --factory-zip husky-*.zip
```

### Magisk patch failed — "repack failed"

**Cause:** `magiskboot` couldn't handle the kernel format (e.g. compressed kernel without ramdisk).

**Fix:**
```bash
# Download a newer Magisk APK with an updated magiskboot
./addons/boot-selector/scripts/patch-magisk.sh \
  --apk Magisk-v28.0.apk --push-adb
# Then retry the patch
```

### U-Boot — "BCB read failed — defaulting to slot_a"

**Cause:** UFS driver not yet ported for the zuma SoC; `ab_select` cannot read the misc partition.

**Status:** This is expected. U-Boot defaults to slot\_a. The UFS PHY init and gear-3 configuration for the Exynos UFS controller at 0x13200000 requires additional porting work.

### How to restore factory Android

```bash
# Download the matching factory ZIP from:
#   https://developers.google.com/android/images#husky
# Then flash everything:
./addons/boot-selector/scripts/setup-android.sh \
  --factory-zip husky-ap3a.240905.015.e2-factory-*.zip \
  --full-factory-reset
```

---

## 15. References

### This project

- Repository: <https://github.com/mikethi/nhpro-native-husky>
- Hardware specs: [HARDWARE_SPECS.md](HARDWARE_SPECS.md)
- NetHunter Pro build: [nethunter-pro/README.md](nethunter-pro/README.md)
- Boot-selector: [addons/boot-selector/README.md](addons/boot-selector/README.md)

### Bootloader analysis

- Factory ABL / BCB: <https://github.com/mikethi/zuma-husky-homebootloader>
- FBPK v2 format spec: [`device/google-husky/bootloader/ALGORITHM.txt`](device/google-husky/bootloader/ALGORITHM.txt)
- FBPK extractor: [`scripts/extract_fbpk.py`](scripts/extract_fbpk.py)
- ABL analyser: [`scripts/parse_abl.py`](scripts/parse_abl.py)

### U-Boot

- Upstream U-Boot: <https://source.denx.de/u-boot/u-boot>
- Board config: [`nethunter-pro/devices/zuma/configs/uboot/`](nethunter-pro/devices/zuma/configs/uboot/)

### Android / Pixel

- Factory images (for ARP-safe flashing): <https://developers.google.com/android/images#husky>
- Platform tools (fastboot / adb): <https://developer.android.com/tools/releases/platform-tools>
- GSI images: <https://developer.android.com/topic/generic-system-image/releases>
- AVB / dm-verity docs: <https://source.android.com/docs/security/features/verifiedboot>

### Magisk

- Magisk releases: <https://github.com/topjohnwu/Magisk/releases>
- Magisk documentation: <https://topjohnwu.github.io/Magisk/>

### postmarketOS

- Installation guide: <https://wiki.postmarketos.org/wiki/Installation_guide>
- pmbootstrap docs: <https://docs.postmarketos.org/pmbootstrap/>
- Pixel 8 Pro device page: <https://wiki.postmarketos.org/wiki/Google_Pixel_8_Pro_(google-husky)>

---

*For build options, flags, and detailed NetHunter Pro configuration see [nethunter-pro/README.md](nethunter-pro/README.md).*
