# TWRP device tree — Infinix GT 30 Pro (X6873)

TWRP recovery for the **Infinix GT 30 Pro (X6873)**, MediaTek **MT6897**
(Dimensity 8350 Ultimate). Built by GitHub Actions.

**The flashable output is `vendor_boot.img`, not `recovery.img`.** This device
has no recovery partition — recovery lives inside `vendor_boot` as a ramdisk
fragment, exactly as stock does.

---

## Read this before flashing anything

Earlier community X6873 recovery builds bootlooped devices. I traced four
distinct causes. Three are configuration mistakes; one is architectural and is
the reason this repository exists.

### 1. The architectural one — why a plain recovery build bricks this device

Stock `vendor_boot.img` contains **two** vendor ramdisk fragments:

| Fragment | Type | Size | Purpose |
|---|---|---|---|
| 0 | `PLATFORM` | 29,216,972 | **normal Android boot** — all 241 vendor kernel modules, fstab, first-stage tools |
| 1 | `RECOVERY` | 3,118,179 | recovery resources only |

A TWRP/OrangeFox build emits a `vendor_boot.img` containing **only its own
ramdisk**. Flashing that replaces the whole partition and deletes fragment 0.
The device then has no vendor kernel modules, cannot mount `super`, and
bootloops — and because recovery lived in the same partition that was just
overwritten, there is nothing left on the device to repair it with.

This repository therefore never flashes a freshly built `vendor_boot.img`.
The workflow builds the recovery ramdisk, then **grafts** it into the *stock*
image as the RECOVERY fragment, leaving the PLATFORM fragment, the DTB and
every header field byte-identical. See
[`tools/vendor_boot_surgeon.py`](tools/vendor_boot_surgeon.py), which verifies
its own output and refuses to write an image if anything else changed.

The build also emits `vendor_boot-RAW-DO-NOT-FLASH.img`. That is the
single-fragment image. The name is the warning.

### 2. Wrong load addresses

The stock v4 header stores absolute addresses. `base + offset` must reproduce
them exactly:

| Field | base + offset | Result | Stock |
|---|---|---|---|
| kernel | `0x3fff8000 + 0x00008000` | `0x40000000` | `0x40000000` |
| ramdisk | `0x3fff8000 + 0x26f08000` | `0x66f00000` | `0x66f00000` |
| tags / dtb | `0x3fff8000 + 0x07c88000` | `0x47c80000` | `0x47c80000` |

`hoshiyomiX/infinix_X6873-TWRP` uses base `0x40078000` with ramdisk offset
`0x11088000`, giving kernel `0x40080000` and ramdisk `0x51100000` — the ramdisk
lands `0x15e00000` away from where the bootloader puts it, so the kernel finds
no ramdisk and reboots. Any tree derived from it inherits the bug.

These corrected values are independently confirmed by the Xiaomi `duchamp`
(POCO X6 Pro) TWRP tree, a different device on the same MT6897 SoC that boots.

### 3. AVB rollback index — the irreversible one

Earlier trees combine `PLATFORM_SECURITY_PATCH := 2099-12-31` with

```makefile
BOARD_AVB_RECOVERY_ROLLBACK_INDEX          := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1
```

That writes an enormous rollback index at location 1 — the same location this
device's real `vbmeta_system` chain uses. Rollback indices are stored in
tamper-evident storage and **only ever increase**. Once a large value is
committed, stock firmware with a normal index is rejected permanently. That is
a brick fastboot cannot undo.

This tree sets `BOARD_AVB_ENABLE := false`. No vbmeta is generated, signed or
flashed. `PLATFORM_SECURITY_PATCH` keeps the TWRP convention value but it is
inert because no AVB descriptor is produced.

**Never flash a vbmeta image from a recovery build. Never re-lock the
bootloader while a grafted vendor_boot is installed.**

### 4. Display and touch

