# Google Pixel 8 Pro (Husky) – Hardware Values from Device Tree

**SoC:** Google Tensor G3 (zuma / Exynos GS301)  
**Compatible:** `google,zuma`  
**Revision:** A0 (FOPLP, IPOP) / B0 (IPOP)

---

## CPU Configuration

### Cluster 0 – Efficiency (Klein cores)
| Property | Value | Hex | Notes |
|----------|-------|-----|-------|
| Cores | 4 (cpu0–cpu3) | — | ARMv9-A Klein (≈Cortex-A510) |
| Capacity DMIPS/MHz | 193 | 0xc1 | Power-efficient profile |
| Dynamic Power Coefficient | 70 | 0x46 | Power model for scheduling |
| Idle State | c2 (PSCI 0x10000) | — | Local timer stop |
| Entry Latency | 70 µs | 0x46 | — |
| Exit Latency | 160 µs | 0xa0 | — |
| Min Residency | 2000 µs | 0x7d0 | Threshold for C2 entry |

### Cluster 1 – Performance (Makalu cores)
| Property | Value | Hex | Notes |
|----------|-------|-----|-------|
| Cores | 4 (cpu4–cpu7) | — | ARMv9-A Makalu (≈Cortex-A715) |
| Capacity DMIPS/MHz | 927 | 0x39f | Balanced performance/power |
| Dynamic Power Coefficient | 513 | 0x201 | — |
| Idle State | c2 (PSCI 0x10000) | — | — |
| Entry Latency | 150 µs | 0x96 | — |
| Exit Latency | 190 µs | 0xbe | — |
| Min Residency | 2500 µs | 0x9c4 | — |

### Cluster 2 – Prime (MakaluELP core)
| Property | Value | Hex | Notes |
|----------|-------|-----|-------|
| Cores | 1 (cpu8) | — | ARMv9-A MakaluELP (≈Cortex-X3) |
| Capacity DMIPS/MHz | 1024 | 0x400 | Peak performance |
| Dynamic Power Coefficient | 757 | 0x2f5 | High power draw |
| Idle State | c2 (PSCI 0x10000) | — | — |
| Entry Latency | 235 µs | 0xeb | — |
| Exit Latency | 220 µs | 0xdc | — |
| Min Residency | 3500 µs | 0xdac | — |

---

## Memory Layout

### Physical Address Space
| Region | Base Address | Size | Purpose |
|--------|--------------|------|---------|
| First Window | 0x80000000 | 2 GiB | Kernel/DRAM (32-bit mapped) |
| Second Window | 0x2_80000000 | 10 GiB | High-memory (above 4 GiB) |
| **Total** | — | **12 GiB LPDDR5X** | — |

### Reserved Memory (from DTS `reserved-memory`)

#### Firmware & Boot
| Name | Address | Size | Status | Purpose |
|------|---------|------|--------|---------|
| ect_binary | 0x90000000 | 0x60000 | active | Exynos calibration table |
| gsa@90200000 | 0x90200000 | 0x3ff000 | active | Google Security Analog |
| gsa@905FF000 | 0x905ff000 | 0x1000 | active | GSA extension |
| abl | 0xf8800000 | 0x2000000 | active | Android Bootloader |

#### Accelerators
| Name | Address | Size | Status | Purpose |
|------|---------|------|--------|---------|
| gxp_fw | 0x91d00000 | 0x300000 | active | NPU (GXP) firmware |
| gxp_mcu_fw | 0x92000000 | 0x400000 | active | NPU MCU firmware |
| gxp_scratchpad | 0x91300000 | 0x60000 | active | NPU scratchpad |
| gxp_secure_data | 0x91400000 | 0x900000 | active | NPU secure data |
| iif_wait_table | 0x91360000 | 0x20000 | active | NPU IIF wait table |
| iif_signal_table | 0x91380000 | 0x20000 | active | NPU IIF signal table |
| tpu_fw | 0x93000000 | 0x1000000 | active | TPU (Tensor) firmware |
| aoc | 0x94000000 | 0x3000000 | active | Audio-on-Chip |

#### Logging & Debugging
| Name | Address | Size | Status | Purpose |
|------|---------|------|--------|---------|
| bldr_log_reserved | 0xfd800000 | 0x100000 | active | Bootloader log |
| ramoops_mem | 0xfd3ff000 | 0x400000 | active | Kernel panic buffer |
| dss_log_reserved | 0xfd3f0000 | 0xe000 | active | Debug snapshot log |
| debug_kinfo_reserved | 0xfd3fe000 | 0x1000 | active | Kernel info |
| header | 0xd8100000 | 0x10000 | active | Log header |
| log_kevents | 0xd8110000 | 0x700000 | active | Kernel events |
| log_bcm | 0xdd610000 | 0x400000 | **disabled** | BCM logs |
| log_s2d | 0xd8810000 | 0x1800000 | active | System logs |
| log_s2d_extract | 0xdda20000 | 0x600000 | active | Log extraction |
| log_array_reset | 0xda010000 | 0xa00000 | active | Reset logs |
| log_array_panic | 0xdaa10000 | 0xa00000 | **disabled** | Panic logs |
| log_itmon | 0xdda10000 | 0x10000 | active | ITMON logs |

