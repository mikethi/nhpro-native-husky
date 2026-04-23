# nhpro-native-husky

**Google Pixel 8 Pro (husky) — postmarketOS & Kali NetHunter Pro, full native kernel hardware control (no HAL)**

→ **[HARDWARE_SPECS.md](HARDWARE_SPECS.md)** — complete hardware table: every component on the Pixel 8 Pro with its driver module name, kernel interface, Sultan kernel source link, firmware path, and mainline kernel equivalent.

## Installation guide (step by step)

### Installation options

- **A: Kali/Debian bare metal build** → use `./build.sh`
- **B: Docker build** → use `./build.sh -d`
- **C: Windows 10 automated setup (PowerShell 7 + WSL2 + Kali)** → use `scripts/setup-wsl-kali.ps1` + `./kali-build.sh`
- **D: postmarketOS (pmbootstrap workflow)** → use `device/google-husky/`

For all NetHunter Pro build options and flags, see: [nethunter-pro/README.md](nethunter-pro/README.md)

### Installation type A/B: Kali NetHunter Pro (Linux host)

#### Prerequisites

- Git: <https://git-scm.com/downloads>
- Android Fastboot (`fastboot`): <https://developer.android.com/tools/releases/platform-tools>
- NetHunter Pro build files in this repo: [nethunter-pro/README.md](nethunter-pro/README.md)
- For **A (bare metal)**: `debos`, `xz-utils`, `android-sdk-libsparse-utils`
- For **B (Docker)**: Docker Engine (<https://docs.docker.com/engine/install/>) and `kali-archive-keyring`

#### Steps

1. Clone this repository and enter the NetHunter build directory:
   ```bash
   source /dev/stdin <<'EOF'
   NHPRO_ROOT="${NHPRO_ROOT:-$PWD/nhpro-native-husky}"
   git clone https://github.com/mikethi/nhpro-native-husky.git "$NHPRO_ROOT"
   cd "$NHPRO_ROOT/nethunter-pro"
   EOF
   ```
2. Install prerequisites:
   - **A (bare metal)**:
     ```bash
     sudo apt update
     sudo apt install -y git debos xz-utils android-sdk-libsparse-utils fastboot
     ```
   - **B (Docker)**:
     ```bash
     sudo apt update
     sudo apt install -y git docker.io kali-archive-keyring fastboot
     ```
3. Build images:
   - **A (bare metal)**: `./build.sh`
   - **B (Docker)**: `./build.sh -d`
4. Enter the output directory and extract `<VERSION>`:
   ```bash
   source /dev/stdin <<'EOF'
   cd "$NHPRO_ROOT/nethunter-pro/.upstream"
   VERSION="$(ls -1t nethunterpro-*-husky-phosh-boot.img | head -n1 | sed -E 's/nethunterpro-(.*)-husky-phosh-boot.img/\1/')"
   [ -n "$VERSION" ] || { echo "No generated NetHunter image files found."; exit 1; }
   echo "$VERSION"
   EOF
   ```
5. Put the phone in bootloader mode and unlock once (this wipes data):
   ```bash
   fastboot flashing unlock
   ```
6. Flash generated images:
   ```bash
   source /dev/stdin <<'EOF'
   fastboot flash boot nethunterpro-${VERSION}-husky-phosh-boot.img
   fastboot flash userdata nethunterpro-${VERSION}-husky-phosh.img
   fastboot reboot
   EOF
   ```

---

### Installation type C: Windows 10 automated setup (PowerShell 7 + WSL2 + Kali)

#### Prerequisites

- Windows 10 build 19041 (20H1) or later — run `winver` to check
- PowerShell 7.2 or later — download from <https://aka.ms/powershell>
- An internet connection

#### Step 1 — Windows: install WSL2, Kali, and usbipd-win

Open **PowerShell 7 as Administrator** (right-click → "Run as administrator"), then run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\setup-wsl-kali.ps1
```

If a reboot is needed to activate WSL features, the script will prompt you. After rebooting, re-run the same command to continue. The script has no options — it is fully automated.

#### Step 2 — Kali: build the NetHunter Pro image

Open the Kali terminal (search "kali" in Start, or run `wsl -d kali-linux`), then:

```bash
source /dev/stdin <<'EOF'
NHPRO_ROOT="${NHPRO_ROOT:-$HOME/nhpro-native-husky}"
cd "$NHPRO_ROOT/nethunter-pro"
./kali-build.sh [OPTIONS]
EOF
```

See [nethunter-pro/README.md](nethunter-pro/README.md#kali-buildsh) for all `kali-build.sh` options.

#### Step 3 — Attach the Pixel 8 Pro and flash

Put the phone in fastboot mode (hold **Power + Volume Down** 10 s), then in an elevated PowerShell window:

```powershell
usbipd list                          # note the BUSID of "Android Bootloader Interface"
usbipd bind   --busid <BUSID>        # one-time binding (requires admin)
usbipd attach --wsl --busid <BUSID>  # attach for this session
```

Back in the Kali terminal, confirm the phone is visible and flash:

```bash
source /dev/stdin <<'EOF'
NHPRO_ROOT="${NHPRO_ROOT:-$HOME/nhpro-native-husky}"
cd "$NHPRO_ROOT/nethunter-pro/.upstream"
fastboot devices
fastboot flashing unlock             # first time only — wipes device
fastboot flash boot     nethunterpro-<VERSION>-husky-phosh-boot.img
fastboot flash userdata nethunterpro-<VERSION>-husky-phosh.img
fastboot reboot
EOF
```

Flash commands with the correct filenames are printed automatically at the end of `kali-build.sh`.

---

### Installation type D: postmarketOS (pmbootstrap workflow)

#### Prerequisites

- postmarketOS installation docs: <https://wiki.postmarketos.org/wiki/Installation_guide>
- pmbootstrap docs: <https://docs.postmarketos.org/pmbootstrap/>
- pmaports tree: <https://gitlab.postmarketos.org/postmarketOS/pmaports>
- Pixel 8 Pro device page: <https://wiki.postmarketos.org/wiki/Google_Pixel_8_Pro_(google-husky)>
- Android Fastboot (`fastboot`): <https://developer.android.com/tools/releases/platform-tools>
- Device package files in this repo: `device/google-husky/`

#### Steps

1. Install `pmbootstrap`:
   ```bash
   source /dev/stdin <<'EOF'
   python3 -m pip install --user pmbootstrap
   EOF
   ```
2. Prepare a local `pmaports` checkout:
   ```bash
   source /dev/stdin <<'EOF'
   PMAPORTS="$HOME/pmaports-husky"
   git clone https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$PMAPORTS"
   EOF
   ```
3. Clone this repository and copy its `google-husky` device tree into your local `pmaports`:
   ```bash
   source /dev/stdin <<'EOF'
   NHPRO_ROOT="${NHPRO_ROOT:-$PWD/nhpro-native-husky}"
   git clone https://github.com/mikethi/nhpro-native-husky.git "$NHPRO_ROOT"
   cp -r "$NHPRO_ROOT/device/google-husky" "$PMAPORTS/device/"
   EOF
   ```
4. Initialize and build/install for `google-husky` with your local `pmaports`:
   ```bash
   source /dev/stdin <<'EOF'
   pmbootstrap --aports "$PMAPORTS" init
   pmbootstrap --aports "$PMAPORTS" install
   EOF
   ```
5. Boot the phone to fastboot mode.
6. Flash generated images using the current `google-husky` instructions from the device wiki page above.

---

## ⚠️⚠️⚠️ U-Boot Secondary Bootloader (Experimental) ⚠️⚠️⚠️

> ### 🔴 WARRANTY VOID — READ BEFORE PROCEEDING 🔴
>
> **FLASHING U-Boot TO THIS DEVICE PERMANENTLY VOIDS YOUR WARRANTY.**
>
> - Unlocking the bootloader (`fastboot flashing unlock`) **wipes all user data** and voids the manufacturer warranty.
> - Flashing U-Boot to the `boot` partition **replaces the Google-signed kernel image** and makes Android unbootable until you manually reflash the original factory image.
> - The **`bootloader` partition is hardware-locked** by the Titan M2 security chip using factory-fused cryptographic keys.  **It cannot be replaced, modified, or patched — ever.**  U-Boot goes in the `boot` partition only (as the kernel payload loaded by Google ABL).
> - The zuma SoC (Google Tensor G3 / Samsung Exynos GS301) has **no upstream U-Boot support** as of this writing.  The config files in this repository (`nethunter-pro/devices/zuma/configs/uboot/`) are a **research/porting starting point** extracted from the factory bootloader image.  **A complete, working U-Boot port for this SoC does not yet exist in upstream U-Boot.**
> - Proceed **only if you understand ARM64 bare-metal bring-up, SoC memory maps, and Android boot image formats**.
> - **You are entirely responsible for any damage to your device.**

---

### U-Boot boot chain on the Pixel 8 Pro

The Pixel 8 Pro uses a four-stage proprietary boot chain before the kernel is reached.  U-Boot cannot replace any of the first three stages (they are TrustZone-protected or Titan-M2-locked), but it *can* replace the kernel payload in the `boot` partition, giving it full second-stage bootloader capability once Google ABL hands off control:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  PIXEL 8 PRO (husky / zuma)  BOOT CHAIN                                     ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Stage    Binary     U-Boot equivalent      Notes                           ║
║  ──────   ────────   ─────────────────────  ───────────────────────────     ║
║  BL1      bl1.bin    U-Boot SPL             Samsung ROM; runs from SRAM     ║
║  PBL      pbl.bin    U-Boot SPL stage 2     Initialises LPDDR5X             ║
║  BL2      bl2.bin    U-Boot proper          SoC / power bring-up            ║
║  ABL      abl.bin    U-Boot + distro-boot   Fastboot, AVB, A/B, kernel      ║
║  BL31     bl31.bin   ARM Trusted Firmware   EL3 SMC handler (TrustZone)     ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  ▲ ALL ABOVE: stored in the `bootloader` partition, Titan M2–verified.      ║
║    HARDWARE LOCKED.  CANNOT BE REPLACED.                                    ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  U-Boot   u-boot.bin  ← packaged as the "kernel" in an Android boot.img    ║
║           └─ stored in the `boot` partition                                  ║
║           └─ loaded and started by Google ABL after `fastboot flashing unlock`║
║           └─ U-Boot then loads your real kernel from UFS / USB / TFTP       ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

Reference configs extracted from `bootloader-husky-ripcurrent-16.4-14540574.img`:
- [`nethunter-pro/devices/zuma/configs/uboot/husky_defconfig`](nethunter-pro/devices/zuma/configs/uboot/husky_defconfig) — U-Boot Kconfig
- [`nethunter-pro/devices/zuma/configs/uboot/husky.h`](nethunter-pro/devices/zuma/configs/uboot/husky.h) — board header (DRAM, load addresses, USB VID/PID)
- [`scripts/parse_abl.py`](scripts/parse_abl.py) — ABL binary analyser that produced these constants
- Factory ABL reference binary: <https://raw.githubusercontent.com/mikethi/zuma-husky-homebootloader/main/abl.bin>

Key memory addresses (from factory ABL / BL2 analysis):

| Constant | Value | Source |
|---|---|---|
| DRAM bank-0 base | `0x80000000` | `pbl.bin`, `bl31.bin` |
| DRAM bank-0 size | `0x200000000` (8 GiB) | `pbl.bin` |
| DRAM bank-1 base | `0x880000000` | `bl31.bin` |
| U-Boot text base | `0xA0800000` | `bl2.bin` staging base |
| Kernel load addr | `0x80080000` | `abl.bin` format string |
| DTB load addr | `0x81000000` | arm64 convention |
| Initrd load addr | `0x84000000` | arm64 convention |
| Secure DRAM base | `0x88800000` | `bl2.bin` |
| Secure DRAM size | `0x09A00000` (~154 MiB) | `bl2.bin` |
| UFS host ctrl | `0x13200000` | `fstab.husky` |
| USB VID | `0x18D1` (Google) | `abl.bin` offset `0x30158` |
| USB PID (fastboot) | `0x4EE7` | `abl.bin` offset `0x88422` |

---

### Prerequisites for all U-Boot install types

Install these on your **build host** in addition to the normal prerequisites for each type:

```bash
# Cross-compiler for aarch64
sudo apt install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu

# U-Boot build tools
sudo apt install -y bison flex libssl-dev python3-setuptools swig \
                    python3-pyelftools bc

# Android boot image tools (needed to wrap U-Boot as a boot.img)
sudo apt install -y android-sdk-libsparse-utils mkbootimg
```

---

### Step 0 (all types): Clone U-Boot and apply the husky board config

> **⚠ The zuma SoC is NOT in upstream U-Boot.  The files in this repo are a porting research base — drivers for UFS, PMIC, USB, and display are not yet implemented.  U-Boot will reach its prompt over the UART console (`ttySAC0`, 3.3 V, 115200 8N1 on test points) but storage and USB bring-up require further porting work.**

```bash
# Clone upstream U-Boot
git clone https://source.denx.de/u-boot/u-boot.git
cd u-boot

# Copy the husky research board config from this repo
# (replace NHPRO_ROOT with the path where you cloned nhpro-native-husky)
NHPRO_ROOT="${NHPRO_ROOT:-$HOME/nhpro-native-husky}"

cp "$NHPRO_ROOT/nethunter-pro/devices/zuma/configs/uboot/husky_defconfig" \
   configs/husky_defconfig

cp "$NHPRO_ROOT/nethunter-pro/devices/zuma/configs/uboot/husky.h" \
   include/configs/husky.h

# Build U-Boot for arm64 using the husky config
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- husky_defconfig
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" 2>&1 | tee uboot-build.log

# The output binary is: u-boot.bin  (or u-boot-nodtb.bin)
ls -lh u-boot.bin
```

#### Wrap U-Boot as an Android boot image

Google ABL expects an Android v4 boot image in the `boot` partition.  U-Boot's binary replaces the kernel position:

```bash
# Create a minimal ramdisk (U-Boot does not use one)
echo | cpio -o -H newc | gzip > /tmp/empty-ramdisk.cpio.gz

mkbootimg \
  --header_version 4 \
  --kernel       u-boot/u-boot.bin \
  --ramdisk      /tmp/empty-ramdisk.cpio.gz \
  --cmdline      "" \
  --base         0x01000000 \
  --pagesize     4096 \
  --kernel_offset    0x00008000 \
  --ramdisk_offset   0x01000000 \
  --tags_offset      0x00000100 \
  --dtb_offset       0x01f00000 \
  --output       uboot-husky-boot.img

ls -lh uboot-husky-boot.img
```

> This image can now be flashed to the `boot` partition via any of the install types below.

---

### U-Boot install type A: Bare metal build (secondary boot)

> **⚠ WARRANTY VOID.  Your device will not run Android until you reflash the factory boot image.**

**Additional prerequisites (type A):**
```bash
sudo apt install -y gcc-aarch64-linux-gnu bison flex libssl-dev \
                    python3-pyelftools mkbootimg
```

**Steps:**
1. Complete **Step 0** above (build `uboot-husky-boot.img`) on your Linux host.
2. Put the phone in bootloader mode (hold **Power + Volume Down** ~10 s).
3. Unlock the bootloader (one-time; wipes all data):
   ```bash
   fastboot flashing unlock
   ```
4. Flash U-Boot to the `boot` partition:
   ```bash
   fastboot flash boot uboot-husky-boot.img
   fastboot reboot
   ```
5. The device will reboot.  If UART is connected (`ttySAC0`, 115200 8N1) you will see the U-Boot prompt.  Without UART the screen will remain black — this is expected because the display driver is not yet implemented in the husky port.

**To restore Android or NetHunter Pro at any time:**
```bash
# Reflash the original kernel boot image
fastboot flash boot nethunterpro-<VERSION>-husky-phosh-boot.img   # NetHunter Pro
# — OR —
fastboot flash boot boot-husky.img                                 # Factory Android
fastboot reboot
```

---

### U-Boot install type B: Docker build (secondary boot)

> **⚠ WARRANTY VOID.  Your device will not run Android until you reflash the factory boot image.**

Docker is used only for building the NetHunter / Kali rootfs.  U-Boot itself is always compiled natively on the host because it does not require the Kali toolchain.

**Steps:**
1. Complete **Step 0** above on your Linux host.
2. Optionally build the full NetHunter Pro rootfs image (for a dual-boot setup):
   ```bash
   cd nethunter-pro
   ./build.sh -d    # build rootfs in Docker
   ```
3. Flash U-Boot to `boot`:
   ```bash
   fastboot flash boot uboot-husky-boot.img
   ```
4. If you want U-Boot to chainload NetHunter Pro from the `userdata` partition, flash the rootfs too:
   ```bash
   fastboot flash userdata nethunterpro-<VERSION>-husky-phosh.img
   ```
5. Reboot:
   ```bash
   fastboot reboot
   ```

---

### U-Boot install type C: Windows 10 / WSL2 (remote / secondary boot)

> **⚠ WARRANTY VOID.  Your device will not run Android until you reflash the factory boot image.**

U-Boot is built inside WSL2 (Kali), and the FBPK tools run there too.  The phone is attached to WSL2 via `usbipd-win`.

#### Step C-1 — WSL2: install build dependencies

Open the Kali terminal (`wsl -d kali-linux`) and run:

```bash
sudo apt update
sudo apt install -y git gcc-aarch64-linux-gnu bison flex libssl-dev \
                    python3-pyelftools bc swig python3-setuptools \
                    android-sdk-libsparse-utils mkbootimg
```

#### Step C-2 — WSL2: clone U-Boot and build

```bash
source /dev/stdin <<'EOF'
NHPRO_ROOT="${NHPRO_ROOT:-$HOME/nhpro-native-husky}"
git clone https://source.denx.de/u-boot/u-boot.git "$HOME/u-boot"
cd "$HOME/u-boot"
cp "$NHPRO_ROOT/nethunter-pro/devices/zuma/configs/uboot/husky_defconfig" configs/husky_defconfig
cp "$NHPRO_ROOT/nethunter-pro/devices/zuma/configs/uboot/husky.h" include/configs/husky.h
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- husky_defconfig
make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)"
echo | cpio -o -H newc | gzip > /tmp/empty-ramdisk.cpio.gz
mkbootimg \
  --header_version 4 --kernel u-boot.bin --ramdisk /tmp/empty-ramdisk.cpio.gz \
  --cmdline "" --base 0x01000000 --pagesize 4096 \
  --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 --dtb_offset 0x01f00000 \
  --output ~/uboot-husky-boot.img
