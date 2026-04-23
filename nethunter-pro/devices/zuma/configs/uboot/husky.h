/* SPDX-License-Identifier: GPL-2.0+ */
/*
 * Google Pixel 8 Pro (husky) — U-Boot board include
 * SoC: Google Tensor G3 (zuma / Samsung GS301)
 *
 * Non-ABL boot model: U-Boot is loaded as the "kernel" payload by Google ABL.
 * U-Boot then:
 *   1. Reads the BCB (Bootloader Control Block) from the misc partition to
 *      determine the active A/B slot — independently of the Google ABL.
 *   2. Presents a 10-entry boot menu (6 OS targets + 3 Magisk patch modes +
 *      emergency U-Boot shell).
 *   3. Loads the selected kernel from UFS userdata and boots it.
 *
 * Magisk patch mode (U-Boot function):
 *   U-Boot boots the Sultan kernel with a tiny patch-initrd that runs
 *   magiskboot to patch the target boot.img stored on userdata, then
 *   reboots.  No host tools or Android boot required.
 *
 * All constants extracted from bootloader-husky-ripcurrent-16.4-14540574.img.
 * See scripts/parse_abl.py and scripts/extract_fbpk.py for the methodology.
 *
 * Upstream references:
 *   https://source.denx.de/u-boot/u-boot               — upstream U-Boot
 *   https://github.com/mikethi/zuma-husky-homebootloader — factory ABL
 */

#ifndef __HUSKY_H
#define __HUSKY_H

/* ── Helper stringification macros ────────────────────────────────────────── */
#define _HUSKY_STR(x)  #x
#define HUSKY_STR(x)   _HUSKY_STR(x)

/* ── DRAM ──────────────────────────────────────────────────────────────────
 * pbl.bin and bl31.bin both embed 0x80000000 as the bank-0 base.
 * husky ships with 12 GB total; bank-0 covers the first 8 GB.
 */
#define CONFIG_SYS_SDRAM_BASE		0x80000000UL
#define CONFIG_SYS_SDRAM_SIZE		0x200000000ULL	/* 8 GB bank-0 */

/* Second DRAM bank.
 * bl31.bin contains 0x0000000880000000 as a 64-bit constant.
 * The Tensor G3 places bank-1 at 34 GB (0x8_8000_0000).
 */
#define DRAM_BANK1_BASE			0x880000000ULL

/* ── U-Boot text / stack ───────────────────────────────────────────────────
 * CONFIG_SYS_TEXT_BASE (0xA0800000) identified in bl2.bin as the staging
 * base before kernel hand-off.
 */
#define CONFIG_SYS_INIT_SP_ADDR		(CONFIG_SYS_TEXT_BASE - 0x10)

/* ── Kernel / DTB / ramdisk staging ───────────────────────────────────────
 * KERNEL_LOAD_ADDR matches the text_offset format string in abl.bin.
 * DTB and ramdisk offsets follow the standard arm64 convention.
 */
#define KERNEL_LOAD_ADDR		0x80080000
#define DTB_LOAD_ADDR			0x81000000
#define INITRD_LOAD_ADDR		0x84000000

/* ── Secure DRAM carve-out ─────────────────────────────────────────────────
 * "secure dram base 0x%lx, size 0x%zx" format string in abl.bin.
 * bl2.bin constants show aligned reservations up to 0x92800000.
 */
#define SECURE_DRAM_BASE		0x88800000
#define SECURE_DRAM_SIZE		0x09A00000	/* ~154 MB */

/* ── UFS host controller ───────────────────────────────────────────────────
 * Source: fstab.husky  /dev/block/platform/13200000.ufs
 */
#define UFS_BASE			0x13200000

/* ── USB / fastboot ────────────────────────────────────────────────────────
 * VID/PID confirmed in abl.bin binary.
 */
#define USB_VID				0x18D1		/* Google */
#define USB_PID_FASTBOOT		0x4EE7

/* ── Boot command ──────────────────────────────────────────────────────────
 * Run the autoboot dispatcher which reads boot_target and slot_suffix,
 * selects A/B slot from BCB, then dispatches to the chosen OS or patch mode.
 */
