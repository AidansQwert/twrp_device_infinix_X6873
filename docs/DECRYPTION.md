# `/data` decryption on X6873 — diagnosis, not a promise

Status: **does not work.** This document records why, measured against TWRP's
own source, so the next attempt starts from facts instead of from another
device tree's flag list.

## What the image actually contains

The RECOVERY fragment built from this tree contains:

| Present | Missing |
|---|---|
| `init.recovery.mt6897.rc`, `fstab.mt6897`, `recovery.fstab` | any keymaster/KeyMint HAL binary |
| the 4 touch/haptic modules | the HAL's `.so` dependencies |
| TWRP itself, compiled with `TW_INCLUDE_CRYPTO` | the vendor HAL `.rc` that would start it |
| (from stock PLATFORM, untouched) the 241 vendor modules | the TEE / trustlet side of the stack |

`TW_INCLUDE_CRYPTO := true` builds TWRP's **client** side: `libkeymaster4support`,
`libkeymint_support`, `libtar`, `keystore2`. Every one of those is a consumer of
a keymaster/KeyMint service. Nothing in this tree *is* that service.

## Why TWRP cannot simply borrow the one in `/vendor`

`TWPartitionManager::Process_Keymaster_Version()` (partitionmanager.cpp:218-266,
identical in android-12.1 and android-14.1) resolves the HAL version like this:

1. `TWFunc::Get_Service_From_Manifest("/vendor", "android.hardware.keymaster", ver)`
   — a **HIDL** name, read from `/vendor/etc/vintf/manifest.xml`.
2. otherwise the `keymaster_ver` property.
3. otherwise a manifest inside the ramdisk.

On an Android 14 launch device the crypto HAL is normally
`android.hardware.security.keymint` (AIDL), so step 1 finds nothing. Even when a
device still ships HIDL keymaster, TWRP only *identifies* the version; it does
not start the service. In normal Android boot the HAL is started by init from
`/vendor/etc/init` during first stage, long before `/vendor` (a logical
partition inside `super`) is mounted by TWRP. Recovery never reaches that point.

Two consequences:

- Decryption needs the HAL **inside the recovery ramdisk**, so recovery's own
  init parses its `.rc` and starts it.
- Filling `/data/unencrypted` is not enough. The metadata key lives in
  `/metadata/vold/metadata_encryption` and is unwrapped by that HAL, which needs
  the TEE underneath it.

## What a working setup would have to add

Extracted from the stock firmware of *this* build, never from another device:

- the keymaster/KeyMint service binary named by the stock vendor manifest, at
  its stock path (`vendor/bin/hw/...`);
- that binary's full `DT_NEEDED` closure (`vendor/lib64`, `vendor/lib64/hw`,
  and 32-bit `vendor/lib` if it links any), including the vendor TEE client
  libraries the HAL uses — the set differs between Trustonic, Microtrust and
  other MTK stacks, so there is no universal list;
- the TEE daemon/trustlets and any key-install helper the stack requires;
- the stock service `.rc`, VINTF manifest fragment, `ueventd` rules, SELinux
  policy for the recovery domain, and property/service ordering;
- all of it placed under `recovery/root/vendor/...` so it is part of the RECOVERY
  fragment and survives the graft.

That is a blob-bundling job, not a configuration change, and it cannot be done
from this repository alone: the tree is source-only by design.

Infinix's own open-source portal
(<https://opensource.dev.infinixmobility.com/>) does not change this. For this
SoC it publishes exactly two GPL kernel tarballs —
`android15_kernel_common_mt6897.tar.gz` (217 MB) and
`android15_kernel_modules_and_devicetree_mt6897.tar.gz` (1.66 GB). Those are the
kernel, its modules and the device tree, i.e. the same material the prebuilt
kernel repository already supplies. Vendor HALs and their libraries are not
published there, and the keymaster/KeyMint stack needed above is a vendor HAL.

## The blocker that may outlive all of that

FBE keys on Android 13/14 are bound to the TEE root of trust established during
verified boot. When a different boot image runs, the TEE may refuse to release
the key no matter how complete the ramdisk is. The public MT6897 (Dimensity
8300-Ultra, same SoC family as this device) tree for Xiaomi `degas` reports
exactly this, and reports decryption as not working for that reason:
<https://github.com/Advnirr/twrp_device_xiaomi_degas>

So the honest expectation is: bundling the stock stack is worth attempting, but
success is not guaranteed on this platform.

## What was fixed here anyway

`recovery.fstab` had two flags that made the *visible* symptom worse and were
wrong regardless of whether decryption ever works:

- `length=2147483648` — TWRP uses `Length` as the authoritative size
  (`Block_Count = Length / 1024`, partition.cpp:2056-2067), so `/data` was
  reported as a 2 GiB partition.
- `wrappedkey` — claims hardware-wrapped keys, which the stock fstab does not
  use.

Both are gone; `fileencryption` now matches stock byte for byte, including
`+inlinecrypt_optimized`.

## How to confirm the diagnosis on a booted recovery

```bash
adb shell dmesg | grep -i -E 'keymaster|keymint|keystore'
adb shell getprop | grep -i -E 'keymaster|crypto'
adb shell 'ls -l /vendor/etc/vintf/manifest.xml; grep -o "android.hardware[.a-z]*key[a-z]*" /vendor/etc/vintf/manifest.xml'
```

- `keymaster_ver` empty plus no HIDL `android.hardware.keymaster` entry
  confirms step 1 of the version discovery fails.
- `Unable to decrypt metadata encryption` in the TWRP log is the metadata key
  never being unwrapped — the HAL is missing, not the flags.
