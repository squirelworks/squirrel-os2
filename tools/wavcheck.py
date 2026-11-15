#!/usr/bin/env python3
"""Checks what QEMU's wav audio backend wrote: a tone of the expected pitch.

QEMU writes 44100 Hz 16-bit stereo, and when the regression kills it the
header's sizes stay 0 and the last few KB may be missing, so the file is
read raw after its 44-byte header. Passes when at least MIN_SECONDS of
the left channel are louder than 1/64 of full scale, and the zero
crossings of that part give FREQ within 5%.

Usage: tools/wavcheck.py FILE FREQ MIN_SECONDS   (prints "ok ..." or "FAIL ...")
Original code.
"""
import struct
import sys

path, freq, need = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
try:
    raw = open(path, 'rb').read()[44:]
except OSError as exc:
    print('FAIL no file:', exc)
    sys.exit(1)
raw = raw[:len(raw) // 4 * 4]
left = struct.unpack('<%dh' % (len(raw) // 2), raw)[::2]
rate = 44100
loud = [i for i, v in enumerate(left) if abs(v) > 512]
if not loud:
    print('FAIL silence')
    sys.exit(1)
seconds = len(loud) / rate
part = left[loud[0]:loud[-1] + 1]
crossings = sum(1 for a, b in zip(part, part[1:]) if (a < 0) != (b < 0))
got = crossings / 2 / (len(part) / rate)
ok = seconds >= need and abs(got - freq) <= freq * 0.05
print('%s %.0f Hz for %.2f s' % ('ok' if ok else 'FAIL', got, seconds))
sys.exit(0 if ok else 1)