#### Cellular Modem
| Name | Address | Size | Purpose |
|------|---------|------|---------|
| cp_rmem | 0xea400000 | 0xc00000 | Modem main memory (rmem_index=0) |
| cp_rmem_1 | 0xe8000000 | 0x2000000 | Modem extended (rmem_index=2) |
| cp_msi_rmem | 0xf6200000 | 0x1000 | Modem MSI (rmem_index=1) |
| cp_aoc_rmem | 0x197fd000 | 0x3000 | Modem AOC (rmem_index=3) |

#### DMA Heaps (Trusty TEE)
| Name | Size | Purpose |
|------|------|---------|
| vstream | 0x4800000 | Video stream buffer |
| vframe | 0x20000000 | Video frame buffer (512 MB) |
| vscaler | 0x3400000 | Video scaler buffer |
| tui | 0x1800000 | Trusted UI |
| gcma_camera | 0x6400000 | Camera GCMA |
| faceauth_dsp | 0x2000000 | Face auth DSP |
| faceauth_tpu | 0x1000000 | Face auth TPU |
| famodel | 0x4b00000 | Face auth model |
| farawimg | 0x5000000 | Face auth raw image |
| faprev | 0xc00000 | Face auth preview |
| mfc_fw | 0x210000 | Media codec firmware |

#### USB DMA
| Name | Address | Size | Purpose |
|------|---------|------|---------|
| xhci_dma_buffer | 0x17bb5000 | 0xb000 | XHCI transfer buffer |
| xhci_dma | 0x17bc0000 | 0x40000 | XHCI DMA pool |
| xhci_dma_dram | 0x97000000 | 0x400000 | XHCI DRAM pool |

#### Security
| Name | Address | Size | Purpose |
|------|---------|------|---------|
| seclog_mem | 0xc3000000 | 0x90000 | Security log (exynos,seclog) |
| dpado-rmem | — | 0x200000 | **disabled** | DP ADO |

---

## Interrupt Controller – ARM GIC-600

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `arm,gic-v3` | ARM Generic Interrupt Controller v3 |
| GICD Base | 0x10400000 | Global Distributor (shared) |
| GICR Base | 0x10440000 | Redistributor base |
| GICR Stride | 0x20000 | Per-redistributor offset |
| Redistributors | 9 | One per core (4+4+1) + shared regions |
| Max SPIs | 960 (GICv3) | Shared Peripheral Interrupts |
| IRQ Lines | 16–1019 | GIC IRQ numbering |

### Notable Interrupts
| IRQ | Source | Type | Purpose |
|-----|--------|------|---------|
| 0x15b (347) | GPU | FIQ | Mali GPU job interrupt |
| 0x15c (348) | GPU | FIQ | Mali GPU MMU interrupt |
| 0x15a (346) | GPU | FIQ | Mali GPU main interrupt |
| 0x2a4 (676) | S2MPG14 | IRQ | Primary PMIC |
| 0x2a5 (677) | S2MPG15 | IRQ | Secondary PMIC |

---

## UART Console

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `samsung,exynos-serial` | Samsung Exynos UART |
| Base Address | 0x10870000 | MMIO (memory-mapped) |
| Device Node | `/dev/ttySAC0` | Serial console |
| Baud Rate | 115200 | 8N1 (8 bits, no parity, 1 stop) |
| Clock Rate | 26000000 Hz | 26 MHz source clock |
| Early Console | `earlycon=exynos4210,mmio32,0x10870000` | Early boot output |

---

## Display – LTPO OLED Panel

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `samsung,s6e3hc4` | Samsung Dynamic AMOLED 2 |
| Resolution | 1344 × 2992 | Portrait (FHD+) |
| Aspect Ratio | 19.5:9 | Nearly fullscreen |
| Refresh Rate | 120 Hz | Adaptive LTPO |
| Color Depth | 24-bit RGB | 8-bits per channel |
| DRM Master | `exynos_drm` | DRM/KMS display driver |
| DSI Controller | `samsung_dsim` | Samsung MIPI-DSI |
| Pixel Density | ~512 ppi | High DPI |

---

## GPU – ARM Mali-T6xx

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `arm,malit6xx` | ARM Mali T600-series |
| Base Address | 0x1f000000 | MMIO window |
| Size | 0x480000 | 4.7 MB |
| Firmware | `rogue.fw` | Imagination PowerVR Rogue |
| Max Frequency | 890000 kHz | 890 MHz |
| Power Policy | `adaptive` | Dynamic frequency scaling |
| Interrupts | 3 (JOB, MMU, GPU) | — |
| Power Domains | top, cores | Multi-domain management |
| DVFS Governor | `quickstep_use_mcu` | Custom frequency scaling |
| Hysteresis | 60 ms | Idle tolerance |

### DVFS Tables (Sample)
| Frequency (kHz) | Voltage | Load (%) |
|-----------------|---------|----------|
| 141000 (min) | 0.55V | — |
| 314000 | 0.56V | — |
| ... | ... | ... |
| 890000 (max) | 0.87V | — |

---

