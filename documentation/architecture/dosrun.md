# dosrun: DOS programs on Squirrel-OS/2 (P.8)

`dosrun` runs real-mode DOS programs as an ordinary Squirrel-OS/2 program:

    run dosrun prog.com [arguments]
    run dosrun prog.exe [arguments]     (MZ without a PE header)

## Why an interpreter and not V86

The P.8 design (`dos-personality.md`) prefers a V86 monitor. V86 needs the
first megabyte of the process's address space, and the kernel's low image
(0x8000, 96 KB) still lives there after 2.4. Until the low image moves,
dosrun interprets the 8086 instead. The design keeps an interpreter for long
mode anyway (no V86 in 64-bit mode), so this code is not thrown away.

## What it is

- An 8086 interpreter with the common 80186 additions (`push imm`, `imul`
  three-operand, `pusha`/`popa`, shifts by an immediate, `enter`/`leave`)
  and the 386 near conditional jump `0F 80..8F`, which assemblers
  emit for conditional jumps further than 128 bytes.
- Arithmetic runs on the host CPU and the flags are carried over, so the
  flags are exactly the 8086's.
- DOS memory is 1 MB + 64 KB of the program's heap. The PSP is at segment
  0x1000. A `.COM` image is at 1000:0100 with SP=FFFE. An `.EXE` image is at
  1010:0000, relocated, with CS:IP and SS:SP from the header.
- The interrupt vectors start out pointing at F000:n*4, where dosrun serves
  them. A program may hook a vector (`INT 21h AH=25h`) and chain to the old one.

## Services

| Interrupt | Functions |
|---|---|
| INT 21h | 00 01 02 06 07 08 09 0A 0B 0C 0D 0E 19 1A 25 2A 2C 2F 30 33 35 3C 3D 3E 3F 40 41 42 43 44 47 48 49 4A 4C 4E/4F 51 56 62 |
| INT 10h | 0E teletype, 09/0A, 0F mode, 03 cursor, 08, 13 string |
| INT 16h, 1Ah | keyboard and clock |
| INT 20h, 29h, 11h, 12h, 15h, 2Fh, 33h | exit, fast output, equipment, memory size, small stubs |

DOS handles 0–4 are the standard devices; a file opened by the program gets
handle = native fd + 5. File names are lower-cased. An `INT 21h` function
that is not listed prints `INT 21h AH=xx is not supported` and returns CF set
with AX=1. An instruction dosrun does not know prints
`dosrun: unsupported instruction XX at CS:IP` and ends the program with exit
code 3.

Not provided yet: the FPU, video memory at B800 on the screen, the timer
interrupts, BIOS disk services, and I/O ports (IN reads FFh, OUT is ignored).

## Tests

All are original, hand-written programs in `programs/`, built with
`nasm -f bin` and put on their own disk (`dos.img`) by `tools/regress.sh`.

| Program | Checks |
|---|---|
| `doshello.asm` (.COM) | INT 21h 09/02/40, the BIOS teletype, the command tail, the DOS version |
| `doscpu.asm` (.COM) | arithmetic flags, mul/div, string ops with rep, shifts, BCD, the 186 additions |
| `dosfile.asm` (.COM) | create, write, seek, read, delete a file; memory blocks; buffered input (0Ah) |
| `dosexe.asm` (.EXE) | a hand-written MZ with relocations, SS:SP from the header, a far call between segments |

Regress checks: `dos-hello`, `dos-cpu`, `dos-file`, `dos-exe`, `dos-missing`, `dos-after`.

## Next

The kernel loader hands `.com` files to dosrun by name, and `winrun` passes
an MZ file without a PE header on to dosrun, so `run prog.com` works without
naming dosrun. Both wait for the Win32 loader work to reach main.
