# Google Pixel 8 Pro (Husky) – DTS Reference for Bare-Metal Linux
## Critical Hardware Values Extracted from device/google-husky/husky.dts

**Purpose:** This document extracts bare-metal hardware addresses and configuration parameters from the device tree source (husky.dts) that are essential for proper no-HAL Linux kernel operation on the Google Tensor G3 (Zuma) SoC.

---

## 1. Memory Map (from husky.dts reserved-memory)

### Main DRAM
```
Physical address space: 12 GiB LPDDR5X

Window 1 (32-bit mapped):
  Base: 0x80000000
  Size: 2 GiB
  Use:  Kernel, initramfs, root filesystem

Window 2 (above 4 GiB):
  Base: 0x2_80000000 (high memory, phandle <0x238>)
  Size: 10 GiB
  Use:  User process memory, large allocations
```

### Reserved Firmware & System Memory (do NOT use for general purpose)

```
Location        Size       Purpose
────────────────────────────────────────────────────────────
0x90000000      0x60000    ECT binary (Exynos calibration table)
0x90200000      0x3ff000   GSA (Google Security Analog) primary
0x905ff000      0x1000     GSA extension
0x91300000      0x60000    GXP (NPU) scratchpad
0x91360000      0x20000    GXP IIF wait table
0x91380000      0x20000    GXP IIF signal table
0x91400000      0x900000   GXP secure data
0x91d00000      0x300000   GXP firmware (⚠ reserved, no-map)
0x92000000      0x400000   GXP MCU firmware (no-map)
0x93000000      0x1000000  TPU firmware 16 MB (no-map)
0x94000000      0x3000000  AOC (Audio-on-Chip) 48 MB (no-map)
0xf8800000      0x2000000  ABL (Android Bootloader) 32 MB (no-map)
0xc3000000      0x90000    Security log (exynos,seclog)

Modem (Shannon 5300):
0xea400000      0xc00000   Main modem memory (rmem_index=0)
0xe8000000      0x2000000  Extended modem memory (rmem_index=2)
0xf6200000      0x1000     Modem MSI (rmem_index=1)
0x197fd000      0x3000     Modem AOC (rmem_index=3)

Logging & Debug:
0xfd800000      0x100000   Bootloader log
0xfd3ff000      0x400000   ramoops (kernel panic buffer)
0xfd3f0000      0xe000     DSS log (debug snapshot)
0xd8100000      0x10000    Log header
0xd8110000      0x700000   Kernel events
0xd8810000      0x1800000  System logs (S2D)
0xdda20000      0x600000   Log extraction
0xda010000      0xa00000   Reset logs
0xdda10000      0x10000    ITMON logs

Trusty TEE DMA Heaps (reusable/shared):
0x03 (phandle)  0x4800000  vstream (video stream, 72 MB)
0x04 (phandle)  0x20000000 vframe (video frame, 512 MB) ⚠ large
0x05 (phandle)  0x3400000  vscaler (video scaler, 52 MB)
0x06 (phandle)  0x1800000  tui (trusted UI, 24 MB)
0x213 (phandle) 0x6400000  gcma_camera (camera, 100 MB)
0x07 (phandle)  0x2000000  faceauth_dsp (face auth DSP, 32 MB)
0x08 (phandle)  0x1000000  faceauth_tpu (face auth TPU, 16 MB)
0x214 (phandle) 0x4b00000  famodel (face model, 75 MB)
0x0a (phandle)  0x5000000  farawimg (face raw image, 80 MB)
0x0c (phandle)  0xc00000   faprev (face preview, 12 MB)
0x0d (phandle)  0x210000   mfc_fw (media codec firmware, 2 MB)

USB DMA pools:
0x17bb5000      0xb000     XHCI transfer buffer
0x17bc0000      0x40000    XHCI DMA pool (256 KB)
0x97000000      0x400000   XHCI DRAM pool (4 MB)
```

---

## 2. Peripheral Base Addresses (MMIO)

### Critical Peripherals for Bare-Metal Boot

