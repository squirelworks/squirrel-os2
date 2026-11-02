#!/usr/bin/env python3
"""Klingon-font branch: rewrite tools/font5x7.txt letters, digits, apostrophe
and digraphs (0x80-0x83) as downsampled pIqaD from tools/klingon-font.py,
keeping punctuation from the Latin 5x7 design. Then rebuild kernel/font.inc.

  python3 tools/mkklingon5x7.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import importlib.util
import mkfont

_spec = importlib.util.spec_from_file_location(
    'klingon_font', os.path.join(ROOT, 'tools', 'klingon-font.py'))
kf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kf)

SRC = os.path.join(ROOT, 'tools', 'font5x7.txt')


def art_rows(art):
    rows = art.strip('\n').split('\n')
    assert len(rows) == 12 and all(len(r) == 7 for r in rows), rows
    return rows


def downsample(rows12):
    """7x12 pIqaD art -> five columns, seven rows for font5x7."""
    row_i = [min(11, round(i * 10 / 6)) for i in range(7)]
    col_i = [0, 1, 3, 5, 6]
    return [''.join(rows12[ri][c] for c in col_i) for ri in row_i]


def latin_base():
    """Existing 0x20-0x7E glyphs (punctuation kept from these)."""
    glyphs = {}
    with open(SRC, encoding='ascii') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            code, *rows = line.split()
            code = int(code, 16)
            if 0x20 <= code <= 0x7E and len(rows) == 7:
                glyphs[code] = rows
    return glyphs


def main():
    glyphs = latin_base()
    for d, art in kf.DIGITS.items():
        glyphs[ord(d)] = downsample(art_rows(art))
    # Digit 0 is a mid bar in pIqaD; 5x7 downsample collides with '-'.
    # Keep a two-row bar so OCR (and eyes) can tell them apart.
    if glyphs[ord('0')] == glyphs.get(ord('-')):
        glyphs[ord('0')] = ['.....', '.....', '#####', '#####', '.....', '.....', '.....']
    glyphs[ord("'")] = downsample(art_rows(kf.KLINGON["'"]))
    for latin, kl in kf.LATIN.items():
        rows = downsample(art_rows(kf.KLINGON[kl]))
        glyphs[ord(latin)] = rows
        glyphs[ord(latin.upper())] = rows
    glyphs[ord('q')] = downsample(art_rows(kf.KLINGON['q']))
    glyphs[ord('Q')] = downsample(art_rows(kf.KLINGON['Q']))
    for cp in (kf.KL_CH, kf.KL_GH, kf.KL_NG, kf.KL_TLH):
        glyphs[cp] = downsample(art_rows(kf.KLINGON[cp]))
    glyphs[0x7F] = ['.....'] * 7

    # VGA text aliases several Latin letters to one pIqaD shape. In 5x7 that
    # makes OCR (qemu_screen gfx_text / regress) unable to read English UI.
    # Nudge a corner pixel on duplicates so each code stays unique while the
    # letterform still reads as pIqaD.
    seen = {}
    for c in range(mkfont.FIRST, mkfont.LAST + 1):
        if c not in glyphs:
            continue
        key = tuple(glyphs[c])
        if key not in seen:
            seen[key] = c
            continue
        rows = [list(r) for r in glyphs[c]]
        for ri, ci in ((6, 4), (6, 0), (0, 4), (0, 0), (3, 2), (5, 3), (1, 1)):
            rows[ri][ci] = '#' if rows[ri][ci] == '.' else '.'
            new = tuple(''.join(r) for r in rows)
            if new not in seen:
                glyphs[c] = [''.join(r) for r in rows]
                seen[new] = c
                break
        else:
            sys.exit('could not uniquify glyph %02x' % c)

    missing = [c for c in range(mkfont.FIRST, mkfont.LAST + 1) if c not in glyphs]
    if missing:
        sys.exit('missing glyphs: %s' % ', '.join('%02x' % c for c in missing))

    header = [
        '# Squirrel-OS/2 graphics font, 5 x 7 - Klingon/pIqaD joke branch.',
        '# Letters, digits, apostrophe and digraphs 80-83 are downsampled',
        '# from tools/klingon-font.py; punctuation keeps the Latin design.',
        '# tools/mkfont.py turns this file into kernel/font.inc.',
        '# Regenerate with: python3 tools/mkklingon5x7.py',
    ]
    lines = header + ['%02x %s' % (c, ' '.join(glyphs[c]))
                      for c in range(mkfont.FIRST, mkfont.LAST + 1)]
    with open(SRC, 'w', encoding='ascii') as f:
        f.write('\n'.join(lines) + '\n')
    text = mkfont.render(mkfont.read())
    with open(mkfont.OUT, 'w', encoding='ascii') as f:
        f.write(text)
    print('wrote %s (%d glyphs) and rebuilt kernel/font.inc' % (
        SRC, mkfont.LAST - mkfont.FIRST + 1))


if __name__ == '__main__':
    main()