## Power Management ICs (S2MPG14 / S2MPG15)

### S2MPG14 (Primary)
| Property | Value | Notes |
|----------|-------|-------|
| Function | Core power rails | CPU, GPU, NPU |
| IRQ | 0x2a4 (676) | Interrupt line |
| Modules | core, regulator | PMU + voltage regulation |

### S2MPG15 (Secondary)
| Property | Value | Notes |
|----------|-------|-------|
| Function | Peripheral rails | Memory, I/O, etc. |
| IRQ | 0x2a5 (677) | — |
| Modules | core, regulator | — |

---

## Clock Controller – Exynos Zuma

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `samsung,exynos-clock` | Custom Exynos clock driver |
| Base Address | 0x10800000 | Clock register window |
| Size | 0x800000 | 8 MB |
| Module | `clk_exynos_zuma` | Kernel driver |

---

## USB-C & OTG

| Property | Value | Notes |
|----------|-------|-------|
| USB Controller | `dwc3` (DesignWare) | USB 3.0/3.1 controller |
| Base Address | 0x1e100000 | — |
| PHY | `exynos_usbdrd` | Exynos USB3 dual-role PHY |
| Mode | OTG | Device + Host capable |
| dr_mode | `otg` | Dual-role operation |
| DMA Pools | 3 (xhci_dma*) | Separate DMA regions |

---

## Thermal Management Unit (TMU)

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `samsung,exynos-tmu` | Exynos Thermal Management |
| Module | `exynos_tmu` | Kernel driver |
| Polling Interval | 1000 ms | Temperature check rate |
| Zones | Multiple | Per-domain cooling |

---

## Touchscreen – Samsung SEC

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `samsung,sec_ts` | Samsung SEC touchscreen |
| Bus | I2C | Interrupt-driven I2C device |
| GPIO Bank | GPA6 | GPIO interrupt pin |
| IRQ Type | 8 (LEVEL_LOW) | Active-low interrupt |
| Module | `sec_ts` | Kernel driver |

---

## NFC

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `st,st21nfc` | STMicroelectronics NFC |
| Bus | SPI / I2C | Platform-dependent |
| Module | `st21nfc` | Kernel driver |

---

## Vibrator / Haptics

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `ti,drv2624` | Texas Instruments haptic driver |
| Bus | I2C | Haptic feedback IC |
| Module | `drv2624` | Kernel driver |

---

## Architecture Timer Clock

| Property | Value | Notes |
|----------|-------|-------|
| Clock Frequency | 24576000 Hz | ~24.576 MHz |
| Purpose | ARM generic timer (CNTP, CNTV) | System tick source |
| Used By | Kernel timekeeping | Time-of-day, scheduling |

---

## Boot Image Configuration

| Property | Value | Notes |
|----------|-------|-------|
| Format | Android boot.img header v4 | Latest Android format |
| Pagesize | 2048 bytes | Load unit |
| Base Address | 0x01000000 | Kernel load address |
| Kernel Offset | 0x00008000 | From base |
| Ramdisk Offset | 0x01000000 | From base |
| Tags Offset | 0x00000100 | From base |
| DTB Offset | 0x01f00000 | Appended to kernel |
| Partition Scheme | A/B (atomic updates) | Dual boot partitions |
| Flash Method | fastboot | Android fastboot protocol |

---

## Energy Model (Pixel EM)

The `pixel-em` node in DTS contains **per-CPU energy coefficients** used by Linux scheduler for:
- **EAS (Energy-Aware Scheduling):** Task placement for power efficiency
- **Power predictions:** Dynamic power estimation
- **Thermal throttling:** Frequency capping under thermal load

Profiles are defined per CPU cluster with frequency-to-power mappings.

---

## PSCI (Power State Coordination Interface)

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `arm,psci-1.0` | ARM PSCI v1.0 |
| Method | `smc` | Secure Monitor Call |
| CPU Idle | PSCI 0x10000 | CPU_SUSPEND function |

---

## Trusty TEE (Trusted Execution Environment)

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `android,trusty-smc-v1` | Google Trusty TEE |
| SMC Calls | Multiple | Secure services |
| IPI Range | 0x08–0x0f | Inter-processor interrupts |
| DMA Heaps | 10+ | Secure & reusable pools |
| Protection IDs | 0x00–0x20 | SMMU protection domains |

---

## Video Processor Unit (BigWave)

| Property | Value | Notes |
|----------|-------|-------|
| Compatible | `google,bigwave` | Google video processor |
| Base Address | 0x1a700000 | MMIO |
| Interrupts | 0xa4 (164) | FIQ |
| OPP Table | 4 frequencies | 100–711 MHz |
| Bandwidth Table | 4 scenarios | 1080p/2160p @ 30/60fps |

---

## References

- **Kernel DTS Source:** `device/google-husky/husky.dts`
- **Compiled DTB:** `device/google-husky/husky.dtb`
- **Alternative DTBs:** 
  - `zuma-a0-foplp.dtb` (A0 FOPLP variant)
  - `zuma-a0-ipop.dtb` (A0 IPOP variant)
  - `zuma-b0-ipop.dtb` (B0 IPOP variant)

