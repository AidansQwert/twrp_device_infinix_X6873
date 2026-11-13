#
# Copyright (C) 2026 The Android Open Source Project
# Copyright (C) 2026 TWRP device tree for Infinix GT 30 Pro (X6873)
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/infinix/X6873

# ============================================================================
# BRICK-SAFETY NOTES — read before changing anything here
#
# Every value below was measured from the device's own stock images.
# Re-verified against XOS 16.3.0.150 (vendor_boot of 2026-09-03, kernel
# 6.1.157-android14-11-g96f885be21ae): header, load addresses, cmdline, fstab
# and partition sizes are unchanged from 16.2.0.145SP03; only the DTB and the
# kernel module set moved, and both are handled below.
# Earlier community X6873 recovery trees
# bootlooped because of the specific mistakes called out in the comments.
# Do not "tidy" these values.
# ============================================================================

# For building with a minimal manifest
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_MISSING_REQUIRED_MODULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_PREBUILT_ELF_FILES := true

# ---------------------------------------------------------------- platform
TARGET_BOARD_PLATFORM := mt6897
TARGET_BOOTLOADER_BOARD_NAME := x6873_h972
TARGET_NO_BOOTLOADER := true
BOARD_HAS_MTK_HARDWARE := true
BOARD_USES_MTK_HARDWARE := true

# ------------------------------------------------------------ architecture
# 64-bit only: stock ro.product.cpu.abilist32 is empty and zygote is zygote64.
# A 32-bit second arch here produces a recovery that tries to load 32-bit
# binaries the device cannot run.
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a76
TARGET_USES_64_BIT_BINDER := true

# ------------------------------------------------------------------ kernel
# GKI 2.0: boot.img holds ONLY the kernel (ramdisk_size = 0). TWRP must not
# try to build or repack a kernel.
TARGET_NO_KERNEL := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_RAMDISK_USE_LZ4 := true
BOARD_KERNEL_SEPARATED_DTBO := true

BOARD_BOOT_HEADER_VERSION := 4
BOARD_KERNEL_PAGESIZE := 4096
# Stock vendor_boot header_size is 2128. BOARD_HEADER_SIZE is not read by the
# AOSP/TWRP build system (verified: no reference in core/Makefile or
# board_config.mk) — mkbootimg derives it from --header_version. Recorded here
# as measured documentation only.
# BOARD_HEADER_SIZE := 2128

# Load addresses.
#
# The stock vendor_boot v4 header stores ABSOLUTE addresses:
#     kernel  0x40000000
#     ramdisk 0x66f00000
#     tags    0x47c80000
#     dtb     0x47c80000
#
# base + offset must reproduce those exactly:
#     0x3fff8000 + 0x00008000 = 0x40000000   kernel
#     0x3fff8000 + 0x26f08000 = 0x66f00000   ramdisk
#     0x3fff8000 + 0x07c88000 = 0x47c80000   tags / dtb
#
# ROOT CAUSE OF THE KNOWN BOOTLOOP: hoshiyomiX/infinix_X6873-TWRP uses
# base 0x40078000 with ramdisk_offset 0x11088000, which resolves to kernel
# 0x40080000 and ramdisk 0x51100000. The ramdisk lands 0x15e00000 below where
# the bootloader expects it, so the kernel finds no ramdisk and reboots.
BOARD_KERNEL_BASE := 0x3fff8000
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x26f08000
BOARD_KERNEL_TAGS_OFFSET := 0x07c88000
BOARD_TAGS_OFFSET := $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_DTB_OFFSET := 0x07c88000

# Stock vendor_boot cmdline, verbatim. Nothing appended.
# In particular NOT androidboot.selinux=permissive: on this device the stock
# vendor policy is loaded from the ramdisk, and forcing permissive changes
# first-stage init behaviour instead of fixing anything.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2
# BOARD_VENDOR_CMDLINE is not an AOSP/TWRP build variable (verified: no
# reference in core/Makefile or board_config.mk). The vendor_boot cmdline comes
# from BOARD_KERNEL_CMDLINE via INTERNAL_KERNEL_CMDLINE, so setting it would be
# dead config. Not set.