echo "Built: $HOME/uboot-husky-boot.img"
EOF
```

#### Step C-3 — Windows (elevated PowerShell): attach the phone to WSL2

Put the phone in fastboot mode (hold **Power + Volume Down** 10 s), then:

```powershell
usbipd list                          # find BUSID of "Android Bootloader Interface"
usbipd bind   --busid <BUSID>        # one-time binding
usbipd attach --wsl --busid <BUSID>  # attach for this session
```

#### Step C-4 — WSL2: flash U-Boot

```bash
fastboot devices                     # confirm phone is visible
fastboot flashing unlock             # first time only — wipes device
fastboot flash boot ~/uboot-husky-boot.img
fastboot reboot
```

---

### U-Boot install type D: postmarketOS / pmbootstrap (secondary boot)

> **⚠ WARRANTY VOID.  Your device will not run Android until you reflash the factory boot image.**

In the postmarketOS workflow, U-Boot is built separately outside pmbootstrap and flashed directly via fastboot once the device is unlocked.

#### Step D-1 — Build U-Boot (same as Step 0)

Follow **Step 0** above on your Linux build host to produce `uboot-husky-boot.img`.

#### Step D-2 — Optionally build the postmarketOS image

Follow the [postmarketOS install steps](#installation-type-d-postmarketos-pmbootstrap-workflow) in this README to produce and flash the pmOS userdata image first.

#### Step D-3 — Flash U-Boot over the pmOS boot image

```bash
# Boot the phone to fastboot mode
fastboot flash boot uboot-husky-boot.img
fastboot reboot
```

Once U-Boot is running (visible over UART), you can load the pmOS kernel from UFS or over TFTP/USB when those U-Boot drivers are ported.

---

### U-Boot UART console (all types)

The Pixel 8 Pro exposes the debug UART on test points inside the device as `ttySAC0` (Samsung/Exynos UART0, `0x10870000`).  Parameters:

| Setting | Value |
|---|---|
| UART base | `0x10870000` |
| Baud rate | `115200` |
| Format | `8N1` |
| Voltage | `3.3 V` (do **not** connect 5 V adapters) |
| U-Boot `earlycon` string | `earlycon=exynos4210,mmio32,0x10870000` |

Without UART access the screen will remain **black** — the display driver (`exynos_drm` / Wayland compositor) is not part of U-Boot and has not been ported for this SoC.

---

### U-Boot reference links

| Resource | URL |
|---|---|
| U-Boot upstream repository | <https://source.denx.de/u-boot/u-boot> |
| U-Boot ARM Exynos board support | <https://source.denx.de/u-boot/u-boot/-/tree/master/board/samsung> |
| U-Boot documentation | <https://docs.u-boot.org/en/latest/> |
| U-Boot mailing list | <https://lists.denx.de/listinfo/u-boot> |
| husky `abl.bin` reference | <https://raw.githubusercontent.com/mikethi/zuma-husky-homebootloader/main/abl.bin> |
| husky FBPK extractor | [`scripts/extract_fbpk.py`](scripts/extract_fbpk.py) |
| husky ABL analyser | [`scripts/parse_abl.py`](scripts/parse_abl.py) |
| husky U-Boot defconfig | [`nethunter-pro/devices/zuma/configs/uboot/husky_defconfig`](nethunter-pro/devices/zuma/configs/uboot/husky_defconfig) |
| husky U-Boot board header | [`nethunter-pro/devices/zuma/configs/uboot/husky.h`](nethunter-pro/devices/zuma/configs/uboot/husky.h) |
| boot-selector addon (kexec targets) | [`addons/boot-selector/README.md`](addons/boot-selector/README.md) |

---

## Downloadable bundle zip

Create a zip with all tracked repository files plus every HTTP(S) link referenced by those files:

```bash
python3 scripts/create_repo_bundle_zip.py
```

The zip is written to `dist/repo-and-links.zip`.

## Generate a repo with fetched external sources

Create a separate repo-style directory containing the external files this repository fetches, placed in paths matching where they are used:

```bash
python3 scripts/create_fetched_sources_repo.py --force
```

Default output:

- `dist/fetched-sources-repo/`
- `dist/fetched-sources-repo/fetched_sources_manifest.json`

Preview without downloading:

```bash
python3 scripts/create_fetched_sources_repo.py --dry-run --force
```

A GitHub Actions workflow (`Repository Bundle Zip`) also uploads the same zip as a downloadable artifact on pushes and manual runs:

- https://github.com/mikethi/nhpro-native-husky/actions/workflows/repo-bundle.yml

## License requirements for bundled content

- This repository currently declares package licensing metadata as `MIT` in `device/google-husky/APKBUILD`.
- Files downloaded from external links are third-party content and may have different licenses.
- Before redistributing `dist/repo-and-links.zip`, review `linked_files_manifest.json` in the archive and comply with each linked source's license terms.