```
Component              Base Address  Size        Purpose                    Module
─────────────────────────────────────────────────────────────────────────────────
Interrupt Controller   0x10400000    0x80000     ARM GIC-600 (GICD)        irq_gic_v3
  GICD (distributor)   0x10400000    —           Interrupt distributor
  GICR (redistributor) 0x10440000    0x20000×9   Per-CPU redistributors
Clock Controller       0x10800000    0x800000    Exynos Zuma clocks        clk_exynos_zuma
UART0 (ttySAC0)       0x10870000    —           Serial console            samsung_serial
  (early console: earlycon=exynos4210,mmio32,0x10870000)

GPU (Mali-T6xx)       0x1f000000    0x480000    Imagination PowerVR       pvrsrvkm
  Interrupts:
    JOB               0x15b (347)    FIQ         Job queue
    MMU               0x15c (348)    FIQ         Memory management
    GPU               0x15a (346)    FIQ         GPU main interrupt

USB 3.0 (DWC3)        0x1e100000    —           DesignWare USB 3.1        dwc3/dwc3_exynos
USB PHY (Exynos)      —              —           USB dual-role PHY         phy_exynos_usbdrd

Video Processor (BigWave) 0x1a700000 0x860      Google VPU                bigwave
  SSMT PID            0x1a6a4000    0xa00       Streaming memory tagging

Audio DSP (ABOX)      —              —           Samsung audio on-chip     snd_soc_samsung_abox
  GIC base (param)    0x10400000    —           Passed to driver

Display (Exynos DRM)  —              —           DRM/KMS master            exynos_drm
  DSIM (MIPI-DSI)     —              —           Samsung DSI controller    samsung_dsim
  Panel (s6e3hc4)     —              —           LTPO OLED (1344×2992)    panel_samsung_s6e3hc4

Modem (Shannon 5300)  —              —           Cellular baseband         modem_if/cpif
  IPC                 —              —           Modem IPC driver

Camera (Pablo ISP)    —              —           Samsung image processor   pablo_icpu
  Sensors             —              —           Camera sensor driver      is_sensor_module

NPU / EdgeTPU         —              —           Tensor/GXP processor      abrolhos/exynos_npu

Thermal (TMU)         —              —           Temperature sensing       exynos_tmu
Power Management ICs:
  S2MPG14 (primary)   —              IRQ 676     Core power (CPU/GPU/NPU)  s2mpg14_*
  S2MPG15 (secondary) —              IRQ 677     Peripheral power          s2mpg15_*

Touchscreen (SEC)     —              I2C         Samsung SEC (sec_ts)      sec_ts

NFC (ST21NFC)         —              SPI/I2C     STMicroelectronics        st21nfc

Vibrator (DRV2624)    —              I2C         Texas Instruments haptic  drv2624
```

### Example: GIC-600 Configuration from husky.dts (lines 136–142)

```dts
intc {
    compatible = "arm,gic-v3";
    #address-cells = <0x02>;
    #size-cells = <0x02>;
    ranges;
    #interrupt-cells = <0x03>;
    interrupt-controller;
    reg = <0x00 0x10400000 0x00 0x80000>,  // GICD base + size
          <0x00 0x10440000 0x00 0x180000>; // GICR base + size (9 redistributors @ stride 0x20000)
    interrupts = <0x01 0x09 0x04>;        // PPI for parent interrupt
};
```

### Interrupt Routing

```
Shared Peripheral Interrupts (SPIs) assigned to drivers:
  IRQ 0x2a4 (676)  → S2MPG14 (primary PMIC)
  IRQ 0x2a5 (677)  → S2MPG15 (secondary PMIC)
  IRQ 0x15a (346)  → GPU main
  IRQ 0x15b (347)  → GPU job queue
  IRQ 0x15c (348)  → GPU MMU
  IRQ 0xa4  (164)  → BigWave VPU
  ...
```

---

## 3. CPU Configuration (from husky.dts lines 549–732)

### CPU Clusters