#define CONFIG_BOOTCOMMAND		"run autoboot"

/* ────────────────────────────────────────────────────────────────────────────
 * U-Boot environment — 6 boot targets + Magisk patch mode + bootmenu
 *
 * Userdata store layout (populated by setup-android.sh / patch-magisk.sh):
 *   /userdata/.linux/        kernel  initrd  cmdline   — NetHunter Pro
 *   /userdata/.android-a/    kernel  initrd  cmdline   — Android slot_a
 *   /userdata/.android-b/    kernel  initrd  cmdline   — Android slot_b
 *   /userdata/.gsi/          kernel  initrd  cmdline   — Android GSI
 *   /userdata/.recovery-a/   kernel  initrd  cmdline   — Recovery slot_a
 *   /userdata/.recovery-b/   kernel  initrd  cmdline   — Recovery slot_b
 *   /userdata/.magisk/       patch-initrd.cpio.gz      — Magisk patch env
 *                            magiskboot                — magiskboot binary
 *
 * Magisk patch mode (U-Boot function):
 *   Selected via bootmenu or  setenv patch_target .android-a; run magisk_patch
 *   U-Boot boots the Sultan kernel (.linux/kernel) with .magisk/patch-initrd
 *   as the initrd.  The patch-initrd runs magiskboot, patches the target
 *   kernel, writes it back to userdata, then reboots.
 * ────────────────────────────────────────────────────────────────────────── */
#define CONFIG_EXTRA_ENV_SETTINGS \
\
	/* ── Hardware addresses ───────────────────────────────────────── */ \
	"ufs_dev=0\0" \
	"loadaddr="       HUSKY_STR(KERNEL_LOAD_ADDR)  "\0" \
	"dtb_addr="       HUSKY_STR(DTB_LOAD_ADDR)     "\0" \
	"ramdisk_addr="   HUSKY_STR(INITRD_LOAD_ADDR)  "\0" \
\
	/* ── Base kernel cmdline (hardware constants, always present) ─── */ \
	"base_args=" \
		"earlycon=exynos4210,mmio32,0x10870000 " \
		"console=ttySAC0,115200n8 " \
		"clk_ignore_unused swiotlb=noforce\0" \
\
	/* ── Android-specific cmdline params (unlocked device) ──────── */ \
	/* androidboot.verifiedbootstate=orange  → unlocked, dm-verity relaxed */ \
	/* androidboot.vbmeta.device_state=unlocked → Android init skips strict */ \
	/* androidboot.selinux=permissive         → prevents SELinux denials    */ \
	/* androidboot.boot_devices=13200000.ufs  → UFS path for ueventd rules  */ \
	"android_args=" \
		"androidboot.hardware=zuma " \
		"androidboot.vbmeta.device_state=unlocked " \
		"androidboot.verifiedbootstate=orange " \
		"androidboot.selinux=permissive " \
		"androidboot.boot_devices=13200000.ufs\0" \
\
	/* ── A/B defaults (overridden by set_slot at boot) ──────────── */ \
	"slot_suffix=_a\0" \
	"boot_target=linux\0" \
\
	/* ── A/B: read active slot from BCB (misc partition) ────────── */ \
	/* Requires CONFIG_CMD_AB_SELECT and UFS driver ported.          */ \
	/* BCB layout: bootloader_message_ab / bootloader_control (AOSP) */ \
	"set_slot=" \
		"echo husky: reading A/B slot from misc (BCB)...; " \
		"part number scsi ${ufs_dev} misc misc_part; " \
		"ab_select slot_suffix scsi ${ufs_dev}:${misc_part} || " \
		"  echo husky: BCB read failed - defaulting to slot_a; " \
		"echo husky: active slot: ${slot_suffix}\0" \
\
	/* ── Partition number discovery ─────────────────────────────── */ \
	"set_parts=" \
		"part number scsi ${ufs_dev} userdata  userdata_part; " \
		"part number scsi ${ufs_dev} boot_a    boot_a_part; " \
		"part number scsi ${ufs_dev} boot_b    boot_b_part\0" \
