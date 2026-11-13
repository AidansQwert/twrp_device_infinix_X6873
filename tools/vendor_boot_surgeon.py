#!/usr/bin/env python3
"""
vendor_boot fragment surgeon for Infinix X6873 (MediaTek MT6897).

WHY THIS EXISTS
---------------
Stock vendor_boot.img on this device carries TWO vendor ramdisk fragments:

    index 0   type PLATFORM   ~29.2 MB   the NORMAL BOOT vendor ramdisk
                                         (241 kernel modules, fstab,
                                          first-stage tools)
    index 1   type RECOVERY    ~3.1 MB   recovery resources only

A recovery build (TWRP, OrangeFox, or AOSP recovery) produces a vendor_boot.img
that contains only its own single ramdisk. Flashing that image replaces the
whole partition and therefore DELETES fragment 0. The device then has no vendor
kernel modules, cannot mount super, and bootloops -- and because recovery lived
in the same partition, there is nothing left on the device to repair it with.

That is the failure mode reported on the 145 and 150 firmware builds.

WHAT THIS DOES
--------------
Rebuilds vendor_boot.img from the STOCK image, keeping fragment 0 and the DTB
byte-identical, and replacing ONLY the RECOVERY fragment with the freshly built
recovery ramdisk. The header, cmdline, load addresses, page size and name field
are copied from stock unchanged.

USAGE
-----
    # inspect
    vendor_boot_surgeon.py info   stock_vendor_boot.img

    # extract a fragment
    vendor_boot_surgeon.py unpack stock_vendor_boot.img outdir/

    # swap in a new recovery ramdisk
    vendor_boot_surgeon.py graft  stock_vendor_boot.img \
                                  new_recovery_ramdisk.lz4 \
                                  out_vendor_boot.img

    # prove the tool is lossless (must report IDENTICAL)
    vendor_boot_surgeon.py selftest stock_vendor_boot.img

SPDX-License-Identifier: Apache-2.0
"""

import hashlib
import os
import struct
import sys

MAGIC = b'VNDRBOOT'
ARGS_SIZE = 2048
NAME_SIZE = 16
TABLE_ENTRY_NAME_SIZE = 32
TABLE_ENTRY_BOARD_ID_WORDS = 16
# AOSP vendor_ramdisk_table_entry_v4 ramdisk_type values
# (system/tools/mkbootimg/include/bootimg/bootimg.h)
TYPE_NAMES = {0: 'NONE', 1: 'PLATFORM', 2: 'RECOVERY', 3: 'DLKM'}
TYPE_RECOVERY = 2

# AVB
AVB_FOOTER_MAGIC = b'AVBf'
AVB_FOOTER_SIZE = 64


def pad_to(n, page):
    """Round n up to a multiple of page."""
    r = n % page
    return n if r == 0 else n + (page - r)