```
Cluster 0 – LITTLE (Klein cores, ≈Cortex-A510)
  Cores:              cpu0–cpu3 (4 cores)
  Frequency (max):    ~2.05 GHz
  Capacity DMIPS/MHz: 193 (0xc1, hex in DTS)
  Dynamic Power Coeff: 70 (0x46)
  Idle state:         c2 (PSCI 0x10000)
  Entry latency:      70 µs
  Exit latency:       160 µs
  Min residency:      2000 µs

Cluster 1 – BIG (Makalu cores, ≈Cortex-A715)
  Cores:              cpu4–cpu7 (4 cores)
  Frequency (max):    ~2.45 GHz
  Capacity DMIPS/MHz: 927 (0x39f)
  Dynamic Power Coeff: 513 (0x201)
  Idle state:         c2 (PSCI 0x10000)
  Entry latency:      150 µs
  Exit latency:       190 µs
  Min residency:      2500 µs

Cluster 2 – PRIME (MakaluELP core, ≈Cortex-X3)
  Cores:              cpu8 (1 core)
  Frequency (max):    ~2.86 GHz
  Capacity DMIPS/MHz: 1024 (0x400)
  Dynamic Power Coeff: 757 (0x2f5)
  Idle state:         c2 (PSCI 0x10000)
  Entry latency:      235 µs
  Exit latency:       220 µs
  Min residency:      3500 µs
```

### PSCI (ARM Power State Coordination Interface)

```dts
psci {
    compatible = "arm,psci-1.0";
    method = "smc";        // Secure Monitor Call
    cpu_suspend = <0x10000>; // CPU_SUSPEND function
};
```

**For bare-metal Linux:**
- PSCI method must be `"smc"` (SMC calls into secure firmware)
- CPU idle states are defined per-core via `arm,psci-suspend-param = <0x10000>`
- Kernel uses PSCI for CPU hotplug, CPU suspend, and system reset

---

## 4. Clock Controller (from husky.dts line 230)

```dts
clocks@10800000 {
    compatible = "samsung,exynos-clock";
    reg = <0x00 0x10800000 0x00 0x800000>;  // 8 MB register window
};
```

**Module:** `clk_exynos_zuma`  
**Provides:** Clock sources for CPU, GPU, peripherals  
**Must initialize:** Very early in kernel boot (before CPU frequency scaling)

---

## 5. UART Console (from husky.dts line 17–18, deviceinfo line 18)

```dts
serial@10870000 {
    compatible = "samsung,exynos-serial";
    reg = <0x00 0x10870000 0x00 0x1000>;
    interrupts = <0x01 ...>;
    clock-names = "uart", "clk_uart_baud0";
};
```

**Device:** `/dev/ttySAC0`  
**Baud rate:** 115200 n8 (8 bits, no parity, 1 stop bit)  
**Clock:** 26 MHz (from modprobe.conf: `clkrate=26000000`)  
**Early console:** `earlycon=exynos4210,mmio32,0x10870000` (kernel cmdline)

---

## 6. Power Domains & Clock Scaling

### CPU frequency scaling (from husky.dts lines 823–871: exynos-acme)

Three independent frequency domains, one per cluster:

```
Domain 0 (LITTLE – Klein):
  CPUs:         0–3
  CAL-ID:       0xb040002
  Min freq:     323000 kHz (~323 MHz)
  Max freq:     1728000 kHz (~1.73 GHz)
  Governor:     EAS (Energy-Aware Scheduler) + EMU coefficient

Domain 1 (BIG – Makalu):
  CPUs:         4–7
  CAL-ID:       0xb040003
  Min freq:     398000 kHz (~398 MHz)
  Max freq:     2361000 kHz (~2.36 GHz)
  Governor:     EAS

Domain 2 (PRIME – MakaluELP):
  CPUs:         8
  CAL-ID:       0xb040004
  Min freq:     500000 kHz (~500 MHz)
  Max freq:     2873000 kHz (~2.87 GHz)
  Governor:     EAS + need-awake (keep awake for responsiveness)
```

**Kernel driver:** `cpufreq-dt` (uses operating-points-v2 tables)  
**No HAL:** Linux scheduler directly scales frequency via cpufreq, no HAL intervention

---

## 7. Display (from husky.dts lines 169–179)

```dts
display {
    compatible = "samsung,s6e3hc4";
    resolution = <1344 2992>;
    refresh-rate = <120>;  // LTPO (Adaptive refresh rate)
    color-depth = <24>;    // RGB, 8-bits per channel
    dpi = <512>;           // ~512 pixels per inch
};
```

**Panel:** Samsung Dynamic AMOLED 2 (1344 × 2992 @ 120 Hz LTPO)  
**DRM master:** `exynos_drm` (no gralloc HAL)  
**DSI controller:** `samsung_dsim` (MIPI-DSI v1.2)  
**Kernel modules:** `exynos_drm`, `samsung_dsim`, `panel_samsung_s6e3hc4`

---

