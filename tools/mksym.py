#!/usr/bin/env python3
"""Make a debugger symbol file from a NASM map file (A.4).

Usage: mksym.py PROGRAM.map PROGRAM.sym
Build the program with a map:  nasm -f bin --before '[map symbols PROGRAM.map]' ...
The .sym file has one "XXXXXXXX name" line per label of the program's
sections (the "Real / Virtual / Name" tables), sorted by address; the
debugger loads it as <program>.sym (documentation/apps/debugger.md).
Original code.
"""
import sys


def symbols(text):
    out, in_section = [], False
    for line in text.splitlines():
        if line.startswith('---- Section'):
            in_section = True
            continue
        if line.startswith('----') or line.startswith('-- '):
            in_section = False
            continue
        parts = line.split()
        if not in_section or len(parts) != 3 or parts[0] == 'Real':
            continue
        try:
            addr = int(parts[1], 16)
        except ValueError:
            continue
        name = parts[2]
        if name.startswith('sqx_') or name.startswith('..'):
            continue
        out.append((addr, name[:27]))
    return sorted(set(out))


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    syms = symbols(open(sys.argv[1], encoding='latin-1').read())
    with open(sys.argv[2], 'w', newline='\n') as f:
        for addr, name in syms:
            f.write('%08X %s\n' % (addr, name))


if __name__ == '__main__':
    main()