class VendorBoot:
    def __init__(self, blob):
        if blob[:8] != MAGIC:
            raise ValueError('not a vendor_boot image (bad magic)')
        self.blob = blob

        # ---- header (vendor_boot_img_hdr_v4) -----------------------------
        off = 8
        (self.header_version, self.page_size, self.kernel_addr,
         self.ramdisk_addr, self.vendor_ramdisk_size) = struct.unpack_from('<5I', blob, off)
        off += 20

        self.cmdline = blob[off:off + ARGS_SIZE]
        off += ARGS_SIZE

        (self.tags_addr,) = struct.unpack_from('<I', blob, off)
        off += 4

        self.name = blob[off:off + NAME_SIZE]
        off += NAME_SIZE

        (self.header_size, self.dtb_size) = struct.unpack_from('<2I', blob, off)
        off += 8
        (self.dtb_addr,) = struct.unpack_from('<Q', blob, off)
        off += 8

        if self.header_version < 4:
            raise ValueError(
                'header version %d: this device is v4; refusing to guess'
                % self.header_version)

        (self.table_size, self.table_entry_num,
         self.table_entry_size, self.bootconfig_size) = struct.unpack_from('<4I', blob, off)
        off += 16

        # ---- section offsets (each section is page aligned) --------------
        p = self.page_size
        self.off_ramdisk = pad_to(self.header_size, p)
        self.off_dtb = self.off_ramdisk + pad_to(self.vendor_ramdisk_size, p)
        self.off_table = self.off_dtb + pad_to(self.dtb_size, p)
        self.off_bootconfig = self.off_table + pad_to(self.table_size, p)

        self.ramdisk_blob = blob[self.off_ramdisk:self.off_ramdisk + self.vendor_ramdisk_size]
        self.dtb = blob[self.off_dtb:self.off_dtb + self.dtb_size]
        self.bootconfig = blob[self.off_bootconfig:self.off_bootconfig + self.bootconfig_size]

        # ---- fragment table ---------------------------------------------
        self.fragments = []
        for i in range(self.table_entry_num):
            eo = self.off_table + i * self.table_entry_size
            size, offset, rtype = struct.unpack_from('<3I', blob, eo)
            raw_name = blob[eo + 12:eo + 12 + TABLE_ENTRY_NAME_SIZE]
            board_id = blob[eo + 12 + TABLE_ENTRY_NAME_SIZE:
                            eo + 12 + TABLE_ENTRY_NAME_SIZE + 4 * TABLE_ENTRY_BOARD_ID_WORDS]
            self.fragments.append({
                'index': i,
                'size': size,
                'offset': offset,
                'type': rtype,
                'type_name': TYPE_NAMES.get(rtype, 'UNKNOWN(%d)' % rtype),
                'name': raw_name.rstrip(b'\0').decode('utf-8', 'replace'),
                'raw_name': raw_name,
                'board_id': board_id,
                'data': self.ramdisk_blob[offset:offset + size],
            })

    # ---------------------------------------------------------------- info
    def describe(self):
        out = []
        a = out.append
        a('header_version        : %d' % self.header_version)
        a('page_size             : %d' % self.page_size)
        a('kernel_addr           : 0x%08x' % self.kernel_addr)
        a('ramdisk_addr          : 0x%08x' % self.ramdisk_addr)
        a('tags_addr             : 0x%08x' % self.tags_addr)
        a('dtb_addr              : 0x%08x' % self.dtb_addr)
        a('header_size           : %d' % self.header_size)
        a('vendor_ramdisk_size   : %d' % self.vendor_ramdisk_size)
        a('dtb_size              : %d' % self.dtb_size)
        a('bootconfig_size       : %d' % self.bootconfig_size)
        a('name                  : %r' % self.name.rstrip(b'\0'))
        a('cmdline               : %r' % self.cmdline.rstrip(b'\0').decode('utf-8', 'replace'))
        a('fragments             : %d' % self.table_entry_num)
        for f in self.fragments:
            a('  [%d] %-9s name=%-10r size=%-10d offset=%d'
              % (f['index'], f['type_name'], f['name'], f['size'], f['offset']))
        return '\n'.join(out)

    # -------------------------------------------------------------- build
    def build(self, fragments):
        """Reassemble the image from a fragment list, preserving everything else."""
        p = self.page_size

        # Concatenate fragment payloads in table order, recomputing offsets.
        parts, offset = [], 0
        for f in fragments:
            f['offset'] = offset
            f['size'] = len(f['data'])
            parts.append(f['data'])
            offset += f['size']
        ramdisk_blob = b''.join(parts)

        # Fragment table
        table = bytearray()
        for f in fragments:
            table += struct.pack('<3I', f['size'], f['offset'], f['type'])
            table += f['raw_name'].ljust(TABLE_ENTRY_NAME_SIZE, b'\0')[:TABLE_ENTRY_NAME_SIZE]
            table += f['board_id'].ljust(4 * TABLE_ENTRY_BOARD_ID_WORDS, b'\0')
            # pad entry out to the stock entry size, in case it is larger
            pad = self.table_entry_size - (12 + TABLE_ENTRY_NAME_SIZE +
                                           4 * TABLE_ENTRY_BOARD_ID_WORDS)
            if pad < 0:
                raise ValueError('table_entry_size smaller than a v4 entry')
            table += b'\0' * pad
        table = bytes(table)

        # Header: every field copied from stock except the two sizes that
        # necessarily change.
        hdr = bytearray()
        hdr += MAGIC
        hdr += struct.pack('<5I', self.header_version, self.page_size,
                           self.kernel_addr, self.ramdisk_addr, len(ramdisk_blob))
        hdr += self.cmdline.ljust(ARGS_SIZE, b'\0')[:ARGS_SIZE]
        hdr += struct.pack('<I', self.tags_addr)
        hdr += self.name.ljust(NAME_SIZE, b'\0')[:NAME_SIZE]
        hdr += struct.pack('<2I', self.header_size, self.dtb_size)
        hdr += struct.pack('<Q', self.dtb_addr)
        hdr += struct.pack('<4I', len(table), len(fragments),
                           self.table_entry_size, self.bootconfig_size)

        if len(hdr) > self.header_size:
            raise ValueError('header overflow: %d > %d' % (len(hdr), self.header_size))
        hdr = bytes(hdr).ljust(pad_to(self.header_size, p), b'\0')

        img = bytearray()
        img += hdr
        img += ramdisk_blob.ljust(pad_to(len(ramdisk_blob), p), b'\0')
        img += self.dtb.ljust(pad_to(self.dtb_size, p), b'\0')
        img += table.ljust(pad_to(len(table), p), b'\0')
        if self.bootconfig_size:
            img += self.bootconfig.ljust(pad_to(self.bootconfig_size, p), b'\0')
        return bytes(img)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def cmd_info(argv):
    vb = VendorBoot(read(argv[0]))
    print(vb.describe())
    return 0


