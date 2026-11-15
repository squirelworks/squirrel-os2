#!/usr/bin/env python3
"""Klingon-font branch: rewrite tools/font5x7.txt and tools/fontp{9,12}.txt
letters, digits, apostrophe and digraphs (0x80-0x83) as pIqaD from
tools/klingon-font.py, keeping punctuation from the Latin designs. Then
rebuild kernel/font.inc and kernel/fontp.inc.

Without the prop-face pass, VBE window chrome (FONT_9 / FONT_12) kept Latin
letterforms while VGA text and 5x7 gfx already showed pIqaD — and digraph
codes 0x80-0x83 indexed past the old 0x20-0x7E prop tables (e.g. "ghunmey"
drew as "unmey").

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


def prop_rows(rows12, height):
    """7x12 pIqaD art -> seven columns, `height` rows for a prop face.

    Use floor(i * 12 / height) so a single mid-row stroke (digit 0) is not
    skipped the way round(i * 11 / (height-1)) can skip source row 5.
    """
    if height == 12:
        return list(rows12)
    row_i = [min(11, (i * 12) // height) for i in range(height)]
    return [rows12[ri] for ri in row_i]


def latin_base_5x7():
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


def latin_base_prop(name, height):
    """Existing punctuation (and any prior glyphs) from a prop face source."""
    path = os.path.join(ROOT, 'tools', name + '.txt')
    glyphs = {}
    with open(path, encoding='ascii') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            code, *rows = line.split()
            code = int(code, 16)
            if 0x20 <= code <= 0x7E and len(rows) == height:
                glyphs[code] = rows
    return glyphs


def apply_klingon(glyphs, row_fn, blank):
    """Overwrite letters, digits, apostrophe and digraphs via row_fn(art)->rows."""
    for d, art in kf.DIGITS.items():
        glyphs[ord(d)] = row_fn(art_rows(art))
    glyphs[ord("'")] = row_fn(art_rows(kf.KLINGON["'"]))
    for latin, kl in kf.LATIN.items():
        rows = row_fn(art_rows(kf.KLINGON[kl]))
        glyphs[ord(latin)] = rows
        glyphs[ord(latin.upper())] = rows
    glyphs[ord('q')] = row_fn(art_rows(kf.KLINGON['q']))
    glyphs[ord('Q')] = row_fn(art_rows(kf.KLINGON['Q']))
    for cp in (kf.KL_CH, kf.KL_GH, kf.KL_NG, kf.KL_TLH):
        glyphs[cp] = row_fn(art_rows(kf.KLINGON[cp]))
    glyphs[0x7F] = blank


def uniquify(glyphs, first, last, nudges):
    """Nudge a pixel on duplicate bitmaps so OCR can tell codes apart."""
    seen = {}
    for c in range(first, last + 1):
        if c not in glyphs:
            continue
        key = tuple(glyphs[c])
        if key not in seen:
            seen[key] = c
            continue
        rows = [list(r) for r in glyphs[c]]
        width = len(rows[0])
        height = len(rows)
        for ri, ci in nudges:
            if ri >= height or ci >= width:
                continue
            rows[ri][ci] = '#' if rows[ri][ci] == '.' else '.'
            new = tuple(''.join(r) for r in rows)
            if new not in seen:
                glyphs[c] = [''.join(r) for r in rows]
                seen[new] = c
                break
        else:
            sys.exit('could not uniquify glyph %02x' % c)


def write_5x7():
    glyphs = latin_base_5x7()
    apply_klingon(glyphs, downsample, ['.....'] * 7)
    # Digit 0 is a mid bar in pIqaD; 5x7 downsample collides with '-'.
    if glyphs[ord('0')] == glyphs.get(ord('-')):
        glyphs[ord('0')] = ['.....', '.....', '#####', '#####', '.....', '.....', '.....']
    uniquify(glyphs, mkfont.FIRST, mkfont.LAST,
             ((6, 4), (6, 0), (0, 4), (0, 0), (3, 2), (5, 3), (1, 1)))
    missing = [c for c in range(mkfont.FIRST, mkfont.LAST + 1) if c not in glyphs]
    if missing:
        sys.exit('5x7 missing glyphs: %s' % ', '.join('%02x' % c for c in missing))
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
    print('wrote %s (%d glyphs)' % (SRC, mkfont.LAST - mkfont.FIRST + 1))


def write_prop(name, height):
    path = os.path.join(ROOT, 'tools', name + '.txt')
    glyphs = latin_base_prop(name, height)
    blank = ['.' * 7] * height
    apply_klingon(glyphs, lambda rows12: prop_rows(rows12, height), blank)
    # Mid-bar digit 0: empty after resample, or colliding with Latin '-'.
    zero, hyphen = glyphs[ord('0')], glyphs.get(ord('-'))
    if (not any('#' in r for r in zero) or
            (hyphen is not None and zero == hyphen)):
        bar = '#' * 7
        mid = height // 2
        glyphs[ord('0')] = (
            ['.' * 7] * mid + [bar, bar] + ['.' * 7] * (height - mid - 2))
    # Do not uniquify space or the blank filler — keep them ink-free.
    hold = {0x20: glyphs[0x20], 0x7F: list(blank)}
    uniquify(glyphs, mkfont.PROP_FIRST, mkfont.PROP_LAST,
             ((height - 1, 6), (height - 1, 0), (0, 6), (0, 0),
              (height // 2, 3), (height - 2, 5), (1, 1), (2, 2)))
    glyphs.update(hold)
    missing = [c for c in range(mkfont.PROP_FIRST, mkfont.PROP_LAST + 1)
               if c not in glyphs]
    if missing:
        sys.exit('%s missing glyphs: %s' % (name, ', '.join('%02x' % c for c in missing)))
    if name == 'fontp9':
        role = 'window face: title bars, menus, widgets'
    else:
        role = 'display face, bold'
    header = [
        '# Squirrel-OS/2 proportional font, %d pixels high (%s; Klingon/pIqaD joke branch).'
        % (height, role),
        '# Letters, digits, apostrophe and digraphs 80-83 are pIqaD from',
        '# tools/klingon-font.py; punctuation keeps the Latin design.',
        '# One glyph per line: the character\'s code in hex, then its rows, top first;',
        '# every row of a glyph is as wide as the glyph (\'#\' ink, \'.\' background).',
        '# tools/mkfont.py turns this file into kernel/fontp.inc.',
        '# Regenerate with: python3 tools/mkklingon5x7.py',
    ]
    lines = header + ['%02x %s' % (c, ' '.join(glyphs[c]))
                      for c in range(mkfont.PROP_FIRST, mkfont.PROP_LAST + 1)]
    with open(path, 'w', encoding='ascii') as f:
        f.write('\n'.join(lines) + '\n')
    print('wrote %s (%d glyphs)' % (path, mkfont.PROP_LAST - mkfont.PROP_FIRST + 1))


def main():
    write_5x7()
    for const, name, height in mkfont.FACES:
        write_prop(name, height)
    with open(mkfont.OUT, 'w', encoding='ascii') as f:
        f.write(mkfont.render(mkfont.read()))
    with open(mkfont.OUTP, 'w', encoding='ascii') as f:
        f.write(mkfont.render_p())
    print('rebuilt kernel/font.inc and kernel/fontp.inc')


if __name__ == '__main__':
    main()
