# pmos-google-nativehusky

**Google Pixel 8 Pro (husky) — postmarketOS & Kali NetHunter, full native kernel hardware control (no HAL)**

→ **[HARDWARE_SPECS.md](HARDWARE_SPECS.md)** — complete hardware table: every component on the Pixel 8 Pro with its driver module name, kernel interface, Sultan kernel source link, firmware path, and mainline kernel equivalent.

## Installation guide (step by step)

### Installation type A: Kali NetHunter Pro build on bare metal (Kali/Debian host)

#### Prerequisites

- Git: <https://git-scm.com/downloads>
- debos: <https://github.com/go-debos/debos>
- xz-utils: <https://tukaani.org/xz/>
- Android sparse/boot tooling package (`android-sdk-libsparse-utils`): <https://packages.debian.org/search?keywords=android-sdk-libsparse-utils>
- Android Fastboot (`fastboot`): <https://developer.android.com/tools/releases/platform-tools>
- NetHunter Pro build files in this repo: [nethunter-pro/README.md](nethunter-pro/README.md)

#### Steps

1. Clone this repository:
   ```bash
   git clone https://github.com/mikethi/nhpro-native-husky.git
   cd nhpro-native-husky/nethunter-pro
   ```
2. Install prerequisites:
   ```bash
   sudo apt update
   sudo apt install -y git debos xz-utils android-sdk-libsparse-utils fastboot
   ```
3. Build image files:
   ```bash
   ./build.sh
   ```
4. Boot Pixel 8 Pro into bootloader mode and unlock once (this wipes data):
   ```bash
   fastboot flashing unlock
   ```
5. Extract the generated version string (`<VERSION>`) from your build output filenames:
   ```bash
   VERSION="$(ls -1t nethunterpro-*-husky-phosh-boot.img | head -n1 | sed -E 's#nethunterpro-(.*)-husky-phosh-boot.img#\1#')"
   echo "$VERSION"
   ```
   If you have multiple builds, this selects the most recent boot image.
6. Flash generated images:
   ```bash
   fastboot flash boot nethunterpro-${VERSION}-husky-phosh-boot.img
   fastboot flash userdata nethunterpro-${VERSION}-husky-phosh.img
   fastboot reboot
   ```

---

### Installation type B: Kali NetHunter Pro build with Docker

#### Prerequisites

- Git: <https://git-scm.com/downloads>
- Docker Engine: <https://docs.docker.com/engine/install/>
- Kali archive keyring package (`kali-archive-keyring`): <https://packages.debian.org/search?keywords=kali-archive-keyring>
- Android Fastboot (`fastboot`): <https://developer.android.com/tools/releases/platform-tools>
- NetHunter Pro build files in this repo: [nethunter-pro/README.md](nethunter-pro/README.md)

#### Steps

1. Clone this repository:
   ```bash
   git clone https://github.com/mikethi/nhpro-native-husky.git
   cd nhpro-native-husky/nethunter-pro
   ```
2. Install prerequisites:
   ```bash
   sudo apt update
   sudo apt install -y git docker.io kali-archive-keyring fastboot
   ```
3. Build image files with Docker:
   ```bash
   ./build.sh -d
   ```
4. Boot Pixel 8 Pro into bootloader mode and unlock once (this wipes data):
   ```bash
   fastboot flashing unlock
   ```
5. Extract the generated version string (`<VERSION>`) from your build output filenames:
   ```bash
   VERSION="$(ls -1t nethunterpro-*-husky-phosh-boot.img | head -n1 | sed -E 's#nethunterpro-(.*)-husky-phosh-boot.img#\1#')"
   echo "$VERSION"
   ```
   If you have multiple builds, this selects the most recent boot image.
6. Flash generated images:
   ```bash
   fastboot flash boot nethunterpro-${VERSION}-husky-phosh-boot.img
   fastboot flash userdata nethunterpro-${VERSION}-husky-phosh.img
   fastboot reboot
   ```

---

### Installation type C: postmarketOS (pmbootstrap workflow)

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
   python3 -m pip install --user pmbootstrap
   ```
2. Prepare a local `pmaports` checkout:
   ```bash
   PMAPORTS="$HOME/pmaports"
   git clone https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$PMAPORTS"
   ```
3. Clone this repository and copy its `google-husky` device tree into your local `pmaports`:
   ```bash
   git clone https://github.com/mikethi/nhpro-native-husky.git
   cp -r nhpro-native-husky/device/google-husky "$PMAPORTS/device/"
   ```
4. Initialize and build/install for `google-husky` with your local `pmaports`:
   ```bash
   pmbootstrap --aports "$PMAPORTS" init
   pmbootstrap --aports "$PMAPORTS" install
   ```
5. Boot the phone to fastboot mode.
6. Flash generated images using the current `google-husky` instructions from the device wiki page above.

## Downloadable bundle zip

Create a zip with all tracked repository files plus every HTTP(S) link referenced by those files:

```bash
python3 scripts/create_repo_bundle_zip.py
```

The zip is written to `dist/repo-and-links.zip`.

A GitHub Actions workflow (`Repository Bundle Zip`) also uploads the same zip as a downloadable artifact on pushes and manual runs:

- https://github.com/mikethi/pmos-google-nativehusky/actions/workflows/repo-bundle.yml

## License requirements for bundled content

- This repository currently declares package licensing metadata as `MIT` in `device/google-husky/APKBUILD`.
- Files downloaded from external links are third-party content and may have different licenses.
- Before redistributing `dist/repo-and-links.zip`, review `linked_files_manifest.json` in the archive and comply with each linked source's license terms.