def cmd_unpack(argv):
    src, outdir = argv[0], argv[1]
    vb = VendorBoot(read(src))
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, 'dtb'), 'wb') as f:
        f.write(vb.dtb)
    for fr in vb.fragments:
        name = 'vendor_ramdisk_%02d_%s' % (fr['index'], fr['type_name'].lower())
        with open(os.path.join(outdir, name), 'wb') as f:
            f.write(fr['data'])
        print('%-34s %10d  %s' % (name, fr['size'], sha(fr['data'])[:16]))
    if vb.bootconfig:
        with open(os.path.join(outdir, 'bootconfig'), 'wb') as f:
            f.write(vb.bootconfig)
    print('dtb                                %10d  %s' % (len(vb.dtb), sha(vb.dtb)[:16]))
    return 0


def cmd_graft(argv):
    # optional flags
    pad = True
    partition_size = None
    args = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--no-pad':
            pad = False
        elif a == '--partition-size':
            i += 1
            partition_size = int(argv[i], 0)
        else:
            args.append(a)
        i += 1
    if len(args) < 3:
        print('usage: graft [--no-pad] [--partition-size N] STOCK NEW_RAMDISK OUT',
              file=sys.stderr)
        return 1
    stock, new_recovery, dest = args[0], args[1], args[2]
    vb = VendorBoot(read(stock))
    new = read(new_recovery)

    targets = [f for f in vb.fragments if f['type'] == TYPE_RECOVERY]
    if len(targets) != 1:
        print('ERROR: expected exactly one RECOVERY fragment, found %d.' % len(targets),
              file=sys.stderr)
        print('Refusing to guess -- inspect with "info" first.', file=sys.stderr)
        return 2

    platform = [f for f in vb.fragments if f['type'] != TYPE_RECOVERY]
    if not platform:
        print('ERROR: stock image has no non-recovery fragment. This is not the',
              file=sys.stderr)
        print('expected X6873 layout; grafting would produce an unbootable image.',
              file=sys.stderr)
        return 2

    tgt = targets[0]
    print('stock RECOVERY fragment : %d bytes  %s' % (tgt['size'], sha(tgt['data'])[:16]))
    print('new   recovery ramdisk  : %d bytes  %s' % (len(new), sha(new)[:16]))
    for f in platform:
        print('preserved %-9s     : %d bytes  %s'
              % (f['type_name'], f['size'], sha(f['data'])[:16]))
    print('preserved DTB           : %d bytes  %s' % (len(vb.dtb), sha(vb.dtb)[:16]))

    # ---- safety gate: a recovery fragment with no touch driver ------------
    # The graft replaces the PLATFORM fragment with stock, so any module the
    # build placed in PLATFORM is discarded. If the incoming recovery fragment
    # carries no touch driver, the resulting recovery would boot with a working
    # display and a dead touchscreen. On a device with no button combo to reach
    # fastboot, that is a serious operational hazard, so warn loudly.
    lower = new[:4 * 1024 * 1024]
    hints = (b'focaltech', b'adaptive-ts', b'goodix', b'himax', b'novatek')
    if not any(h in new for h in hints):
        print()
        print('WARNING: the new recovery ramdisk contains no recognisable touch')
        print('         driver. Recovery may boot with a dead touchscreen.')
        print('         Stage the modules into recovery/root/lib/modules/ so')
        print('         they land in the RECOVERY fragment (see BoardConfig.mk).')
        print()

    tgt['data'] = new
    img = vb.build(vb.fragments)

    # The partition is 64 MiB. Refuse to emit something that cannot be flashed.
    # Checked before padding, so an oversized payload is caught on its own merit.
    limit = 67108864
    if len(img) > limit:
        print('ERROR: result is %d bytes, larger than the %d byte vendor_boot '
              'partition.' % (len(img), limit), file=sys.stderr)
        print('Shrink the recovery ramdisk (TW_EXCLUDE_* options) and retry.',
              file=sys.stderr)
        return 3

    # ---- pad to the full partition size -----------------------------------
    # Stock vendor_boot.img as dumped is exactly the partition size (64 MiB):
    # a raw partition read, zero padded, with a 64-byte AVB footer in the last
    # block. Device trees that set BOARD_AVB_ENABLE := true get the same result
    # from "avbtool add_hash_footer --partition_size", which pads the file out
    # to that size. That is the only reason other devices' recovery images are
    # exactly 64 MiB -- it is padding, not content.
    #
    # Padding matters for a real reason, not cosmetics: fastboot writes only as
    # many bytes as the image contains, so flashing a short image leaves the
    # tail of the previous partition content in place -- including the stock
    # AVB footer and its vbmeta block. Padding guarantees the whole partition
    # is overwritten and no stale metadata survives.
    if pad:
        target = partition_size if partition_size else len(read(stock))
        if target < len(img):
            print('ERROR: padding target %d is smaller than the image (%d).'
                  % (target, len(img)), file=sys.stderr)
            return 3
        pad_bytes = target - len(img)
        img = img + b'\x00' * pad_bytes
        print('padded  %d -> %d bytes (+%d zero bytes) to match the partition'
              % (target - pad_bytes, target, pad_bytes))

    with open(dest, 'wb') as f:
        f.write(img)

    # Verify what we just wrote, rather than trusting the writer.
    chk = VendorBoot(read(dest))
    ok = True
    if chk.table_entry_num != vb.table_entry_num:
        print('VERIFY FAIL: fragment count changed', file=sys.stderr); ok = False
    if chk.dtb != vb.dtb:
        print('VERIFY FAIL: DTB changed', file=sys.stderr); ok = False
    for a, b in zip(sorted(platform, key=lambda x: x['index']),
                    sorted([f for f in chk.fragments if f['type'] != TYPE_RECOVERY],
                           key=lambda x: x['index'])):
        if a['data'] != b['data']:
            print('VERIFY FAIL: %s fragment changed' % a['type_name'], file=sys.stderr)
            ok = False
    rec = [f for f in chk.fragments if f['type'] == TYPE_RECOVERY]
    if len(rec) != 1 or rec[0]['data'] != new:
        print('VERIFY FAIL: recovery fragment not written correctly', file=sys.stderr)
        ok = False
    for field in ('kernel_addr', 'ramdisk_addr', 'tags_addr', 'dtb_addr',
                  'page_size', 'header_size', 'cmdline', 'name'):
        if getattr(chk, field) != getattr(vb, field):
            print('VERIFY FAIL: header field %s changed' % field, file=sys.stderr)
            ok = False
    if not ok:
        return 4

    print()
    print('wrote %s (%d bytes, %.1f%% of the 64 MiB partition)'
          % (dest, len(img), 100.0 * len(img) / limit))
    print()
    print('AVB: no footer is written, deliberately. The stock root vbmeta.img')
    print('     carries a DIRECT HASH descriptor for vendor_boot')
    print('     (image_size + sha256 digest), so libavb hashes the partition')
    print('     itself and never consults a footer. Any modification therefore')
    print('     fails verification regardless of what footer is present, which')
    print('     is why this device needs:')
    print('       fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img')
    print('     Do not re-lock the bootloader while this image is installed.')
    print('VERIFIED: PLATFORM fragment, DTB and all header fields are unchanged.')
    return 0


