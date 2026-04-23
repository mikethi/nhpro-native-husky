/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * Google Pixel 8 Pro (husky) — U-Boot board include
 * SoC: Google Tensor G3 (zuma / Samsung GS301)
 *
 * All constants below were extracted from the factory FBPK v2 bootloader
 * image (bootloader-husky-ripcurrent-16.4-14540574.img) using the tooling
 * in scripts/extract_fbpk.py and scripts/parse_abl.py:
 *
 *   pbl.bin / bl2.bin / bl31.bin  → DRAM layout, carve-outs, text base
 *   abl.bin                       → kernel load address, cmdline tokens,
 *                                   USB VID/PID, secure-DRAM format strings
 *   fstab.husky                   → UFS host controller base address
 */

#ifndef __HUSKY_H
#define __HUSKY_H

/* ── DRAM ──────────────────────────────────────────────────────────────────
 * pbl.bin and bl31.bin both embed 0x80000000 as the bank-0 base.
 * husky ships with 12 GB total; bank-0 covers the first 8 GB.
 */
#define CONFIG_SYS_SDRAM_BASE		0x80000000UL
#define CONFIG_SYS_SDRAM_SIZE		0x200000000ULL	/* 8 GB bank-0 */

/* Second DRAM bank.
 * bl31.bin contains 0x0000000880000000 as a 64-bit constant.
 * The Tensor G3 memory map places bank-1 at 34 GB (0x8_8000_0000),
 * NOT at 4 GB (0x1_0000_0000) as on SDM845 / SDM888 boards.
 */
#define DRAM_BANK1_BASE			0x880000000ULL

/* ── U-Boot text / stack ───────────────────────────────────────────────────
 * CONFIG_SYS_TEXT_BASE (0xA0800000) is defined in the defconfig; it was
 * identified in bl2.bin as the staging base before kernel hand-off.
 */
#define CONFIG_SYS_INIT_SP_ADDR		(CONFIG_SYS_TEXT_BASE - 0x10)

/* ── Kernel / DTB / ramdisk staging ───────────────────────────────────────
 * KERNEL_LOAD_ADDR matches the text_offset format string found in abl.bin.
 * DTB and ramdisk offsets follow the standard arm64 convention used across
 * all Pixel (zuma/gs101/gs201) board ports.
 */
#define KERNEL_LOAD_ADDR		0x80080000
#define DTB_LOAD_ADDR			0x81000000
#define INITRD_LOAD_ADDR		0x84000000

/* ── Secure DRAM carve-out ─────────────────────────────────────────────────
 * abl.bin contains the format string "secure dram base 0x%lx, size 0x%zx".
 * bl2.bin shows aligned constants up through 0x92800000 before usable DRAM
 * begins, consistent with a ~154 MB reservation for TrustZone / BL31 / GSA.
 */
#define SECURE_DRAM_BASE		0x88800000
#define SECURE_DRAM_SIZE		0x09A00000	/* ~154 MB */

/* ── UFS host controller ───────────────────────────────────────────────────
 * Sourced from fstab.husky: /dev/block/platform/13200000.ufs
 */
#define UFS_BASE			0x13200000

/* ── USB / fastboot ────────────────────────────────────────────────────────
 * VID/PID confirmed in abl.bin binary (abl offset 0x30158 / 0x88422).
 */
#define USB_VID				0x18D1		/* Google */
#define USB_PID_FASTBOOT		0x4EE7

/* ── Boot command ──────────────────────────────────────────────────────────
 * Load an Android boot image from $loadaddr and hand off to the kernel.
 * Matches the abootimg / bootm flow used by the generic arm64 Android path.
 */
#define CONFIG_BOOTCOMMAND \
	"abootimg addr $loadaddr; bootm $loadaddr"

#endif /* __HUSKY_H */
