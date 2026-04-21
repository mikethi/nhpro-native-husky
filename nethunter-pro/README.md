# NetHunter Pro – Google Pixel 8 Pro (husky)

Kali [NetHunter Pro](https://www.kali.org/get-kali/#kali-mobile) port for the **Google Pixel 8 Pro** (`husky`, Google Tensor G3 / zuma SoC).

## No-HAL policy

All hardware is accessed directly through standard kernel interfaces.
**No Android Hardware Abstraction Layer (HAL) is used.**

| Subsystem      | Kernel interface         | User-space stack            |
|----------------|--------------------------|-----------------------------|
| WiFi           | nl80211                  | wpa_supplicant / iwd        |
| Bluetooth      | HCI (`/dev/hci0`)        | BlueZ                       |
| Display        | DRM/KMS + Wayland        | phoc / Phosh                |
| Audio          | ALSA / ASoC              | PipeWire + WirePlumber      |
| Camera         | V4L2                     | megapixels / libcamera      |
| Modem          | ModemManager IPC         | ModemManager / oFono        |
| Input          | evdev (`/dev/input`)     | libinput                    |
| Sensors        | IIO subsystem            | iio-sensor-proxy            |
| GPU            | DRM/KMS (pvrsrvkm)       | Mesa / Wayland compositor   |
| USB-C / OTG    | DWC3 + USB PHY           | usbutils / usb-modeswitch   |

## Kernel

Uses the **Sultan kernel** (`kerneltoast/android_kernel_google_zuma`, tag `16.0.0-sultan`).
This kernel enables all of the above interfaces on the zuma SoC without any HAL shim.

## Prerequisites

### Bare metal (Kali or Debian)

```bash
sudo apt install git debos xz-utils mkbootimg fastboot
```

### Docker

```bash
sudo apt install git docker.io kali-archive-keyring
```

## Build

```bash
# bare metal
./build.sh

# Docker
./build.sh -d

# With phosh (default), SSH enabled, compressed output
./build.sh -d -s -z
```

### All options

| Flag | Default | Description |
|------|---------|-------------|
| `-d` | | Use Docker |
| `-e ENV` | `phosh` | Desktop environment (`phosh` \| `plasma-mobile`) |
| `-c` | | Encrypt root filesystem |
| `-R PWD` | | Encryption password |
| `-H NAME` | `kali` | Hostname |
| `-u USER` | `kali` | Username |
| `-p PWD` | `1234` | User password |
| `-s` | | Enable SSH |
| `-Z` | | Enable ZRAM |
| `-z` | | Compress output image |
| `-V VER` | `YYYYMMDD` | Version string |
| `-M URL` | kali mirror | APT mirror |
| `-v` | | Verbose |
| `-D` | | Debug shell on failure |

## Flash

> **⚠ Unlocking the bootloader wipes all data on the device.**

```bash
# 1. Unlock the bootloader (once)
fastboot flashing unlock

# 2. Flash the Sultan kernel boot image
fastboot flash boot   nethunterpro-<VERSION>-husky-phosh-boot.img

# 3. Flash the Kali rootfs to the userdata partition
fastboot flash userdata nethunterpro-<VERSION>-husky-phosh.img

# 4. Reboot
fastboot reboot
```

Default credentials: **kali / 1234**

## Device details

| Field | Value |
|-------|-------|
| Codename | `husky` |
| SoC | Google Tensor G3 (zuma / Exynos GS301) |
| RAM | 12 GiB LPDDR5X |
| Display | 6.7″ LTPO OLED 1344×2992 120 Hz |
| Boot image | Android header v4, pagesize 4096 |
| Kernel cmdline | `earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8 clk_ignore_unused swiotlb=noforce androidboot.hardware=zuma` |
| Flash method | `fastboot` |

## Repository structure

```
nethunter-pro/
├── build.sh                        # Main build script
├── devices/
│   └── zuma/
│       ├── configs/
│       │   └── husky.toml          # Device config (boot image offsets, flash layout)
│       ├── packages-base.yaml      # No-HAL base packages (kernel, firmware, tools)
│       ├── packages-phosh.yaml     # Phosh shell packages
│       └── bootloader.yaml         # mkbootimg boot.img creation + fastboot flash
└── overlays/
    └── husky/
        ├── etc/
        │   ├── modprobe.d/
        │   │   └── husky.conf      # Per-driver options (no HAL)
        │   └── modules-load.d/
        │       └── husky.conf      # Modules loaded at boot
        └── usr/lib/udev/rules.d/
            └── 50-husky-firmware.rules  # Firmware udev rules (no HAL)
```