# DTB: the stock MT6897 DTB of XOS 16.3.0.150 (401194 bytes, sha256
# 4ff99438…a347), byte-identical, taken from that firmware's vendor_boot.
# It differs from the 16.2 DTB (401220 bytes) — same board, updated nodes.
# It carries the MediaTek DT wrapper header (magic 1eabb7d7) the bootloader
# expects — do not strip it, and do not substitute a DTB from another device.
# BOARD_INCLUDE_DTB_IN_BOOTIMG defines the $(PRODUCT_OUT)/dtb.img target, but
# only BOARD_PREBUILT_DTBIMAGE_DIR supplies a RULE to build it (core/Makefile
# concatenates $(BOARD_PREBUILT_DTBIMAGE_DIR)/*.dtb). Setting the former
# without the latter is what produced run #5's
#   ninja: 'out/target/product/X6873/dtb.img' ... missing and no known rule
# BOARD_PREBUILT_DTBIMAGE (singular) is not an AOSP variable at all.
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/dtb
BOARD_INCLUDE_DTB_IN_BOOTIMG := true

# NOTE ON CMDLINE DUPLICATION
# INTERNAL_VENDOR_BOOTIMAGE_ARGS already passes
#   --vendor_cmdline "$(INTERNAL_KERNEL_CMDLINE)"
# where INTERNAL_KERNEL_CMDLINE = BOARD_KERNEL_CMDLINE + " buildvariant=eng"
# (core/Makefile:909, board_config.mk:229). We deliberately do NOT add another
# --vendor_cmdline: mkbootimg would take the last one and we would lose the
# build-system value. The extra "buildvariant=eng" token differs from stock but
# is harmless — the bootloader only consumes bootopt=, and stock TWRP trees
# carry the same token.
BOARD_MKBOOTIMG_ARGS += --base $(BOARD_KERNEL_BASE)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --board ""

# -------------------------------------------------------------- partitions
BOARD_FLASH_BLOCK_SIZE := 262144
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_SUPER_PARTITION_GROUPS := infinix_dynamic_partitions
BOARD_INFINIX_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext vendor product odm
BOARD_USES_METADATA_PARTITION := true

TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs

# ===========================================================================
# ROOT CAUSE FIX FOR RUN #7 — the rsync "root/vendor" collision
#
# Run #7 reached 20263/20265 and failed with:
#     could not make way for new symlink: root/vendor
#     cannot delete non-empty directory: root/vendor
#
# Without this variable, envsetup.mk leaves TARGET_COPY_OUT_VENDOR as a
# placeholder that board_config.mk:561 resolves to "system/vendor". The
# baseline ramdisk then contains root/vendor as a SYMLINK to /system/vendor.
# Anything installing into vendor/ inside the recovery ramdisk (the
# android.hardware.boot@1.1.xml / @1.2.xml VINTF fragments that
# AB_OTA_UPDATER := true pulls in via TWRP_REQUIRED_MODULES, plus any
# .recovery HAL) turns recovery/root/vendor into a real non-empty directory,
# and the recovery packaging rsync cannot overwrite a non-empty directory with
# a symlink -> exit 23.
#
# This device HAS a real vendor partition, so "vendor" is also the correct
# value. board_config.mk:577 then sets BOARD_USES_VENDORIMAGE := true, which is
# harmless here: BUILDING_VENDOR_IMAGE additionally requires
# BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE, which is deliberately not set, so no
# vendor.img is built.
#
# This is exactly what the booting duchamp TWRP tree does (it sets
# TARGET_COPY_OUT_VENDOR := vendor and therefore never hits this collision,
# even while installing the same boot/health HALs).
# ===========================================================================
TARGET_COPY_OUT_VENDOR := vendor

# ---------------------------------------------------------------- recovery
# There is NO dedicated recovery partition. Recovery lives in vendor_boot as
# the RECOVERY ramdisk fragment, which is what stock does.
TARGET_NO_RECOVERY := true
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true

# Leave this EMPTY. The stock fstab requests
# avb_keys=/avb/{q,r,s}-gsi.avbpubkey, and moving GSI keys into vendor_boot on
# a device whose vbmeta we are not resigning causes first_stage_mount to fail
# verification and reboot.
BOARD_MOVE_GSI_AVB_KEYS_TO_VENDOR_BOOT :=

TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab
# recovery.fstab is unchanged for 16.3: the stock fstab.emmc^ (recovery variant)
# in the 16.3 vendor_boot lists the same partitions and the same FBE scheme as
# 16.2, including protect2 and the metadata-encrypted userdata.

# Stock recovery graphics format. RGBX_8888 (used by every earlier X6873 tree)
# gives swapped red/blue channels on this panel.
TARGET_RECOVERY_PIXEL_FORMAT := BGRA_8888

