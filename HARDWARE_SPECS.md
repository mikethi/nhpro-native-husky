# Google Pixel 8 Pro (husky) — Hardware Specifications & Driver Reference

**SoC:** Google Tensor G3 (internal codename **zuma**, silicon: Exynos GS301)  
**Kernel source:** [kerneltoast/android\_kernel\_google\_zuma @ 16.0.0-sultan](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan)  
**No-HAL policy:** every subsystem below is accessed through a standard Linux kernel interface. No Android Hardware Abstraction Layer (HAL) process is involved.

---

## Quick-reference table

| Subsystem | Hardware | Driver module(s) | Kernel interface | Firmware |
|---|---|---|---|---|
| CPU | 9-core ARMv9 (Klein + Makalu + MakaluELP) | built-in | PSCI / `cpufreq` | — |
| Memory ctrl | LPDDR5X memory controller | built-in | — | — |
| Interrupt ctrl | ARM GIC-600 | `irq_gic_v3` | `/proc/interrupts` | — |
| Arch timer | ARM Generic Timer | built-in | `clocksource` | — |
| Clock tree | Exynos zuma clock controller | `clk_exynos_zuma` | `clk` framework | — |
| PMIC A | Samsung S2MPG14 | `s2mpg14_core` / `s2mpg14_regulator` | `regulator` / `MFD` | — |
| PMIC B | Samsung S2MPG15 | `s2mpg15_core` / `s2mpg15_regulator` | `regulator` / `MFD` | — |
| Storage | UFS 3.1 (Exynos UFS controller) | `ufs_exynos` | `/dev/sda` (`scsi`) | — |
| Display | 6.7 " LTPO OLED, 1344 × 2992, 120 Hz, Samsung S6E3HC4 | `exynos_drm` · `samsung_dsim` · `panel_samsung_s6e3hc4` | DRM/KMS `/dev/dri/card0` | — |
| GPU | Imagination PowerVR BXM-8-256 | `pvrsrvkm` | DRM `/dev/dri/renderD128` | `/lib/firmware/pvr/rogue.fw` |
| WiFi | Samsung SCSC S5400 (mx140) | `scsc_wlan` | nl80211 / `wlan0` | `/lib/firmware/scsc/mx140/` |
| Bluetooth | Samsung SCSC S5400 (mx140) | `scsc_bt` | BlueZ HCI `/dev/hci0` | `/lib/firmware/scsc/mx140/` |
| Cellular | Shannon 5300 (5G sub-6 + mmWave) | `cpif` · `modem_if` | ModemManager / ofono | vendor RFS partition |
| Audio DSP | Samsung ABOX v3 | `snd_soc_samsung_abox` · `snd_soc_samsung_abox_gic` | ALSA/ASoC | `/lib/firmware/abox/abox.bin` |
| Audio amp | Cirrus Logic CS35L45 | `snd_soc_cs35l45` | ALSA/ASoC | — |
| Audio codec | Wolfson/Cirrus WM ADSP | `snd_soc_wm_adsp` | ALSA/ASoC | — |
| Camera ISP | Samsung Pablo ICPU | `pablo_icpu` · `is_sensor_module` · `is_core` | V4L2 `/dev/video*` | — |
| NPU / TPU | Google Tensor Processing Unit (abrolhos) | `abrolhos` | `/dev/abrolhos` | — |
| Touchscreen | Samsung SEC (sec\_ts) | `sec_ts` | evdev `/dev/input/event*` | — |
| GPIO keys | Power · Vol-up · Vol-down (GPA4/GPA6) | `gpio_keys` | evdev `/dev/input/event*` | — |
| USB-C | Synopsys DWC3 + Exynos USB PHY | `dwc3` · `dwc3_exynos` · `phy_exynos_usbdrd` | `xhci-hcd` / gadget | — |
| Thermal | Exynos TMU | `exynos_tmu` | thermal sysfs | — |
| Haptics | TI DRV2624 | `drv2624` | `ff-memless` | — |
| NFC | STMicroelectronics ST21NFC | `st21nfc` | `/dev/nfc*` | — |
| Sensors (IIO) | 6-axis IMU · barometer · ALS · proximity · magnetometer | vendor IIO drivers (see §Sensors) | `iio:device*` · `input` | — |
| Fingerprint | Under-display optical FP sensor | vendor char driver | `/dev/goodix_fp` or similar | — |
| Security | Titan M2 security chip | vendor TEE driver | `/dev/trusty*` | — |
| UART console | Samsung/Exynos UART0 (ttySAC0) | `samsung_serial` | `/dev/ttySAC0` @ 115200 | — |