## 8. Boot Image Parameters (from deviceinfo lines 21–31)

Used by `mkbootimg` to create the `boot.img` flashed to the `/boot` partition:

```
Format:             Android boot header v4 (latest)
Page size:          4096 bytes
Base address:       0x00000000
Kernel offset:      0x00008000 (32 KB from base)
Ramdisk offset:     0x01000000 (16 MB from base)
Tags offset:        0x00000100 (256 bytes from base)
DTB offset:         0x01f00000 (31 MB from base) – APPENDED to kernel

Partition scheme:   A/B atomic updates (fastboot)
Flash method:       fastboot (not dd or similar)
```

**Example mkbootimg command:**
```bash
mkbootimg \
  --header_version 4 \
  --kernel kernel.gz \
  --ramdisk initramfs.cpio.gz \
  --dtb husky.dtb \
  --cmdline "earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8 ..." \
  --base 0x00000000 \
  --pagesize 4096 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 \
  --dtb_offset 0x01f00000 \
  -o boot.img
```

---

## 9. Trusty TEE – Secure DMA Heaps

Reserved memory regions allocated to the Trusty TEE (Google's Trusted Execution Environment) for secure services:

```
DMA Heap                  Size        Location          Purpose
──────────────────────────────────────────────────────────────────
vstream                   72 MB       0x...             Video stream
vframe                    512 MB      0x...             Video frame (large!)
vscaler                   52 MB       0x...             Video scaler
tui                       24 MB       0x...             Trusted UI
gcma_camera               100 MB      0x...             Camera processing
faceauth_dsp              32 MB       0x...             Face auth DSP
faceauth_tpu              16 MB       0x...             Face auth TPU
famodel                   75 MB       0x...             Face auth model
farawimg                  80 MB       0x...             Face auth raw images
faprev                    12 MB       0x...             Face auth preview
mfc_fw                    2 MB        0x...             Media codec firmware
```

**For no-HAL Linux:** These regions remain in reserved-memory and are NOT accessed directly by userspace. Trusty TEE continues to provide secure services (e.g., keypair generation, DRM) via SMC calls from the kernel.

---

## 10. Kernel Command Line (from deviceinfo line 18)

```bash
earlycon=exynos4210,mmio32,0x10870000 \
  console=ttySAC0,115200n8 \
  clk_ignore_unused \
  swiotlb=noforce \
  androidboot.hardware=zuma
```

**Explanation:**
- `earlycon=...` – Serial output before main console driver loads (UART @ 0x10870000)
- `console=ttySAC0,115200n8` – Main console device after boot
- `clk_ignore_unused` – Keep clocks enabled (prevents subsystem shutdown)
- `swiotlb=noforce` – Disable software IOMMU fallback (hardware IOMMU is available)
- `androidboot.hardware=zuma` – Device identifier for hardware-specific init scripts

---

## References

- **husky.dts (full):** 14,000+ lines, defines all hardware nodes
- **husky.dtb (compiled):** Binary device tree blob, ~1.5 MB
- **Kernel DTS path in mainline:** `arch/arm64/boot/dts/google/`
- **Exynos SoC docs:** Samsung S.LSI public datasheets (limited availability)
- **Tensor G3 block diagram:** Google I/O presentations, Pixel 8 Pro teardowns

---

## How to Use This Reference

### For Device Driver Development:
1. Extract relevant base address from this document
2. Cross-reference with kernel source (`drivers/*/`)
3. Use `of_iomap()` to map MMIO regions in driver probe

### For Bootloader Development:
1. Ensure early clocks (clk_exynos_zuma) are initialized
2. Set up GIC-600 interrupt routing
3. Configure UART @ 0x10870000 for early debug output

### For Firmware Extraction:
1. Identify reserved-memory regions (do NOT compress/overwrite)
2. Preserve GSA (Google Security Analog) @ 0x90200000
3. Ensure TPU firmware @ 0x93000000 and GXP firmware @ 0x91d00000 are pre-loaded by bootloader

### For No-HAL Linux Porting:
1. Use this document to validate kernel .config options
2. Enable `CONFIG_ARM_PSCI_CPUIDLE` for CPU power states
3. Enable `CONFIG_EXYNOS_CPUFREQ_DT` for frequency scaling
4. Load modules in order: clock → PMIC → GIC → UFS → rest