# --------------------------------------------------------------------- AVB
# Recovery is not a separate partition here, so there is no recovery vbmeta
# to sign. Earlier trees set BOARD_AVB_RECOVERY_* with rollback index
# location 1 — the same location the real vbmeta_system chain uses on this
# device. Writing a descriptor there is what turns a bootloop into a
# verification failure that needs fastboot to recover.
#
# We do not resign or regenerate any vbmeta. Only vendor_boot is flashed, and
# the device must be unlocked (its stock vbmeta then does not gate boot).
BOARD_AVB_ENABLE := false

# ---------------------------------------------------------------- versions
# PLATFORM_VERSION 99.87.36 with PLATFORM_SECURITY_PATCH 2099-12-31 is a TWRP
# convention to defeat the anti-rollback check. It is kept, but note it also
# makes PLATFORM_SECURITY_PATCH_TIMESTAMP enormous — which is exactly why
# using that value as an AVB rollback index (as earlier trees did) is
# dangerous. With AVB disabled above, it is inert.
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)

# ----------------------------------------------------------------- display
# Panel: vtdr6126a, 1224x2720, DSI video mode, up to 144 Hz, density 480.
# Earlier trees declared 1080x2400 / 120 Hz, which is a different panel.
TARGET_SCREEN_WIDTH := 1224
TARGET_SCREEN_HEIGHT := 2720
TARGET_SCREEN_DENSITY := 480

TW_THEME := portrait_hdpi
TW_FRAMERATE := 60
TW_NO_SCREEN_BLANK := true
# Backlight. Verified against the stock module set: leds-mtk.ko exports the
# node name "lcd-backlight" and contains both "max_brightness" and the literal
# 2047, so the range is 0-2047. Every MediaTek reference tree checked uses the
# same path.
# Confirmed on the device: /sys/class/leds/lcd-backlight exists and
# max_brightness reports 5119, so the slider must scale to that. TWRP assumes
# 255 by default, which would clamp the panel to the bottom 5% of its range.
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 5119
TW_MAX_BRIGHTNESS := 2047
TW_DEFAULT_BRIGHTNESS := 1200

# --------------------------------------------------------------------- USB
# Stock recovery init sets exactly these two properties.
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_USB_STORAGE := true

# --------------------------------------------------------------- crypto
# FBE with metadata encryption, aes-256-xts:aes-256-cts:v2, F2FS userdata.
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_LIBRESETPROP := true
TW_INCLUDE_RESETPROP := true
# TW_INCLUDE_FBE_METADATA_DECRYPT is NOT set: TWRP's Android.mk adds
# -DTW_INCLUDE_FBE_METADATA_DECRYPT unconditionally inside the
# TW_INCLUDE_CRYPTO block (android-12.1 Android.mk:358), so setting it here
# would be dead config.
#
# CORRECTION to an earlier comment in this file: TW_USE_FSCRYPT_POLICY does
# have a consumer. libtar/Android.mk:59 is the only one, and the only value
# that changes behaviour is 1 (-DUSE_FSCRYPT_POLICY_V1, legacy policy v1).
# Every other value, including leaving it unset, compiles -DUSE_FSCRYPT_POLICY_V2.
# This device's fstab declares ...aes-256-cts:v2, i.e. policy v2, so 2 is the
# correct value. It is set explicitly below so the choice is visible instead of
# being an implicit default.
TW_USE_FSCRYPT_POLICY := 2

# WHY /data STILL DOES NOT DECRYPT
#
# TW_INCLUDE_CRYPTO builds TWRP's crypto client code. It does not supply the
# keymaster/KeyMint implementation that actually unwraps the metadata key, and
# this ramdisk ships none: recovery/root contains only init.recovery, the fstab
# and kernel modules. TWRP's version discovery is also HIDL-specific --
# partitionmanager.cpp:221 calls
#     TWFunc::Get_Service_From_Manifest("/vendor", "android.hardware.keymaster", ver)
# and falls back only to the keymaster_ver property or a ramdisk manifest, so a
# device that exposes AIDL android.hardware.security.keymint has nothing for it to
# find. See docs/DECRYPTION.md for the diagnosis and what a working setup needs.

# ------------------------------------------------------------------- misc
TW_INCLUDE_FASTBOOTD := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_NTFS_3G := true
TW_EXTRA_LANGUAGES := true
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
# Not set, no consumer found in TWRP 12.1 source (verified against
# bootable/recovery/Android.mk and the soong EXPORT_TO_SOONG list):
#   TW_HAS_NO_RECOVERY_PARTITION, TW_HAS_NO_SELECT_BUTTON, TW_USB_STORAGE,
#   BOARD_SUPPRESS_SECURE_ERASE
# They are inert rather than harmful, but dead config hides real problems.

