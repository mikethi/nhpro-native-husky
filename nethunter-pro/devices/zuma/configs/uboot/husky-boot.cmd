# Google Pixel 8 Pro (husky) — U-Boot boot script
# SoC: Google Tensor G3 (zuma / Samsung GS301)
#
# Compile to a U-Boot script image with:
#   mkimage -A arm64 -T script -C none \
#           -n "husky boot script" \
#           -d husky-boot.cmd husky-boot.scr
#
# Load and run from U-Boot prompt with:
#   ext4load scsi 0:<userdata_part> 0xA1000000 .linux/husky-boot.scr
#   source 0xA1000000
#
# Or embed via CONFIG_BOOTCOMMAND / CONFIG_EXTRA_ENV_SETTINGS in husky.h.
#
# ── Overview ────────────────────────────────────────────────────────────────
# This script implements the full 6-target + Magisk patch boot menu for the
# Google Pixel 8 Pro running U-Boot in non-ABL mode.
#
# Non-ABL mode means: U-Boot replaces the kernel in the boot_a/boot_b
# partition.  Google ABL loads U-Boot as if it were the Linux kernel, then
# U-Boot takes full control of boot selection independently of ABL's own slot
# decision.  It reads the BCB (Bootloader Control Block) from the misc
# partition and selects the active A/B slot from there.
#
# ── Boot targets ────────────────────────────────────────────────────────────
#  1. linux       — NetHunter Pro (Sultan kernel + Kali initrd)
#  2. android-a   — Android slot_a
#  3. android-b   — Android slot_b
#  4. gsi         — Android Generic System Image (system_a replaced by GSI)
#  5. recovery-a  — Android Recovery slot_a
#  6. recovery-b  — Android Recovery slot_b
#
# ── Magisk patch mode ───────────────────────────────────────────────────────
# U-Boot can patch any stored kernel with Magisk WITHOUT needing a running
# Android or a connected PC.  It boots a tiny patch-initrd (containing
# magiskboot, magiskinit, magisk64) under the Sultan kernel, which patches
# the target boot.img on userdata, then reboots.
#
# Prepare the patch environment first on the host:
#   ./addons/boot-selector/scripts/patch-magisk.sh --apk Magisk.apk --push-adb
#
# ── Userdata store layout ────────────────────────────────────────────────────
#   /data/.linux/          kernel  initrd  cmdline   NetHunter Pro
#   /data/.android-a/      kernel  initrd  cmdline   Android slot_a
#   /data/.android-b/      kernel  initrd  cmdline   Android slot_b
#   /data/.gsi/            kernel  initrd  cmdline   Android GSI
#   /data/.recovery-a/     kernel  initrd  cmdline   Recovery slot_a
#   /data/.recovery-b/     kernel  initrd  cmdline   Recovery slot_b
#   /data/.magisk/         patch-initrd.cpio.gz      Magisk patch initrd
#
# ── Anti-Rollback Protection (ARP) note ────────────────────────────────────
# ARP is enforced by the ABL on the bootloader partition via Titan M2.
# U-Boot operates AFTER ABL has already run; the rollback counter was checked
# when ABL booted U-Boot.  Kexec-style booting from userdata does not
# re-trigger ARP.  However: if you update the ABL to a newer version, the
# Titan M2 programs the rollback counter and you CANNOT downgrade the ABL.
# Always match your factory Android images to your ABL version.
#
# ── dm-verity note ───────────────────────────────────────────────────────────
# On an unlocked device the ABL injects:
#   androidboot.verifiedbootstate=orange
#   androidboot.vbmeta.device_state=unlocked
# These are forwarded to the Android kernel via the cmdline set in this
# script, causing Android's init to relax dm-verity enforcement (orange
# warning screen, then normal boot).  To fully disable dm-verity run:
#   fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
# (scripts/setup-android.sh does this automatically)
#
# ── References ───────────────────────────────────────────────────────────────
#   https://source.denx.de/u-boot/u-boot         — upstream U-Boot
#   https://github.com/mikethi/zuma-husky-homebootloader — factory ABL / BCB

# ============================================================================
# Hardware constants (match husky.h)
# ============================================================================
setenv ufs_dev       "0"
setenv loadaddr      "0x80080000"
setenv dtb_addr      "0x81000000"
setenv ramdisk_addr  "0x84000000"

# ============================================================================
# Kernel cmdline components
# ============================================================================

