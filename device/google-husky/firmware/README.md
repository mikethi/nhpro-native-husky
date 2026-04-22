# Google Pixel 8 Pro (husky) – Zuma Firmware Blobs

SoC: **Google Tensor G3 (zuma / Exynos GS301)**

All hardware is driven directly via standard Linux kernel interfaces (no Android HAL layer).
Each subsystem requires one or more binary firmware blobs that the kernel loads at runtime
via `request_firmware()`.  This file documents every blob, the driver that loads it, the
on-device path it must be installed to, and how to obtain it.

---

## How to obtain the blobs

The authoritative source for all firmware listed here is the official **Google Pixel factory
image** for the Pixel 8 Pro (`husky`), available from:

  <https://developers.google.com/android/images#husky>

Extract the `vendor.img` (or `vendor_dlkm.img`) partition from the factory ZIP and pull the
files from the paths shown below.  A helper script is planned at
`scripts/extract-husky-firmware.sh`.

> **License notice** – these blobs are proprietary, non-redistributable Google/vendor firmware.
> They are installed into the `device-google-husky-nonfree-firmware` subpackage and are never
> committed to this repository.

---

## Samsung SCSC WiFi / Bluetooth (S5400, mx140)

| Attribute | Value |
|-----------|-------|
| Driver | `scsc_wlan` / `scsc_bt` |
| Install path | `/lib/firmware/scsc/mx140/` |
| Key blobs | `mx140.bin`, `mx140_t.bin`, `wlan_mib.bin`, `bt_address.bin` |
| modprobe option | `firmware_variant=mx140` (see `husky-modprobe.conf`) |

### Description of changes
The Samsung SCSC combo chip (S5400) uses an internal Cortex-M sub-system called **MX140**.
The `mx140.bin` blob is the full MX140 firmware image loaded by `scsc_wlan` at probe time.
`mx140_t.bin` is the debug/tracing variant used during development.  `wlan_mib.bin` holds
per-board MIB (Management Information Base) calibration values for the 2.4 GHz / 5 GHz
radios.  `bt_address.bin` stores the per-unit Bluetooth device address programmed at the
factory.  No WLAN HAL is involved; the driver speaks nl80211 directly to wpa_supplicant.

---

## Imagination PowerVR BXM-8-256 GPU

| Attribute | Value |
|-----------|-------|
| Driver | `pvrsrvkm` |
| Install path | `/lib/firmware/pvr/` |
| Key blobs | `rogue.fw` |
| modprobe option | `fw_devinfo_name=rogue.fw` (see `husky-modprobe.conf`) |

### Description of changes
The PowerVR BXM-8-256 is an IMG Rogue-family GPU.  `rogue.fw` is the microcode image that
initialises the firmware processor inside the GPU tile.  It is loaded once at `pvrsrvkm`
probe time and handles command scheduling, power management, and fault recovery entirely on
the GPU side.  The driver exposes a DRM/KMS node (`/dev/dri/card0`); no gralloc HAL or
GPU-services daemon is required for display output.

---

## Samsung ABOX Audio DSP

| Attribute | Value |
|-----------|-------|
| Driver | `snd_soc_samsung_abox` |
| Install path | `/lib/firmware/abox/` |
| Key blobs | `abox.bin`, `abox_reload.bin` |
| modprobe option | `firmware_name=abox.bin` (see `husky-modprobe.conf`) |

### Description of changes
The ABOX (Audio Box) is a dedicated Cortex-A DSP inside the Zuma SoC that handles all
audio routing, mixing, and codec communication independently of the application processor.
`abox.bin` is the primary DSP firmware; `abox_reload.bin` is the hot-reload image used
after a DSP crash or system-suspend resume cycle.  The ALSA/ASoC subsystem is the only
user-space interface (PulseAudio / PipeWire); no AudioFlinger HAL is involved.

---

## Shannon 5300 Cellular Modem (cpif / modem_if)

| Attribute | Value |
|-----------|-------|
| Driver | `cpif` / `modem_if` |
| Install path | `/lib/firmware/modem/` |
| Key blobs | `modem.bin`, `modem_nv.bin`, `modem_ipc.bin` |
| modprobe option | `force_use_s5100=1` (see `husky-modprobe.conf`) |

### Description of changes
The Shannon 5300 (SS5300) is Google's in-house 5G sub-6 GHz / mmWave modem.  `modem.bin`
is the complete modem OS image; `modem_nv.bin` contains non-volatile calibration and
carrier-profile data; `modem_ipc.bin` is the inter-processor communication (IPC) shim
that the `cpif` kernel driver uses to set up shared-memory rings between the AP and the
modem.  ModemManager speaks to the modem over the `/dev/umts_ipc*` character devices
exposed by `cpif`; no RIL HAL is needed.

---

## Samsung Pablo ISP (camera)

| Attribute | Value |
|-----------|-------|
| Driver | `pablo_icpu` / `is_sensor_module` |
| Install path | `/lib/firmware/pablo/` |
| Key blobs | `pablo_icpu.bin`, `is_rta.bin` |

### Description of changes
The Pablo ISP (Image Signal Processor) is a multi-core DSP inside Zuma responsible for
RAW-to-YUV processing, 3A (AE/AF/AWB) algorithms, and real-time noise reduction.
`pablo_icpu.bin` is the firmware for the ICPU (ISP Control Processing Unit) Cortex-M core.
`is_rta.bin` is the Real-Time Algorithm firmware image that implements the 3A pipeline.
Both are loaded by `pablo_icpu` during camera pipeline start-up.  V4L2 subdevice nodes are
the only user-space interface; no camera HAL is required.

---

## Google / Samsung NPU – EdgeTPU (Tensor Processing Unit)

| Attribute | Value |
|-----------|-------|
| Driver | `abrolhos` / `exynos_npu` |
| Install path | `/lib/firmware/abrolhos/` |
| Key blobs | `abrolhos.fw`, `gsabin.bin` |

### Description of changes
The **Abrolhos** EdgeTPU is Google's fourth-generation TPU tile embedded in the Tensor G3.
`abrolhos.fw` is the TPU microcode that handles ML inference scheduling, memory management,
and DMA for the INT8 / BF16 matrix-multiply engines.  `gsabin.bin` is the Google Security
Anchor firmware that attests the TPU runtime environment.  The `abrolhos` driver exposes
`/dev/accel0` (DRM-accel subsystem) for direct inference without any HAL or NNAPI daemon.

---

## Installation

The `device-google-husky-nonfree-firmware` APK installs the udev rules and module
configuration.  To install the actual blobs, extract them from the factory image and copy
them to the paths listed above, then trigger a `udevadm trigger` or reboot.

A future `nonfree_firmware()` APKBUILD function will automate the extraction via
`scripts/extract-husky-firmware.sh` once the helper script is available.