# lptools can resize and delete logical partitions from the GUI. On a device
# whose super layout we have not fully verified, that is a data-loss risk.
TW_EXCLUDE_LPTOOLS := true
TW_EXCLUDE_APEX := true

# ---------------------------------------------------------------- modules
# No kernel modules are shipped in the RECOVERY fragment.
#
# The graft keeps the stock PLATFORM fragment, and that fragment already carries
# the firmware's own module set — 244 .ko on XOS 16.3.0.150, all reporting
# vermagic 6.1.157-android14-11-g96f885be21ae — together with its modules.load
# (182) and modules.load.recovery (237). First-stage init loads them at recovery
# boot, so TWRP gets exactly the modules that match the running kernel.
#
# Copying modules in again is what breaks a firmware bump: the 16.2 prebuilt set
# is vermagic 6.1.145, and a 6.1.157 kernel refuses to load it
# ("version magic … should be 6.1.157…"), which leaves recovery without display
# or input modules.
#
# Run #6 failed partly because nothing populated the vendor ramdisk:
#   error: cannot open directory 'out/target/product/X6873/vendor_ramdisk'
# With BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT plus
# BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT, the PLATFORM fragment must be
# populated explicitly or it ships empty -- which is exactly the defect in the
# idabgsram, XTENSEI and naden X6873 trees. This wiring follows
# transsion-graveyard's Tecno CM6 tree.
# BOARD_VENDOR_RAMDISK_KERNEL_MODULES and $(DEVICE_PATH)-kernel are deliberately
# NOT used: whatever they install lands in the PLATFORM fragment, which the graft
# replaces with the stock one, and 28 MB of modules next to a 28 MB stock
# fragment plus TWRP would not fit in the 64 MiB partition anyway. The r10
# artifact proved the first point: its RECOVERY fragment held 0 .ko files.

# TWRP module loading.
#
# TW_LOAD_VENDOR_BOOT_MODULES is NESTED inside "ifneq ($(TW_LOAD_VENDOR_MODULES),)"
# in bootable/recovery/Android.mk:323-334, so the loader is only compiled when at
# least one module is named here.
#
# Everything the running kernel needs at boot already comes from the stock
# PLATFORM fragment, so the only names worth listing are the four odm_dlkm ones
# below. TWRP insmods them itself once the ramdisk is up, because first-stage
# init cannot see them (they are not in vendor_boot). The .ko files have to be
# dropped into recovery/root/lib/modules/ from the matching firmware; if that
# directory is empty the loader logs four failures and recovery still boots.
#
# Touch and haptics are the one remaining gap, and they are not in vendor_boot on
# any X6873 firmware: focaltech_ft3683g.ko, adaptive-ts.ko, haptic_drv_hv.ko and
# aw86224_light.ko live in odm_dlkm and are only mounted after super comes up.
# Recovery therefore boots and works with a dead digitiser until they are taken
# from the *matching* odm_dlkm.img (16.3.0.150). Do not reuse the 16.2 copies:
# their vermagic is 6.1.145 and the 16.3 kernel rejects them.
#
# Touch firmware is deliberately NOT shipped. Our driver is the flash-resident
# SPI variant (focaltech_ft3683g.ko, built from .../focaltech/ft3683g_spi/), and
# its firmware requests exist only for FW upgrade and factory-test INI paths.
# Placing a firmware file where a flash-resident FTS driver can find it risks an
# auto-upgrade on probe, and flashing touch firmware from recovery can brick the
# digitizer.

# Order matters: TWRP insmods this list front to back and does not retry.
#   tran-led-core      <- aw86224_light
#   adaptive-ts        <- focaltech_ft3683g
#
# adaptive-ts only needs tnek / transsion_tranlog / mtk_disp_notify, all of which
# first-stage init already loads from the stock PLATFORM fragment. Its modinfo
# also names opsMediator, but that is a stale modpost entry: on XOS 16.3.0.150
# there is no opsMediator module, no /sys/module/opsMediator and no such symbol
# in /proc/kallsyms, yet adaptive_ts loads fine on the stock system (refcount 1
# from focaltech_ft3683g). insmod resolves symbols, not depends=, so nothing
# else has to be shipped.
TW_LOAD_VENDOR_MODULES := "tran-led-core.ko adaptive-ts.ko focaltech_ft3683g.ko aw86224_light.ko haptic_drv_hv.ko"
TW_LOAD_VENDOR_BOOT_MODULES := true

# Bumped so the artifact identifies the firmware it targets.
TW_DEVICE_VERSION := X6873-brick-safe-2-xos16.3