\
	/* ── Load files from userdata ext4 filesystem ───────────────── */ \
	/* ext4load requires UFS driver and EXT4 support.                */ \
	"load_kernel=" \
		"ext4load scsi ${ufs_dev}:${userdata_part} " \
		"${loadaddr} ${store}/kernel\0" \
	"load_initrd=" \
		"ext4load scsi ${ufs_dev}:${userdata_part} " \
		"${ramdisk_addr} ${store}/initrd\0" \
	"load_cmdline=" \
		"ext4load scsi ${ufs_dev}:${userdata_part} " \
		"${loadaddr_tmp} ${store}/cmdline\0" \
\
	/* ── Generic kexec-style boot from userdata store ───────────── */ \
	/* Sets ${store} before calling this env var.                    */ \
	"boot_from_store=" \
		"run set_parts; " \
		"echo husky: loading kernel from ${store}/kernel; " \
		"run load_kernel && run load_initrd && " \
		"booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr} || " \
		"  { run load_kernel; booti ${loadaddr} - ${dtb_addr}; }\0" \
\
	/* ──────────────────────────────────────────────────────────── */ \
	/* Boot target 1: linux — NetHunter Pro (Sultan kernel + NH initrd) */ \
	/* ──────────────────────────────────────────────────────────── */ \
	"boot_linux=" \
		"echo husky: booting NetHunter Pro...; " \
		"setenv store .linux; " \
		"setenv bootargs ${base_args}; " \
		"run boot_from_store\0" \
\
	/* ──────────────────────────────────────────────────────────── */ \
	/* Boot target 2: android-a — Android slot_a                    */ \
	/* dm-verity: relaxed by androidboot.verifiedbootstate=orange   */ \
	/* ARP: ABL already ran; rollback counter not re-checked here   */ \
	/* ──────────────────────────────────────────────────────────── */ \
	"boot_android_a=" \
		"echo husky: booting Android slot_a...; " \
		"setenv store .android-a; " \
		"setenv bootargs ${base_args} ${android_args} " \
			"androidboot.slot_suffix=_a; " \
		"run boot_from_store\0" \
\
	/* Boot target 3: android-b — Android slot_b */ \
	"boot_android_b=" \
		"echo husky: booting Android slot_b...; " \
		"setenv store .android-b; " \
		"setenv bootargs ${base_args} ${android_args} " \
			"androidboot.slot_suffix=_b; " \
		"run boot_from_store\0" \
\
	/* ──────────────────────────────────────────────────────────── */ \
	/* Boot target 4: gsi — Android Generic System Image            */ \
	/* GSI replaces system_a partition; vendor_a stays stock.       */ \
	/* androidboot.dynamic_partitions=true required for GSI mounts  */ \
	/* ──────────────────────────────────────────────────────────── */ \
	"boot_gsi=" \
		"echo husky: booting Android GSI (system_a)...; " \
		"setenv store .gsi; " \
		"setenv bootargs ${base_args} ${android_args} " \
			"androidboot.slot_suffix=_a " \
			"androidboot.dynamic_partitions=true; " \
		"run boot_from_store\0" \
\
	/* ──────────────────────────────────────────────────────────── */ \
	/* Boot targets 5 & 6: recovery slot_a / slot_b                 */ \
	/* androidboot.mode=recovery triggers Android recovery init     */ \
	/* ──────────────────────────────────────────────────────────── */ \
	"boot_recovery_a=" \
		"echo husky: booting Recovery slot_a...; " \
		"setenv store .recovery-a; " \
		"setenv bootargs ${base_args} ${android_args} " \
			"androidboot.slot_suffix=_a " \
			"androidboot.mode=recovery; " \
		"run boot_from_store\0" \
\
	"boot_recovery_b=" \
		"echo husky: booting Recovery slot_b...; " \
		"setenv store .recovery-b; " \
		"setenv bootargs ${base_args} ${android_args} " \
			"androidboot.slot_suffix=_b " \
			"androidboot.mode=recovery; " \
		"run boot_from_store\0" \
