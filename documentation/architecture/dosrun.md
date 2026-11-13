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
| INT 10h | 00 mode (03h text, 13h graphics), 0E teletype, 09/0A, 0F mode, 02/03 cursor, 08, 13 string; in mode 13h also 0C/0D pixels; 10h DAC (AL 10h, 12h, 15h, 17h) |
| INT 16h, 1Ah | keyboard (in graphics AH=01h does not wait) and the 18.2 Hz tick count from the kernel's timer |
| INT 20h, 29h, 11h, 12h, 15h, 2Fh, 33h | exit, fast output, equipment, memory size, small stubs |

DOS handles 0–4 are the standard devices; a file opened by the program gets
handle = native fd + 5. File names are lower-cased. An `INT 21h` function
that is not listed prints `INT 21h AH=xx is not supported` and returns CF set
with AX=1. An instruction dosrun does not know prints
`dosrun: unsupported instruction XX at CS:IP` and ends the program with exit
code 3.

Not provided yet: the FPU, video memory at B800 on the screen, the timer
interrupts, BIOS disk services, and I/O ports other than the VGA's DAC (3C8h, 3C9h)
and input status (3DAh); other ports read FFh and ignore writes.

## Graphics: VGA mode 13h

`INT 10h AX=0013h` switches the screen to 320 × 200 graphics through `SYS_GUI` (a
full-screen session, as a DOS box is on real hardware). The program's `A000:0000` is the
screen, one byte a pixel; dosrun copies it to the display when the program waits for a key,
polls the keyboard, reads the clock or the retrace bit, changes mode or ends, and at least once
a tick while it computes. The BIOS teletype (and INT 21h output) writes into `A000` with the
kernel's 5 × 7 font in 6 × 8 cells, 53 columns by 25 rows, in the colour from BL (INT 10h
AH=0Eh) or white. Port 3DAh toggles its retrace bits on every read, so wait-for-retrace loops
end.

Colours: the program has a full 256-entry DAC (default: 16 EGA colours, 16 greys and a hue
wheel made here). Entries 64–255 go to the display's own entries as they are
(`GUI_PALETTE`); entries 0–63 are shown as the nearest of the display's fixed 64 EGA colours,
because the kernel keeps those for text. Any other mode set (`AX=0003h` and the rest) goes
back to the text screen as it was; so does the program's end.

Not yet: a DOS program in a window beside others. That waits for programs to own windows
(2.2, OS2-GUI); the DOS screen is then the window's contents instead of the whole display.


## Tests

All are original, hand-written programs in `programs/`, built with
`nasm -f bin` and put on their own disk (`dos.img`) by `tools/regress.sh`.

| Program | Checks |
|---|---|
| `doshello.asm` (.COM) | INT 21h 09/02/40, the BIOS teletype, the command tail, the DOS version |
| `doscpu.asm` (.COM) | arithmetic flags, mul/div, string ops with rep, shifts, BCD, the 186 additions |
| `dosfile.asm` (.COM) | create, write, seek, read, delete a file; memory blocks; buffered input (0Ah) |
| `dosgfx.asm` (.COM) | mode 13h: A000, INT 10h pixels, DAC ports and INT 10h read-back, retrace, teletype text in graphics, back to text |
| `dosexe.asm` (.EXE) | a hand-written MZ with relocations, SS:SP from the header, a far call between segments |

Regress checks: `dos-hello`, `dos-cpu`, `dos-file`, `dos-exe`, `dos-missing`, `dos-after`.

## Starting a DOS program

`run prog.com [arguments]` and `run prog.exe [arguments]` work without naming dosrun: the
kernel loader runs `dosrun <file> <arguments>` for a headerless file named `*.com` and for an
`MZ` file without a PE header (`../kernel/loader.md`). `run winrun prog.exe` on a DOS `.EXE`
passes it on to dosrun and returns its exit code. Regress checks: `dos-run-com`,
`dos-run-exe`, `dos-winrun`, `dos-run-after`.

Not yet: DOS programs larger than 64 KB (the loader's staging limit refuses them before
dosrun sees them; `run dosrun big.exe` works up to dosrun's own limit).