# Hardware-specific early console and bus params (always present)
setenv base_args \
    "earlycon=exynos4210,mmio32,0x10870000 console=ttySAC0,115200n8 \
    clk_ignore_unused swiotlb=noforce"

# Android-specific params for an unlocked device
#   verifiedbootstate=orange → dm-verity relaxed, orange warning screen shown
#   vbmeta.device_state=unlocked → Android init skips strict AVB enforcement
#   selinux=permissive → prevents SELinux denials during early boot
#   boot_devices → ueventd uses this to create /dev/block/by-name symlinks
setenv android_args \
    "androidboot.hardware=zuma \
    androidboot.vbmeta.device_state=unlocked \
    androidboot.verifiedbootstate=orange \
    androidboot.selinux=permissive \
    androidboot.boot_devices=13200000.ufs"

# ============================================================================
# Step 1 — Determine active A/B slot from BCB (misc partition)
# ============================================================================
# The BCB (Bootloader Control Block) is stored in the misc partition.
# It contains the bootloader_message_ab / bootloader_control structures
# defined in AOSP system/core/bootloader_message/.
# ab_select reads the 'slot_suffix' field and sets the named env var.
# If this fails (UFS not yet ported), default to slot_a.
echo "husky: reading A/B slot from BCB (misc partition)..."
part number scsi ${ufs_dev} misc misc_part
if ab_select slot_suffix scsi ${ufs_dev}:${misc_part}; then
    echo "husky: BCB active slot: ${slot_suffix}"
else
    echo "husky: BCB read failed — defaulting to slot_a"
    setenv slot_suffix "_a"
fi

# Discover partition numbers for ext4load
part number scsi ${ufs_dev} userdata userdata_part
part number scsi ${ufs_dev} boot_a   boot_a_part
part number scsi ${ufs_dev} boot_b   boot_b_part

# ============================================================================
# Step 2 — Show boot menu and wait for selection
# ============================================================================
# The bootmenu command shows an interactive menu with a countdown.
# Press any key within bootmenu_delay seconds to interact.
# Press Enter (or let it time out) to boot the default (first) entry.
# The selection is stored in the bootmenu_choice env var, which we
# translate to boot_target and dispatch below.

echo ""
echo "  nhpro-native-husky — Google Pixel 8 Pro (husky)"
echo "  SoC: Tensor G3 (zuma / Samsung GS301)"
echo "  Slot: ${slot_suffix}"
echo ""

setenv bootmenu_0 "1  NetHunter Pro (Linux)     =setenv boot_target linux"
setenv bootmenu_1 "2  Android  slot_a           =setenv boot_target android-a"
setenv bootmenu_2 "3  Android  slot_b           =setenv boot_target android-b"
setenv bootmenu_3 "4  Android  GSI  (system_a)  =setenv boot_target gsi"
setenv bootmenu_4 "5  Recovery slot_a           =setenv boot_target recovery-a"
setenv bootmenu_5 "6  Recovery slot_b           =setenv boot_target recovery-b"
setenv bootmenu_6 "-- Magisk: patch android-a   =setenv boot_target magisk-a"
setenv bootmenu_7 "-- Magisk: patch android-b   =setenv boot_target magisk-b"
setenv bootmenu_8 "-- Magisk: patch GSI         =setenv boot_target magisk-gsi"
setenv bootmenu_9 "-- U-Boot shell              =setenv boot_target shell"
setenv bootmenu_delay "5"

bootmenu

# ============================================================================
# Step 3 — Dispatch to selected boot target
# ============================================================================

# ── 1. linux: NetHunter Pro ──────────────────────────────────────────────────
if test "${boot_target}" = "linux"; then
    echo "husky: booting NetHunter Pro..."
    setenv bootargs "${base_args}"
    ext4load scsi ${ufs_dev}:${userdata_part} ${loadaddr}    .linux/kernel
    ext4load scsi ${ufs_dev}:${userdata_part} ${ramdisk_addr} .linux/initrd
    booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr}
fi

# ── 2. android-a: Android slot_a ─────────────────────────────────────────────
if test "${boot_target}" = "android-a"; then
    echo "husky: booting Android slot_a..."
    setenv bootargs "${base_args} ${android_args} androidboot.slot_suffix=_a"
    ext4load scsi ${ufs_dev}:${userdata_part} ${loadaddr}    .android-a/kernel
    ext4load scsi ${ufs_dev}:${userdata_part} ${ramdisk_addr} .android-a/initrd
    booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr}