---

## Detailed sections

---

### 1. CPU — Google Tensor G3 (zuma)

**Full name:** Google Tensor G3 (Exynos GS301)  
**Architecture:** ARMv9-A, AArch64  
**Process node:** Samsung 4 nm LPP  

| Cluster | Cores | Microarch | Freq (max) | `capacity-dmips-mhz` |
|---|---|---|---|---|
| 0 — Efficiency | 4 × cpu0–cpu3 | Klein (≈ Cortex-A510) | ~2.05 GHz | 453 |
| 1 — Performance | 4 × cpu4–cpu7 | Makalu (≈ Cortex-A715) | ~2.45 GHz | 826 |
| 2 — Prime | 1 × cpu8 | MakaluELP (≈ Cortex-X3) | ~2.86 GHz | 1024 |

**CPU driver:** built into the kernel (`arm64` core code + PSCI)  
**PSCI:** SMC-based (`method = "smc"`)  
**DTS node:** [`/cpus`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=compatible+armv9&type=code) in `husky.dts`  
**Mainline reference:** [`Documentation/arm64/`](https://www.kernel.org/doc/html/latest/arm64/index.html)

---

### 2. Memory — LPDDR5X

**Capacity:** 12 GiB LPDDR5X  
**Physical map:**  
- `0x8000_0000` – `0xFFFF_FFFF` (2 GiB, first window)  
- `0x2_8000_0000` – `0x4_FFFF_FFFF` (10 GiB, above 4 GiB boundary)  

**Driver:** built-in memory controller (no loadable module)  
**DTS node:** [`memory@80000000`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=memory%4080000000&type=code)

---

### 3. Interrupt Controller — ARM GIC-600

**Compatible:** `arm,gic-v3`  
**GICD base:** `0x10400000`  
**GICR base:** `0x10440000` (9 redistributors × 0x20000)  
**Driver module:** `irq_gic_v3`  
**Driver source:** [`drivers/irqchip/irq-gic-v3.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/irqchip/irq-gic-v3.c)  
**Mainline source:** [`drivers/irqchip/irq-gic-v3.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/irqchip/irq-gic-v3.c)

---

### 4. Clock Tree — `clk_exynos_zuma`

**Driver module:** `clk_exynos_zuma`  
**Driver source:** [`drivers/clk/samsung/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/clk/samsung)  
**Arch timer clock frequency:** 24 576 000 Hz  
**UART source clock:** 26 MHz (used by `samsung_serial` via `options samsung_serial clkrate=26000000`)  
**Mainline reference:** [`drivers/clk/samsung/`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/clk/samsung)

---

### 5. PMIC — Samsung S2MPG14 / S2MPG15

**Chips:** S2MPG14 (main SoC PMIC), S2MPG15 (sub PMIC)  

| Module | Function | Source |
|---|---|---|
| `s2mpg14_core` | MFD core | [`drivers/mfd/s2mpg14*.c`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=s2mpg14&type=code) |
| `s2mpg14_regulator` | Voltage regulators | [`drivers/regulator/s2mpg14*.c`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=s2mpg14_regulator&type=code) |
| `s2mpg15_core` | MFD core | [`drivers/mfd/s2mpg15*.c`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=s2mpg15&type=code) |
| `s2mpg15_regulator` | Voltage regulators | [`drivers/regulator/s2mpg15*.c`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=s2mpg15_regulator&type=code) |

---

### 6. Storage — UFS 3.1 (Exynos UFS)

**Interface:** UFS HS Gear 4 Lane 2 (HS-G4L2)  
**Driver module:** `ufs_exynos`  
**Driver source:** [`drivers/scsi/ufs/ufs-exynos.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/scsi/ufs/ufs-exynos.c)  
**Kernel interface:** SCSI block device `/dev/sda`  
**modprobe options:**
```
options ufs_exynos ufs_gear=4 ufs_lane=2
```
**Mainline reference:** [`drivers/ufs/host/ufs-exynos.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/ufs/host/ufs-exynos.c)

---

### 7. Display — Samsung S6E3HC4 LTPO OLED

**Panel:** Samsung S6E3HC4  
**Size / resolution:** 6.7 " · 1344 × 2992 · 489 ppi · 1–120 Hz LTPO  
**Interface:** MIPI-DSI  

| Module | Function | Source |
|---|---|---|
| `exynos_drm` | Exynos DRM master driver | [`drivers/gpu/drm/samsung/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/gpu/drm/samsung) |
| `samsung_dsim` | MIPI-DSI controller | [`drivers/gpu/drm/samsung/dpu/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/gpu/drm/samsung/dpu) |
| `panel_samsung_s6e3hc4` | Panel driver | [`drivers/gpu/drm/panel/panel-samsung-s6e3hc4.c`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=s6e3hc4&type=code) |

**Kernel interface:** DRM/KMS — `/dev/dri/card0` (display), `/dev/dri/renderD128` (render)  
**No-HAL:** Wayland compositors (phoc, weston) use `libdrm` directly. No gralloc HAL.

---

### 8. GPU — Imagination PowerVR BXM-8-256

**GPU core:** Imagination Technologies PowerVR BXM-8-256  
**Driver module:** `pvrsrvkm`  
**Driver source:** [`drivers/gpu/drm/img-rogue/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/gpu/drm/img-rogue)  
**Kernel interface:** DRM render node `/dev/dri/renderD128`  
**Firmware:** `/lib/firmware/pvr/rogue.fw`  
**modprobe options:**
```
options pvrsrvkm fw_devinfo_name=rogue.fw
options pvrsrvkm pvr_debug=0
```
**No-HAL:** Mesa Imagination driver (IMG Rogue backend) or `pvr-mesa` used directly via DRM. No gralloc/EGL HAL.  
**Upstream Mesa:** [mesa/mesa — `src/imagination/`](https://gitlab.freedesktop.org/mesa/mesa/-/tree/main/src/imagination)

---

### 9. WiFi — Samsung SCSC S5400

**Chip:** Samsung SCSC S5400 combo (WiFi 6E + BT 5.3)  
**Driver module:** `scsc_wlan`  
**Driver source:** [`drivers/net/wireless/scsc/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/net/wireless/scsc)  
**Kernel interface:** nl80211 — `wlan0` / `cfg80211`  
**Firmware:** `/lib/firmware/scsc/mx140/` (`mx140.bin`, `mx140_t.bin`, calibration)  
**modprobe options:**
```
options scsc_wlan firmware_variant=mx140
options scsc_wlan disable_recovery=N
options scsc_wlan wlbt_panic_on_failure=N
```
**No-HAL:** `wpa_supplicant` or `iwd` connects to nl80211 directly. No WLAN HAL.  
**Userspace tools:** [`wpa_supplicant`](https://w1.fi/wpa_supplicant/) · [`iwd`](https://git.kernel.org/pub/scm/network/wireless/iwd.git) · [`iw`](https://wireless.wiki.kernel.org/en/users/documentation/iw)

---

### 10. Bluetooth — Samsung SCSC S5400

**Chip:** same combo chip as WiFi (S5400 / mx140)  
**Driver module:** `scsc_bt`  
**Driver source:** [`drivers/misc/samsung/scsc_wifibt/scsc_bt/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/misc/samsung/scsc_wifibt/scsc_bt)  
**Kernel interface:** BlueZ HCI — `/dev/hci0`  
**Firmware:** `/lib/firmware/scsc/mx140/` (shared with WiFi)  
**modprobe options:**
```
options scsc_bt use_new_fw=1
```
**No-HAL:** BlueZ `bluetoothd` binds directly to HCI socket. No Bluetooth HAL.  
**Userspace tools:** [`bluez`](http://www.bluez.org/) · [`bluez-tools`](https://github.com/khvzak/bluez-tools)

---

### 11. Cellular Modem — Shannon 5300 (5G)

**Chip:** Samsung Shannon 5300 (S5300)  
**Standards:** 5G SA/NSA sub-6 GHz + mmWave  
**Driver modules:**

| Module | Function | Source |
|---|---|---|
| `cpif` | CP Interface (IPC transport) | [`drivers/net/ethernet/samsung/cpif/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/net/ethernet/samsung/cpif) |
| `modem_if` | Modem interface / boot | [`drivers/misc/samsung/modem_if/`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=modem_if&type=code) |

**Kernel interface:** ModemManager / ofono via `/dev/wwan*` or SIPC  
**modprobe options:**
```
options cpif force_use_s5100=1
```
**No-HAL:** ModemManager manages the modem directly over MBIM/QMI/SIPC. No RIL HAL.  
**Userspace tools:** [`ModemManager`](https://www.freedesktop.org/wiki/Software/ModemManager/) · [`ofono`](https://01.org/ofono) · [`libqmi-utils`](https://www.freedesktop.org/wiki/Software/libqmi/) · [`libmbim-utils`](https://www.freedesktop.org/wiki/Software/libmbim/)

---

### 12. Audio — Samsung ABOX + CS35L45 + WM ADSP

**DSP:** Samsung ABOX v3 (integrated in Tensor G3)  
**Amplifier:** Cirrus Logic CS35L45 (speaker amp)  
**Codec DSP:** Wolfson/Cirrus WM ADSP  

| Module | Function | Source |
|---|---|---|
| `snd_soc_samsung_abox` | ABOX DSP ASoC driver | [`sound/soc/samsung/abox/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/sound/soc/samsung/abox) |
| `snd_soc_samsung_abox_gic` | ABOX GIC helper | [`sound/soc/samsung/abox/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/sound/soc/samsung/abox) |
| `snd_soc_cs35l45` | Cirrus CS35L45 amp | [`sound/soc/codecs/cs35l45.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/sound/soc/codecs/cs35l45.c) |
| `snd_soc_wm_adsp` | WM ADSP codec firmware | [`sound/soc/codecs/wm_adsp.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/sound/soc/codecs/wm_adsp.c) |

**Kernel interface:** ALSA/ASoC — `/dev/snd/controlC0`, `/dev/snd/pcmC0D*`  
**Firmware:** `/lib/firmware/abox/abox.bin`  
**modprobe options:**
```
options snd_soc_samsung_abox firmware_name=abox.bin
options snd_soc_samsung_abox_gic gicd_base=0x10400000
```
**No-HAL:** PipeWire or PulseAudio talks to ALSA directly. No AudioFlinger HAL.  
**Userspace tools:** [`pipewire`](https://pipewire.org/) · [`wireplumber`](https://pipewire.pages.freedesktop.org/wireplumber/) · [`alsa-utils`](https://github.com/alsa-project/alsa-utils)

---

### 13. Camera — Samsung Pablo ISP

**ISP:** Samsung Pablo ICPU (Image Control Processing Unit)  
**Sensors:** 50 MP main (Samsung GNH) · 48 MP ultrawide · 48 MP 5× periscope telephoto  

| Module | Function | Source |
|---|---|---|
| `pablo_icpu` | Pablo ISP firmware controller | [`drivers/media/platform/exynos/camera/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/media/platform/exynos/camera) |
| `is_sensor_module` | Image sensor module driver | [`drivers/media/platform/exynos/camera/sensor/`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=is_sensor_module&type=code) |
| `is_core` | Pablo IS core | [`drivers/media/platform/exynos/camera/`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=is_core&type=code) |

**Kernel interface:** V4L2 — `/dev/video0`, `/dev/video1`, `/dev/video2`  
**No-HAL:** `libcamera` or `v4l2-ctl` accesses sensors directly. No Camera HAL.  
**Userspace tools:** [`v4l-utils`](https://linuxtv.org/wiki/index.php/V4l-utils) · [`libcamera`](https://libcamera.org/) · [`megapixels`](https://megapixels.app/)

---

### 14. NPU / TPU — Google Tensor Processing Unit

**Chip:** Google Tensor Processing Unit (codename **abrolhos**)  
**Driver module:** `abrolhos`  
**Driver source:** [`drivers/misc/abrolhos/`](https://github.com/kerneltoast/android_kernel_google_zuma/search?q=abrolhos&type=code)  
**Kernel interface:** character device `/dev/abrolhos`  
**No-HAL:** Direct `/dev/abrolhos` access or via TensorFlow Lite delegate without NNHAL.

---

### 15. Touchscreen — Samsung SEC

**Controller:** Samsung SEC capacitive touch (sec\_ts)  
**Bus:** I²C  
**Driver module:** `sec_ts`  
**Driver source:** [`drivers/input/touchscreen/sec_ts/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/input/touchscreen/sec_ts)  
**Kernel interface:** evdev — `/dev/input/event*`  
**modprobe options:**
```
options sec_ts irq_type=8
```
**No-HAL:** libinput reads `/dev/input/event*` directly. No touch HAL.

---

### 16. GPIO Keys (Power · Volume up · Volume down)

**SoC GPIO banks:** GPA4 (Power, Vol-down) · GPA6 (Vol-up)  
**Driver module:** `gpio_keys`  
**Driver source:** [`drivers/input/keyboard/gpio_keys.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/input/keyboard/gpio_keys.c)  
**Kernel interface:** evdev — `/dev/input/event*`  
**Linux keycodes:** `KEY_POWER` (116) · `KEY_VOLUMEDOWN` (114) · `KEY_VOLUMEUP` (115)

---

### 17. USB-C — DWC3 + Exynos USB PHY

**Controller:** Synopsys DesignWare USB3 (DWC3) + Exynos USB3 PHY  
**Mode:** OTG dual-role (device ↔ host)  

| Module | Function | Source |
|---|---|---|
| `dwc3` | DWC3 core | [`drivers/usb/dwc3/core.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/usb/dwc3/core.c) |
| `dwc3_exynos` | Exynos glue layer | [`drivers/usb/dwc3/dwc3-exynos.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/usb/dwc3/dwc3-exynos.c) |
| `phy_exynos_usbdrd` | USB3 PHY | [`drivers/phy/samsung/phy-exynos-usbdrd.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/phy/samsung/phy-exynos-usbdrd.c) |

**modprobe options:**
```
options dwc3 dr_mode=otg
```
**Mainline source:** [`drivers/usb/dwc3/`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/usb/dwc3)

---

### 18. Thermal — Exynos TMU

**Sensor:** Exynos Thermal Management Unit (embedded in zuma)  
**Driver module:** `exynos_tmu`  
**Driver source:** [`drivers/thermal/samsung/exynos_tmu.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/thermal/samsung/exynos_tmu.c)  
**Kernel interface:** thermal sysfs `/sys/class/thermal/thermal_zone*`  
**modprobe options:**
```
options exynos_tmu polling_delay=1000
```
**Mainline source:** [`drivers/thermal/samsung/`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/thermal/samsung)

---

### 19. Haptics / Vibrator — TI DRV2624

**Chip:** Texas Instruments DRV2624 (haptic driver + LRA actuator)  
**Bus:** I²C  
**Driver module:** `drv2624`  
**Driver source:** [`drivers/input/misc/drv2624.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/input/misc/drv2624.c)  
**Kernel interface:** `ff-memless` — `/dev/input/event*` (force-feedback)  
**Mainline source:** [`drivers/input/misc/drv2624.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/input/misc/drv2624.c)

---

### 20. NFC — STMicroelectronics ST21NFC

**Chip:** STMicroelectronics ST21NFC  
**Bus:** I²C  
**Driver module:** `st21nfc`  
**Driver source:** [`drivers/nfc/st21nfc/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/nfc/st21nfc)  
**Kernel interface:** NFC character device `/dev/nfc*` · `nfc` netlink socket  
**Userspace tools:** [`neard`](https://01.org/linux-nfc) · [`libnfc`](https://nfc-tools.github.io/projects/libnfc/)

---

### 21. Sensors (IIO / Input)

Sensor hardware on the Pixel 8 Pro is accessed via the Linux **Industrial I/O (IIO)** subsystem — no sensor HAL.

| Sensor | Hardware (approx.) | Driver / subsystem | Kernel interface |
|---|---|---|---|
| 6-axis IMU (accel + gyro) | STMicro LSM6DSO or equivalent | `st_lsm6dsx` / IIO | `/dev/iio:device*` |
| Magnetometer (compass) | AKM AK09918 or equivalent | `ak8975` / IIO | `/dev/iio:device*` |
| Barometer | Bosch BMP390 or equivalent | `bmp280` / IIO | `/dev/iio:device*` |
| Ambient light / proximity | Avago APDS-9253 or equivalent | `apds9960` / IIO | `/dev/iio:device*` |

**IIO driver source:** [`drivers/iio/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/iio)  
**No-HAL:** [`iio-sensor-proxy`](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) exposes sensors over D-Bus to compositors.

---

### 22. Fingerprint Sensor — Under-display optical

**Type:** Under-display optical fingerprint  
**Driver:** vendor character driver (Goodix / Qualcomm FPC via vendor partition)  
**Kernel interface:** `/dev/goodix_fp` (or `/dev/fpc1020`)  
**No-HAL:** The pmos / Kali environment does not use the fingerprint HAL. PAM module `pam_fprint` with a custom backend can interface with the character device once a mainline driver is available.

---

### 23. Titan M2 Security Chip

**Chip:** Google Titan M2 (discrete security microcontroller)  
**Function:** Secure boot verification, hardware key storage, TPM-like operations  
**Driver:** Vendor TEE / Trusty driver  
**Kernel interface:** `/dev/trusty-ipc-*` or `/dev/gsc*`  
**Driver source:** [`drivers/trusty/`](https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan/drivers/trusty)  
**No-HAL note:** In pmos/Kali environments, Titan M2 can be used for PKCS#11 key operations via `libgsc` or `tpm2-tools` once driver support matures.

---

### 24. UART Console — ttySAC0

**MMIO base:** `0x10870000`  
**Baud rate:** 115200 n8  
**Driver module:** `samsung_serial`  
**Driver source:** [`drivers/tty/serial/samsung_tty.c`](https://github.com/kerneltoast/android_kernel_google_zuma/blob/16.0.0-sultan/drivers/tty/serial/samsung_tty.c)  
**Kernel interface:** `/dev/ttySAC0`  
**Kernel cmdline:** `earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8`  
**modprobe options:**
```
options samsung_serial clkrate=26000000
```
**Mainline source:** [`drivers/tty/serial/samsung_tty.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/tty/serial/samsung_tty.c)

---

## Module load order at boot

The following `modules-load.d` sequence ensures correct dependency ordering (storage first, then clocks/power, then everything else):

```
ufs_exynos            # 1. Storage  — rootfs must be readable first
clk_exynos_zuma       # 2. Clocks
s2mpg14_core          # 3. PMIC
s2mpg15_core
s2mpg14_regulator
s2mpg15_regulator
irq_gic_v3            # 4. Interrupts
exynos_drm            # 5. Display
samsung_dsim
panel_samsung_s6e3hc4
pvrsrvkm              # 6. GPU
scsc_wlan             # 7. WiFi
scsc_bt               # 8. Bluetooth
cpif                  # 9. Modem
modem_if
snd_soc_samsung_abox  # 10. Audio
snd_soc_samsung_abox_gic
snd_soc_cs35l45
snd_soc_wm_adsp
pablo_icpu            # 11. Camera
is_sensor_module
is_core
abrolhos              # 12. NPU
sec_ts                # 13. Touchscreen
gpio_keys             # 14. Keys
dwc3                  # 15. USB
dwc3_exynos
phy_exynos_usbdrd
exynos_tmu            # 16. Thermal
drv2624               # 17. Haptics
st21nfc               # 18. NFC
```

Full config: [`device/google-husky/firmware/husky-modules.conf`](device/google-husky/firmware/husky-modules.conf)  
Full modprobe options: [`device/google-husky/firmware/husky-modprobe.conf`](device/google-husky/firmware/husky-modprobe.conf)

---

## Scheduler & Frequency Tuning Parameters

All values below are written by `init.zuma.rc` at boot.  Every numeric parameter
is annotated here with its unit, percentage-of-maximum, and whether it is a
**hardware-safety** limit (required to prevent physical damage) or an
**OEM policy** choice (a power/battery trade-off with no safety justification).

---

### PELT multiplier — `/proc/sys/kernel/sched_pelt_multiplier`

| Phase | Value | Meaning |
|---|---|---|
| `early-init` | 1 | Slowest ramp — prevents premature CPU boost during startup |
| `sys.boot_completed=1` | **4** | Maximum — full-speed load tracking for normal operation |

Scale: 1–4.  At value 1 the EAS PELT algorithm tracks task demand 4× more slowly,
making the frequency governor under-responsive to new load.  Restored to 4 after boot.
**Category:** OEM policy (boot optimisation only — no hardware-safety role post-boot).

---

### TEO idle governor — `/proc/vendor_sched/teo_util_threshold`

| Parameter | Value | Meaning |
|---|---|---|
| Little cores (cpu0–cpu3) | 2 | Util gate ≈ 0.2 % — go deep-idle only if almost completely idle |
| Mid cores (cpu4–cpu7) | 1024 | Disabled — always go to deepest available idle state |
| Prime core (cpu8) | 1024 | Disabled — always go to deepest available idle state |

Controls when the TEO governor considers utilisation when choosing an idle state.
This is a **power/latency trade-off** (affects wake-up latency, not peak throughput).
**Category:** OEM power policy.

---

### uclamp_max — scheduler group utilisation caps

`uclamp_max` limits the scheduler's perceived utilisation for a task group.  When a
task's demand is capped, the frequency governor will not boost above the OPP that
corresponds to that percentage.  **Scale: 0 = 0 %, 1024 = 100 % (uncapped), −2 = kernel max.**

#### Per-CPU automatic cap — `/proc/vendor_sched/auto_uclamp_max`

| CPU cluster | Value (this repo) | Percentage | Was (upstream) |
|---|---|---|---|
| cpu0–cpu3 (Little, Klein) | **1024** | 100 % — uncapped | 130 (~12.7 %) |
| cpu4–cpu7 (Mid, Makalu) | **1024** | 100 % — uncapped | 512 (50 %) |
| cpu8 (Prime, MakaluELP) | **1024** | 100 % — uncapped | 670 (~65.4 %) |

#### Scheduler group caps — `/proc/vendor_sched/groups/<group>/uclamp_max`

| Group | Value (this repo) | Percentage | Was (upstream) | Notes |
|---|---|---|---|---|
| `bg` (background) | **1024** | 100 % — uncapped | 130 (~12.7 %) | Background pentest tools need full CPU access |
| `sys_bg` (system bg) | **1024** | 100 % — uncapped | 512 (50 %) | OEM policy removed |
| `ota` (OS updates) | **1024** | 100 % — uncapped | 512 (50 %) | OEM policy removed |
| `dex2oat` (JIT) | −2 | uncapped | −2 (uncapped) | Unchanged |

**Category:** All upstream caps were OEM battery/power policy — **no hardware-safety
role**.  Removed.  The thermal framework (TMU + cooling devices) handles any actual
hardware-protection throttling independently of these scheduler caps.

#### uclamp_max filter — `/proc/vendor_sched/uclamp_max_filter_enable`

| Parameter | Value (this repo) | Was (upstream) |
|---|---|---|
| `uclamp_max_filter_enable` | **0** (disabled) | 1 (enabled) |
| `uclamp_max_filter_divider` | 4 | 4 |
| `uclamp_max_filter_rt` | 16 | 16 |

The filter was a second layer of runtime throttling that could dynamically further
reduce group uclamp_max values.  **No hardware-safety purpose** — disabled.

---

### PMU-based adaptive frequency limits — `sched_pixel`

These limits engage **only** when the workload is memory-bandwidth-limited.
`spc_threshold` (stalls-per-cycle) measures how often the CPU pipeline is stalled
waiting for DRAM.  When SPC > threshold the CPU is bottlenecked by memory, not
compute: running faster yields no performance gain and wastes power.  The kernel
then caps frequency at `limit_frequency` until the stall condition clears.

`lcpi_threshold 0` = LCPI-based path disabled; only SPC path active.
`pmu_limit_enable 1` = explicitly enabled (previously implicit/undocumented).

| Cluster | Max freq | `spc_threshold` | `limit_frequency` | Limit (% of peak) |
|---|---|---|---|---|
| policy0 — Little (cpu0–cpu3, Klein) | ~2050 MHz | 76 | 1,328,000 kHz = **1.328 GHz** | ~64.8 % |
| policy4 — Mid (cpu4–cpu7, Makalu) | ~2450 MHz | 73 | 1,836,000 kHz = **1.836 GHz** | ~74.9 % |
| policy8 — Prime (cpu8, MakaluELP) | ~2860 MHz | 68 | 2,363,000 kHz = **2.363 GHz** | ~82.6 % |

**Category:** Legitimate performance optimisation (not an OEM restriction).  For
non-memory-bound workloads the caps never engage.  For memory-bound workloads
they prevent wasted power at no performance cost.  The `spc_threshold` and
`limit_frequency` values are kept from the upstream Pixel configuration.
`pmu_poll_time 10` = PMU sampling interval, 10 ms.

---

### Runtime read access

All `sched_pixel` sysfs nodes and `/proc/vendor_sched/*` entries are owned
`system:system` with mode `0644` (read by any user) after the `on init` chown
block runs.  You can inspect the live state at any time:

```bash
# Current per-policy limit frequency (kHz):
cat /sys/devices/system/cpu/cpufreq/policy0/sched_pixel/limit_frequency
cat /sys/devices/system/cpu/cpufreq/policy4/sched_pixel/limit_frequency
cat /sys/devices/system/cpu/cpufreq/policy8/sched_pixel/limit_frequency

# PMU enable flags (1 = enabled):
cat /sys/devices/system/cpu/cpufreq/policy0/sched_pixel/pmu_limit_enable
cat /sys/devices/system/cpu/cpufreq/policy4/sched_pixel/pmu_limit_enable
cat /sys/devices/system/cpu/cpufreq/policy8/sched_pixel/pmu_limit_enable

# Scheduler group uclamp_max (1024 = uncapped):
cat /proc/vendor_sched/groups/bg/uclamp_max
cat /proc/vendor_sched/groups/sys_bg/uclamp_max

# PELT multiplier (should be 4 post-boot):
cat /proc/sys/kernel/sched_pelt_multiplier
```

---

## References

| Resource | Link |
|---|---|
| Sultan kernel source | <https://github.com/kerneltoast/android_kernel_google_zuma/tree/16.0.0-sultan> |
| Mainline kernel (torvalds) | <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git> |
| postmarketOS device wiki | <https://wiki.postmarketos.org/wiki/Google_Pixel_8_Pro_(google-husky)> |
| Tensor G3 (zuma) SoC info | <https://en.wikipedia.org/wiki/Google_Tensor#Tensor_G3> |
| Linux DRM/KMS docs | <https://www.kernel.org/doc/html/latest/gpu/index.html> |
| ALSA/ASoC docs | <https://www.kernel.org/doc/html/latest/sound/index.html> |
| V4L2 docs | <https://www.kernel.org/doc/html/latest/userspace-api/media/v4l/v4l2.html> |
| nl80211 / cfg80211 docs | <https://wireless.wiki.kernel.org/en/developers/documentation/nl80211> |
| BlueZ HCI docs | <http://www.bluez.org/> |
| ModemManager docs | <https://www.freedesktop.org/software/ModemManager/doc/latest/> |
| Linux IIO docs | <https://www.kernel.org/doc/html/latest/driver-api/iio/index.html> |
| libdrm | <https://gitlab.freedesktop.org/mesa/drm> |
| Mesa (IMG Rogue) | <https://gitlab.freedesktop.org/mesa/mesa/-/tree/main/src/imagination> |
| libcamera | <https://libcamera.org/> |
| iio-sensor-proxy | <https://gitlab.freedesktop.org/hadess/iio-sensor-proxy> |
| PipeWire | <https://pipewire.org/> |