| Item | Earlier trees | Actual X6873 |
|---|---|---|
| Panel | 1080 x 2400 | **1224 x 2720** (`vtdr6126a`) |
| Refresh | 120 Hz | 144 Hz |
| Pixel format | `RGBX_8888` | **`BGRA_8888`** |

Wrong stride or channel order gives a black or torn screen that is
indistinguishable from a failed boot.

Touch needed a separate fix: the stock PLATFORM ramdisk has **no touch
driver**, because at normal boot touch comes from `odm_dlkm` after `super` is
mounted. Four modules are added to the RECOVERY fragment
(`focaltech_ft3683g.ko`, `adaptive-ts.ko`, `haptic_drv_hv.ko`,
`aw86224_light.ko`), all reporting vermagic
`6.1.145-android14-11-gbd2a8237408e` — the same kernel build as the stock
modules. Because the RECOVERY fragment is overlaid on PLATFORM at recovery
boot, normal boot is unaffected.

---

## Verified device facts

Measured from this device's own stock images, not inherited from another tree.

| Item | Value |
|---|---|
| SoC | MT6897, DTB `model = MT6897` |
| Kernel | 6.1.145-android14-11, GKI 2.0, KMI 11 (`mgk_64_k61`) |
| boot.img | header v4, **kernel only**, `ramdisk_size = 0` |
| init_boot.img | generic ramdisk |
| vendor_boot.img | header v4, `header_size` 2128, 2 fragments, DTB 401220 B |
| cmdline | `bootopt=64S3,32N2,64N2` |
| Recovery graphics | `BGRA_8888` |
| Userdata | F2FS, FBE `aes-256-xts:aes-256-cts:v2` + metadata encryption |
| Update | Virtual A/B with compression |

The 145SP03 and 150SP12 firmware builds ship the **same kernel binary**
(sha256 `185c25f8…c961`), the same 241-module set, identical `modules.load`
(179) / `modules.load.recovery` (234) and an identical DTB. Firmware version
skew is therefore not a cause of the earlier failures.

## Brick-safety choices in `recovery.fstab`

`bootloader`, `preloader`, `lk`, `seccfg`, `efuse`, `proinfo` and `para` are
deliberately **absent**. A mis-tap on "Install image" targeting the preloader
is how MediaTek devices become unreachable by fastboot. What TWRP does not
list, it cannot offer. `TW_EXCLUDE_LPTOOLS := true` for the same reason.

## Building

Actions → **Build TWRP vendor_boot (X6873)** → Run workflow.

Artifacts:

| File | Use |
|---|---|
| `vendor_boot-twrp-X6873.img` | **flash this** |
| `vendor_boot-RAW-DO-NOT-FLASH.img` | the single-fragment build output, kept for inspection only |
| `SHA256SUMS.txt` | hashes |

## Flashing

Requires an unlocked bootloader.

```bash
# 1. Back up the stock image first. Do not skip this.
adb reboot bootloader
fastboot getvar current-slot

# 2. Flash recovery
fastboot flash vendor_boot vendor_boot-twrp-X6873.img

# 3. Boot to recovery
fastboot reboot recovery
```

### Why this device needs vbmeta verification disabled

Some Infinix/Tecno devices accept a modified `vendor_boot` without touching
vbmeta; this one does not, and that is not a guess. Parsing the stock
`vbmeta.img` (12288 bytes, libavb 1.0, `SHA256_RSA2048`, `rollback_index=5`,
header `flags=0` meaning verification enabled) gives:

```
[1]  CHAIN partition="boot"           rollback_index_location=3
[2]  CHAIN partition="vbmeta_system"  rollback_index_location=2
[3]  CHAIN partition="vbmeta_vendor"  rollback_index_location=4
[41] HASH  partition="dtbo"        image_size=233824
[42] HASH  partition="init_boot"   image_size=3121152
[43] HASH  partition="vendor_boot" image_size=32489472  sha256  digest=faa2eef6...
```