fi

# ── 3. android-b: Android slot_b ─────────────────────────────────────────────
if test "${boot_target}" = "android-b"; then
    echo "husky: booting Android slot_b..."
    setenv bootargs "${base_args} ${android_args} androidboot.slot_suffix=_b"
    ext4load scsi ${ufs_dev}:${userdata_part} ${loadaddr}    .android-b/kernel
    ext4load scsi ${ufs_dev}:${userdata_part} ${ramdisk_addr} .android-b/initrd
    booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr}
fi

# ── 4. gsi: Android Generic System Image ─────────────────────────────────────
# GSI replaces the system_a partition with a generic AOSP system image.
# The vendor_a partition and kernel stay as factory stock.
# androidboot.dynamic_partitions=true is required for GSI partition mounts.
if test "${boot_target}" = "gsi"; then
    echo "husky: booting Android GSI (system_a)..."
    setenv bootargs "${base_args} ${android_args} \
        androidboot.slot_suffix=_a \
        androidboot.dynamic_partitions=true"
    ext4load scsi ${ufs_dev}:${userdata_part} ${loadaddr}    .gsi/kernel
    ext4load scsi ${ufs_dev}:${userdata_part} ${ramdisk_addr} .gsi/initrd
    booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr}
fi

# ── 5. recovery-a: Android Recovery slot_a ───────────────────────────────────
# androidboot.mode=recovery causes Android's first-stage init to start the
# recovery binary instead of the normal system init.
if test "${boot_target}" = "recovery-a"; then
    echo "husky: booting Recovery slot_a..."
    setenv bootargs "${base_args} ${android_args} \
        androidboot.slot_suffix=_a \
        androidboot.mode=recovery"
    ext4load scsi ${ufs_dev}:${userdata_part} ${loadaddr}    .recovery-a/kernel
    ext4load scsi ${ufs_dev}:${userdata_part} ${ramdisk_addr} .recovery-a/initrd
    booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr}
fi

# ── 6. recovery-b: Android Recovery slot_b ───────────────────────────────────
if test "${boot_target}" = "recovery-b"; then
    echo "husky: booting Recovery slot_b..."
    setenv bootargs "${base_args} ${android_args} \
        androidboot.slot_suffix=_b \
        androidboot.mode=recovery"
    ext4load scsi ${ufs_dev}:${userdata_part} ${loadaddr}    .recovery-b/kernel
    ext4load scsi ${ufs_dev}:${userdata_part} ${ramdisk_addr} .recovery-b/initrd
    booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr}
fi

# ── Magisk patch mode ─────────────────────────────────────────────────────────
# U-Boot boots the Sultan kernel (.linux/kernel) with the Magisk patch-initrd
# (.magisk/patch-initrd.cpio.gz).  The patch-initrd mounts userdata, runs
# magiskboot to patch the target kernel in-place, then calls reboot.
# After reboot U-Boot shows the menu again; the patched target is ready.
#
# Prepare the patch environment with:
#   ./addons/boot-selector/scripts/patch-magisk.sh --apk Magisk.apk --push-adb

if test "${boot_target}" = "magisk-a" || \
   test "${boot_target}" = "magisk-b" || \
   test "${boot_target}" = "magisk-gsi"; then

    if test "${boot_target}" = "magisk-a";   then setenv patch_target ".android-a"; fi
    if test "${boot_target}" = "magisk-b";   then setenv patch_target ".android-b"; fi
    if test "${boot_target}" = "magisk-gsi"; then setenv patch_target ".gsi";       fi

    echo "husky: Magisk patch mode — target: ${patch_target}"
    echo "  Loading Sultan kernel + Magisk patch-initrd..."
    setenv bootargs "${base_args} patch_target=${patch_target} patch_reboot=1"
    ext4load scsi ${ufs_dev}:${userdata_part} ${loadaddr}    .linux/kernel
    ext4load scsi ${ufs_dev}:${userdata_part} ${ramdisk_addr} .magisk/patch-initrd.cpio.gz
    booti ${loadaddr} ${ramdisk_addr}:${filesize} ${dtb_addr}
fi

# ── Fallback: U-Boot interactive shell ───────────────────────────────────────
echo "husky: dropping to U-Boot shell (type 'run boot_linux' to boot)"
