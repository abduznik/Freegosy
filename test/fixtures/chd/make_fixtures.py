"""Regenerates the CHD fixtures used by chd_reader_test.dart.

Builds two tiny synthetic discs and compresses each with MAME's chdman
(https://www.mamedev.org/), so the tests check Freegosy's reader against
the reference writer:

- a PS2 DVD: a cooked ISO9660 image (2048-byte sectors) whose SYSTEM.CNF
  says `BOOT2 = cdrom0:\\SLUS_203.28;1`;
- a PS1 CD: a raw MODE2/2352 track whose SYSTEM.CNF says
  `BOOT = cdrom:\\SCES_012.37;1`.

SYSTEM.CNF sits far into each disc (sector 261, as on real discs), and some
sectors hold byte patterns so the hunks don't all compress the same way.
The source images are kept gzipped beside them. Needs chdman (tested with
0.289) on PATH or in CHDMAN; run from this directory. The discs are
synthetic, not real game data.
"""
import gzip
import os
import struct
import subprocess

CHDMAN = os.environ.get('CHDMAN', 'chdman')
SECTORS = 300
CNF_LBA = 261
ROOT_LBA = 22


def both16(v):
    return struct.pack('<H', v) + struct.pack('>H', v)


def both32(v):
    return struct.pack('<I', v) + struct.pack('>I', v)


def dir_record(name, lba, size, is_dir):
    body = struct.pack('<B', 0) + both32(lba) + both32(size) + bytes(7) + bytes([2 if is_dir else 0, 0, 0]) \
        + both16(1) + bytes([len(name)]) + name
    # The length byte counts the padding byte that keeps records even.
    pad = b'\0' if len(name) % 2 == 0 else b''
    return bytes([33 + len(name) + len(pad)]) + body + pad


def iso_sectors(cnf):
    sectors = [bytes(2048)] * SECTORS
    root = dir_record(b'\0', ROOT_LBA, 2048, True) + dir_record(b'\1', ROOT_LBA, 2048, True) \
        + dir_record(b'README.TXT;1', 40, 5, False) + dir_record(b'SYSTEM.CNF;1', CNF_LBA, len(cnf), False)
    pvd = bytearray(2048)
    pvd[0:7] = b'\x01CD001\x01'
    pvd[80:88] = both32(SECTORS)
    pvd[120:124] = both16(1)
    pvd[124:128] = both16(1)
    pvd[128:132] = both16(2048)
    pvd[156:156 + 34] = dir_record(b'\0', ROOT_LBA, 2048, True)
    sectors[16] = bytes(pvd)
    sectors[17] = b'\xffCD001\x01'.ljust(2048, b'\0')
    sectors[ROOT_LBA] = root.ljust(2048, b'\0')
    sectors[40] = b'hello'.ljust(2048, b'\0')
    seed = 12345
    for lba in range(50, 54):
        data = bytearray(2048)
        for i in range(2048):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            data[i] = (seed >> 16) & 0x3F  # compressible, but not smooth (FLAC loses)
        sectors[lba] = bytes(data)
    sectors[CNF_LBA] = cnf.ljust(2048, b'\0')
    return sectors


def bcd(v):
    return ((v // 10) << 4) | (v % 10)


ECC_LO = [((i << 1) ^ (0x11d if i & 0x80 else 0)) & 0xFF for i in range(256)]
ECC_HI = [0] * 256
for _i in range(256):
    ECC_HI[_i ^ ECC_LO[_i]] = _i


def add_ecc(sector):
    """Writes the P and Q ECC of a mode 2 form 1 sector, as libchdr's
    ecc_generate (its address bytes count as zero)."""
    data = bytearray(sector[12:])
    data[0:4] = bytes(4)

    def rows(count, comps, offset, out):
        for row in range(count):
            v1 = v2 = 0
            for comp in range(comps):
                b = data[offset(row, comp)]
                v1 = ECC_LO[v1 ^ b]
                v2 ^= b
            v1 = ECC_HI[ECC_LO[v1] ^ v2]
            data[out + row] = sector[12 + out + row] = v1
            data[out + count + row] = sector[12 + out + count + row] = v2 ^ v1

    rows(86, 24, lambda r, c: r + 86 * c, 0x81c - 12)
    rows(52, 43, lambda r, c: (86 * (r >> 1) + (r & 1) + 88 * c) % 2236, 0x81c - 12 + 172)


def raw_mode2(lba, data):
    """A MODE2 form 1 sector: sync, address, mode, subheader, data, and on
    even sectors a valid ECC, which chdman strips together with the sync
    header (the reader must put the sync header back). EDC is left zero:
    chdman doesn't check it."""
    msf = lba + 150
    header = bytes([bcd(msf // 4500), bcd(msf // 75 % 60), bcd(msf % 75), 2])
    sync = b'\x00' + b'\xff' * 10 + b'\x00'
    sector = bytearray(sync + header + bytes([0, 0, 8, 0, 0, 0, 8, 0]) + data + bytes(280))
    if lba % 2 == 0:
        add_ecc(sector)
    return bytes(sector)


def run(*args):
    subprocess.run([CHDMAN, *args, '-f'], check=True, stdout=subprocess.DEVNULL)


def main():
    dvd = iso_sectors(b'BOOT2 = cdrom0:\\SLUS_203.28;1\r\nVER = 1.00\r\nVMODE = NTSC\r\n')
    with open('dvd.iso', 'wb') as f:
        f.write(b''.join(dvd))
    for codec in ('zlib', 'lzma', 'huff', 'zstd', 'none'):
        run('createdvd', '-i', 'dvd.iso', '-o', f'ps2_dvd_{codec}.chd', '-c', codec)
    # chdman's default codecs include FLAC, which wins on smooth data: a ramp
    # in sectors 100-101 gives this disc a FLAC hunk the reader can't read,
    # away from the sectors SYSTEM.CNF is found through.
    for lba in (100, 101):
        dvd[lba] = bytes((i * 3) & 0xFF for i in range(2048))
    with open('dvd_flac.iso', 'wb') as f:
        f.write(b''.join(dvd))
    run('createdvd', '-i', 'dvd_flac.iso', '-o', 'ps2_dvd_default.chd')
    os.remove('dvd_flac.iso')

    cd = iso_sectors(b'BOOT = cdrom:\\SCES_012.37;1\r\nTCB = 4\r\nEVENT = 16\r\nSTACK = 801FFFF0\r\n')
    with open('cd.bin', 'wb') as f:
        f.write(b''.join(raw_mode2(lba, s) for lba, s in enumerate(cd)))
    with open('cd.cue', 'w') as f:
        f.write('FILE "cd.bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n')
    for codec in ('cdzl', 'cdlz', 'cdzs'):
        run('createcd', '-i', 'cd.cue', '-o', f'ps1_cd_{codec}.chd', '-c', codec)
    run('createcd', '-i', 'cd.cue', '-o', 'ps1_cd_default.chd')

    # The source images, gzipped, for comparing what the reader decodes.
    for image in ('dvd.iso', 'cd.bin'):
        with open(image, 'rb') as src, gzip.GzipFile(f'{image}.gz', 'wb', mtime=0) as dst:
            dst.write(src.read())
    for scratch in ('dvd.iso', 'cd.bin', 'cd.cue'):
        os.remove(scratch)


if __name__ == '__main__':
    main()