def describe_tail(orig, n):
    """Classify whatever the stock image has after the payload.

    Stock images are padded out to the full 64 MiB partition and carry an AVB
    footer in the last 64 bytes, plus the vbmeta block it points at. That is
    expected, not corruption.
    """
    tail = orig[n:]
    if not tail:
        return 'nothing', True
    footer = orig[-AVB_FOOTER_SIZE:]
    if footer[:4] == AVB_FOOTER_MAGIC:
        # AvbFooter: magic[4] version_major[4] version_minor[4]
        #            original_image_size[8] vbmeta_offset[8] vbmeta_size[8]
        orig_size, vb_off, vb_size = struct.unpack_from('>QQQ', footer, 12)
        if orig_size != n:
            return ('AVB footer says payload is %d bytes but the parsed payload '
                    'is %d' % (orig_size, n)), False
        gap = orig[n:vb_off]
        after = orig[vb_off + vb_size:len(orig) - AVB_FOOTER_SIZE]
        if set(gap) <= {0} and set(after) <= {0}:
            return ('AVB footer, %d byte vbmeta at offset %d, rest zero padding'
                    % (vb_size, vb_off)), True
        return 'AVB footer present but unexpected non-zero data as well', False
    if set(tail) <= {0}:
        return 'all zero padding', True
    return 'NON-ZERO DATA (unexpected)', False


