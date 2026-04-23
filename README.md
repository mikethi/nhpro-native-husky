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
