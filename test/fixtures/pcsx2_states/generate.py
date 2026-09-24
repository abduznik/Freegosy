"""Regenerates the PCSX2 save-state mockups used by the state sync tests.

Run from this folder: python3 generate.py
"""
import random
import zipfile

rng = random.Random(1234)


def blob(n):
    return bytes(rng.randrange(256) for _ in range(n))


def write_state(path, seed_tag):
    # Same layout as a real PCSX2 state: a zip of named memory/register dumps.
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('PCSX2 Savestate Version.id', b'\x00\x00\x9a\x00')
        z.writestr('Internal Structures.bin', seed_tag + blob(1024))
        z.writestr('eeMemory.bin', seed_tag + blob(2048))
        z.writestr('iopMemory.bin', seed_tag + blob(1024))
        z.writestr('vuMemory.bin', seed_tag + blob(512))


write_state('valid.p2s', b'A')
write_state('valid_other.p2s', b'B')

good = open('valid.p2s', 'rb').read()
# A write cut off halfway: still starts with the zip header, but the
# zip's end record (central directory) is missing.
open('truncated.p2s', 'wb').write(good[: len(good) // 2])
# A preallocated file that was never filled in (power loss, full disk).
open('zeroed.p2s', 'wb').write(bytes(len(good)))
# Not a state at all.
open('garbage.p2s', 'wb').write(b'this is not a PCSX2 save state\n' * 10)