def cmd_selftest(argv):
    """Repack the stock image with no changes; the payload must be identical."""
    src = argv[0]
    orig = read(src)
    vb = VendorBoot(orig)
    rebuilt = vb.build(vb.fragments)

    n = len(rebuilt)
    same = rebuilt == orig[:n]
    tail_desc, tail_ok = describe_tail(orig, n)

    print('stock size    : %d' % len(orig))
    print('rebuilt size  : %d' % n)
    print('payload match : %s' % ('IDENTICAL' if same else 'DIFFERENT'))
    print('stock tail    : %s' % tail_desc)
    print()
    print('fragment types:')
    for f in vb.fragments:
        print('  [%d] type=%d %-9s name=%r' % (f['index'], f['type'], f['type_name'], f['name']))

    if not same:
        for i in range(min(n, len(orig))):
            if rebuilt[i] != orig[i]:
                print('first difference at offset %d (0x%x)' % (i, i), file=sys.stderr)
                break
        return 1
    if not tail_ok:
        print('WARNING: %s' % tail_desc, file=sys.stderr)
        return 1

    # Sanity: the layout this tool depends on must actually be present.
    kinds = sorted(f['type_name'] for f in vb.fragments)
    if kinds != ['PLATFORM', 'RECOVERY']:
        print('WARNING: expected exactly PLATFORM + RECOVERY fragments, got %s'
              % kinds, file=sys.stderr)
        return 1

    print()
    print('SELFTEST PASSED: repacking is lossless and the fragment layout is')
    print('the expected PLATFORM + RECOVERY pair.')
    return 0


COMMANDS = {
    'info': (cmd_info, 1, 'IMAGE'),
    'unpack': (cmd_unpack, 2, 'IMAGE OUTDIR'),
    'graft': (cmd_graft, 3, 'STOCK_IMAGE NEW_RECOVERY_RAMDISK OUT_IMAGE'),
    'selftest': (cmd_selftest, 1, 'IMAGE'),
}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        print(__doc__.strip())
        return 1
    fn, nargs, usage = COMMANDS[argv[0]]
    rest = argv[1:]
    if len(rest) < nargs:
        print('usage: %s %s %s' % (os.path.basename(sys.argv[0]), argv[0], usage),
              file=sys.stderr)
        return 1
    return fn(rest)


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except ValueError as e:
        # Bad magic / wrong header version. Show the size and the first bytes so
        # a downloaded error page is obvious instead of a bare traceback.
        path = sys.argv[2] if len(sys.argv) > 2 else None
        if path and os.path.isfile(path):
            with open(path, 'rb') as f:
                head = f.read(16)
            print('input file  : %s (%d bytes)' % (path, os.path.getsize(path)),
                  file=sys.stderr)
            print('first bytes : %r' % head, file=sys.stderr)
            if head[:5] in (b'<!doc', b'<html'):
                print('The URL returned an HTML page, not an image. Use the raw '
                      'file URL (raw.githubusercontent.com/...).', file=sys.stderr)
        print('ERROR: %s' % e, file=sys.stderr)
        sys.exit(1)