`vendor_boot` has a **direct HASH descriptor in the root vbmeta**. libavb hashes
the partition contents and compares against that digest, so any modification
fails — and the footer inside the partition is irrelevant, which is why adding
an AVB footer to a custom image does not help. Devices that boot custom
recovery without touching vbmeta are ones whose vendor_boot has no descriptor,
or whose bootloader skips AVB entirely when unlocked.

So the required sequence is:

```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot flash vendor_boot vendor_boot-twrp-X6873.img
fastboot reboot recovery
```

Use the `vbmeta.img` from firmware matching your installed build. Flashing
vbmeta with those flags only clears the verification flags; it does **not**
change the rollback index, so it is reversible by reflashing stock vbmeta.

### Why the image is exactly 64 MiB

The grafted image is padded to the full 67108864-byte partition size. Other
devices' recovery images are 64 MiB because they set `BOARD_AVB_ENABLE := true`,
and `avbtool add_hash_footer --partition_size` pads the output to that size —
the size comes from padding, not content.

This matters beyond cosmetics: `fastboot` writes only as many bytes as the image
contains. A short image would leave the tail of the previous partition in place,
including the **stock AVB footer and its vbmeta block**, so the partition would
end up carrying stale verification metadata. Padding guarantees the whole
partition is overwritten.

To restore stock:

```bash
fastboot flash vendor_boot stock_vendor_boot.img
```

Because the graft preserves the PLATFORM fragment, a normal reboot still boots
Android even if recovery itself misbehaves. That is the point of the design:
the failure mode is "recovery does not work", not "phone does not boot".

If the device does not reach recovery, reflash the stock `vendor_boot.img` and
report the symptom. Do not flash vbmeta, boot, or any firmware partition
trying to fix it.

## Honest status

This tree has not yet been booted on hardware. Every value in it is verified
against stock, and the graft tool is verified to be lossless, but "verified
configuration" is not the same as "known to boot". First-boot risks that remain:

- `/data` decryption is **not working**. TWRP carries a keymaster/KeyMint
  *client*, but this ramdisk ships no HAL to talk to, and TWRP's version
  discovery asks for the HIDL name `android.hardware.keymaster`
  (`partitionmanager.cpp:221`) which an AIDL KeyMint device does not publish.
  `docs/DECRYPTION.md` has the full diagnosis, what a working setup needs, and
  the TEE root-of-trust caveat that may block it on this SoC anyway.
- TWRP 12.1 may not mount stock EROFS `system`/`vendor` for backups
- `TW_BRIGHTNESS_PATH` is unconfirmed on this panel
- the fingerprint input device has no `.idc`, so TWRP may log unknown input events

None of these can bootloop the device, because normal boot does not use the
RECOVERY fragment.

## Credits

- `bootctrl/` and `mtk_plpath_utils/` come from
  [idabgsram/recovery-device_infinix_Infinix-X6873](https://github.com/idabgsram/recovery-device_infinix_Infinix-X6873)
  (Apache-2.0, `NOTICE` preserved).
- Load-address convention cross-checked against
  [ramabondanp/twrp-android_device_xiaomi_duchamp](https://github.com/ramabondanp/twrp-android_device_xiaomi_duchamp).
- Earlier X6873 trees by
  [hoshiyomiX](https://github.com/hoshiyomiX/infinix_X6873-TWRP),
  [XTENSEI](https://github.com/XTENSEI/twrp_device_infinix_X6873),
  [idabgsram](https://github.com/idabgsram/recovery-device_infinix_Infinix-X6873),
  [naden01](https://github.com/naden01/android_device_infinix_X6873) — used to
  identify what to verify, and what they got wrong.
- Stock firmware reference:
  [rama-firmware-dumps X6873](https://gitlab.com/rama-firmware-dumps/Infinix/Infinix-X6873).

## License

Apache-2.0. See `LICENSE` and `bootctrl/NOTICE`.