\
	/* ──────────────────────────────────────────────────────────── */ \
	/* Magisk patch mode (U-Boot function)                           */ \
	/*                                                               */ \
	/* How it works:                                                  */ \
	/*   1. U-Boot loads the Sultan kernel (.linux/kernel)           */ \
	/*      + patch-initrd (.magisk/patch-initrd.cpio.gz)            */ \
	/*   2. Boots with patch_target=<store> in cmdline               */ \
	/*   3. patch-initrd's /init runs magiskboot to patch the target */ \
	/*      kernel in-place on userdata, then calls `reboot`         */ \
	/*   4. Device reboots back to U-Boot; patched kernel is ready   */ \
	/*                                                               */ \
	/* Prepare with: ./addons/boot-selector/scripts/patch-magisk.sh */ \
	/* ──────────────────────────────────────────────────────────── */ \
	"magisk_patch=" \
		"echo husky: Magisk patch mode for ${patch_target}...; " \
		"run set_parts; " \
		"ext4load scsi ${ufs_dev}:${userdata_part} " \
			"${loadaddr} .linux/kernel; " \
		"ext4load scsi ${ufs_dev}:${userdata_part} " \
			"${ramdisk_addr} .magisk/patch-initrd.cpio.gz; " \
		"setenv bootargs ${base_args} " \
			"patch_target=${patch_target} " \
			"patch_reboot=1; " \
		"booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr}\0" \
\
	"magisk_patch_android_a=" \
		"setenv patch_target .android-a; run magisk_patch\0" \
	"magisk_patch_android_b=" \
		"setenv patch_target .android-b; run magisk_patch\0" \
	"magisk_patch_gsi=" \
		"setenv patch_target .gsi; run magisk_patch\0" \
	"magisk_patch_recovery_a=" \
		"setenv patch_target .recovery-a; run magisk_patch\0" \
	"magisk_patch_recovery_b=" \
		"setenv patch_target .recovery-b; run magisk_patch\0" \
\
	/* ── Boot menu (shown during BOOTDELAY or when boot_target=menu) */ \
	"bootmenu_0=1  NetHunter Pro (Linux)      =run boot_linux\0" \
	"bootmenu_1=2  Android  slot_a            =run boot_android_a\0" \
	"bootmenu_2=3  Android  slot_b            =run boot_android_b\0" \
	"bootmenu_3=4  Android  GSI  (system_a)   =run boot_gsi\0" \
	"bootmenu_4=5  Recovery slot_a            =run boot_recovery_a\0" \
	"bootmenu_5=6  Recovery slot_b            =run boot_recovery_b\0" \
	"bootmenu_6=-- Magisk: patch android-a    =run magisk_patch_android_a\0" \
	"bootmenu_7=-- Magisk: patch android-b    =run magisk_patch_android_b\0" \
	"bootmenu_8=-- Magisk: patch GSI          =run magisk_patch_gsi\0" \
	"bootmenu_9=-- U-Boot shell               =\0" \
	"bootmenu_delay=5\0" \
\
	/* ── Autoboot dispatcher ─────────────────────────────────────── */ \
	/* Reads BCB for slot selection, then dispatches on boot_target. */ \
	/* Falls through to boot_linux (default) if target is unknown.   */ \
	"autoboot=" \
		"run set_slot; " \
		"if test ${boot_target} = menu;        then bootmenu; fi; " \
		"if test ${boot_target} = android-a;   then run boot_android_a; fi; " \
		"if test ${boot_target} = android-b;   then run boot_android_b; fi; " \
		"if test ${boot_target} = gsi;         then run boot_gsi; fi; " \
		"if test ${boot_target} = recovery-a;  then run boot_recovery_a; fi; " \
		"if test ${boot_target} = recovery-b;  then run boot_recovery_b; fi; " \
		"if test ${boot_target} = magisk-a;    then run magisk_patch_android_a; fi; " \
		"if test ${boot_target} = magisk-b;    then run magisk_patch_android_b; fi; " \
		"if test ${boot_target} = magisk-gsi;  then run magisk_patch_gsi; fi; " \
		"run boot_linux\0"

#endif /* __HUSKY_H */
