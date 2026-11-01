# Squirrel-OS/2 Specifications

Current capabilities and intentional limitations.  
Updated with each release. The newest section is last; older sections are kept as history. What comes next is in [`../ROADMAP.md`](../ROADMAP.md).

## 0.0.2 — Capabilities

- Boots from a 512-byte sector after firmware hand-off
- Sets text video mode and writes `UwU` directly to VGA text memory (`0xB8000`)
- Owns periodic timing via PIT channel 0 (~100 Hz) and a native IRQ0 handler
- Drives the PC speaker for short beeps
- Produces a beep approximately every 15 seconds with light jitter
- Runs in 16-bit real mode

## 0.0.2 — Intentional Limitations

| Item | Description |
|------|-------------|
| Real mode only | No memory protection or protected-mode features yet |
| Boot-sector size | Entire image must fit in 512 bytes |
| Firmware video init | Uses `int 0x10` once to set mode 3; display writes are direct thereafter |
| Timing precision | Beep interval is approximate by design at this stage |
| Jitter | Simple free-running seed; not a high-quality random source |
| Tick width | 16-bit counter (wraps after ~10.9 min at 100 Hz) |
| Hardware dependency | Speaker and PIT behavior follow classic PC / emulator expectations |
| No input | Keyboard is not read |
| No storage | No file system or block device |
| No processes | Single control loop |

## 0.0.3 — Capabilities

- Boot sector loads a second stage
- Enters 32-bit protected mode with its own GDT
- Writes `UwU` from protected mode
- Produces a single beep
- Stack set in protected mode

## 0.0.3 — Intentional Limitations

| Item | Description |
|------|-------------|
| No IDT yet | Interrupts are not handled in protected mode |
| Single beep | Periodic timer from 0.0.2 not yet restored |
| Firmware disk load | Second stage is read via `int 0x13` |
| Firmware video init | Mode set still uses `int 0x10` |
| No input / storage / processes | Unchanged |

## 0.9.3 — Capabilities

The system that 1.0.0 will tag. Each line names where it is described and, where one exists, a `tools/regress.sh` check.

**Boot and hardware**

- Boots from a hard-disk image or a 1.44 MB floppy image with a BIOS (not UEFI). The boot sector uses extended disk reads and falls back to CHS reads (`kernel/boot-sector.md`; `floppy-boot`).
- Stage 2 checks for CPUID, an FPU and 4 MB pages, then reads the BIOS memory map (E820) and enters 32-bit protected mode with its own GDT and IDT.
- PIT at 100 Hz, PS/2 keyboard through IRQ 1, VGA text mode 80 × 25, PC speaker.
- Banner `Squirrel-OS/2 0.9.3` and the list of applications (`ver-banner`, `ver-planned`).

**Memory** (`kernel/memory.md`, `kernel/memory-map.md`)

- Page allocator over usable RAM between 1 MB and 256 MB (`mem`, `memtest`).
- Paging: the first 4 MB identity-mapped, and a separate address space per loaded program for its 64 KB at `0x30000`.
- `SYS_SBRK` moves the end of a program's heap (`heap`).

**Processes and system calls** (`kernel/processes.md`, `kernel/syscalls.md`)

- Up to 8 process slots, scheduled cooperatively and round-robin. A process runs until it yields, waits or exits. `ps` lists them (`proctest`).
- 25 system calls (0–24) through `int 0x80` (`systest`).
- A fault in a program prints a crash report (exception name, registers, decoded page fault, stack, process name) and ends only that program. The shell can be restarted after its own fault (`kernel/crash-reports.md`).

**Devices** (`kernel/drivers.md`, `kernel/block-device.md`)

- Driver table with devices found by name: `con`, `kbd`, `hd0` (boot disk, read-only), `hd1` (data disk). `devices` lists them.
- ATA PIO on the primary channel (`blktest`).

**File system** (`kernel/filesystem.md`)

- SQFS on the data disk (ATA primary slave): 64 entries in all (files and directories together), names up to 15 characters, paths up to 63 characters, one contiguous extent per file that moves when it grows.
- Directories: `mkdir`, `cd`, `pwd`, and `mv` between directories. Up to 8 open files.
- File-system failures name their reason (`Not found`, `Already exists`, `Is a directory`, `Directory not empty`, …).
- Files persist across a reboot (`persist-*`, `fs-persist`).

**Shell** (`kernel/shell.md`)

- Built-in commands, plus `run` for applications and programs.
- Pipes, `<`, `>`, `>>` and line editing.
- History of 16 commands, kept in `shell.hist` across reboots.
- Batch files and `autoexec.bat`.
- Usage hints for commands typed without their arguments.

**Applications** (`apps/`)

- `files`, the file browser:
  - lists files and directories, enters directories and goes back up with `..`;
  - views and deletes files, and says why when a delete is refused;
  - starts the applications from their entries (`fb-run-*`).
- `calc`: integer expressions, with a history at `/calc.hist`.
- `sci`: floating-point expressions using the x87 FPU.
- `matrix`: matrices up to 6 × 6.
- `edit` and `vedit`: full-screen text editors with a 16 KB buffer that load and save by path. `vedit` names every action on its message line.
- `draw`: an ASCII drawer on a 64 × 18 canvas, with points, lines, rectangles and fill, that loads and saves by path.

**Programs** (`kernel/loader.md`, `programs/README.md`)

- SQX and ELF32 programs are loaded from the data disk with an argument string of up to 63 characters.
- Sample programs: `hello`, `wc`, `ls`, `cat`, `nest`, `crash`, `heap`, `devtest`, `elfhello`.

**Localization** (`kernel/localization.md`)

- `en`, `la` and `tlh` string tables. `lang` switches at run time, with English fallback.

**Tools** (`guides/getting-started.md`)

- `tools/build.sh` and `tools/run.sh` build the images and start QEMU.
- `tools/regress.sh` runs the regression suite and `tools/bochs_smoke.sh` the Bochs smoke test.
- `tools/sqfs.py` reads and writes the data disk from the host.

## 0.9.3 — Intentional Limitations

| Item | Description |
|------|-------------|
| Hardware | Pentium-class CPU or later with CPUID, an FPU and 4 MB pages. BIOS boot only. A PS/2 keyboard (or BIOS emulation of one), VGA text mode, and ATA disks on the primary channel. Tested in QEMU and Bochs. VirtualBox, VMware and real hardware are untested. |
| Memory | Pages above 256 MB are not used. Tested from 4 MB to 128 MB. |
| Ring 0 | Programs run in ring 0. Paging keeps program areas apart, but a program can write over kernel memory. User mode is 2.x. |
| Stacks | 8 KB per process slot, not grown. A stack overflow resets the machine (`kernel/crash-reports.md`). |
| No FPU save | The x87 state is not saved on a process switch, so only one process should use floating point at a time (`sci` or `matrix`). Task 1.0-fpu. |
| Zombies | A process nobody waits for keeps its slot. Task 1.0-zombie. |
| Program size | 64 KB per program image, at `0x30000`. Heap through `SYS_SBRK`. |
| File system | 64 entries in all, 15-character names, 63-character paths. No seek. Sequential reads and writes per descriptor. No cache, journal or fsck. Programs see a failed file call as −1 without its reason (task 1.0-errno). |
| Boot disk | `hd0` is never written. Without a data disk the system runs with no files. |
| Editors | Files over 16 KB load truncated, with a warning. Search is in since 1.0.9, one-level undo since 1.0.11, and the `vedit` control-character display since 1.0.12. |
| Drawing | ASCII only, on a fixed 64 × 18 canvas. No pixel graphics (milestone 1.3 and 1.6-draw-pixels). |
| Scaffolds | `topo` prints a scaffold message and returns; the banner lists it as planned. It waits for 2.x. `graph` plots since 1.3.3. `diff` does derivatives (1.0.7), integrals (1.0.8) and ODEs by Euler's method (1.0.10). |
| Localization | Most messages are still English literals. The boot-sector and CPU-check messages are English only by design, because they print before the string tables exist. |
| Pipes | Stages run one after another, not concurrently. Output beyond 32 KB per stage is cut. There is no quoting and no separate error stream. |
| Drivers | Polled I/O only, with no interrupt-driven ATA. Devices are fixed at boot, with no `/dev` namespace and no loadable drivers. |
| No GUI, mouse or network | Milestones 1.3 to 1.6 and 2.0. |

## 1.0.0

1.0.0 is the 0.9.3 system tagged, and the two 0.9.3 sections above describe it. The only changes are the version string and the one-boot `walk-1.0` check (`releases/1.0.0.md`).

## 1.0.1

- Each process keeps its own x87 FPU registers across a process switch (`kernel/processes.md`; `fpu-switch`). The "No FPU save" limitation of 0.9.3 is gone.

## 1.0.2

- `SYS_SEEK` (25) moves a file descriptor's position within the file (`kernel/filesystem.md`; `seek`). The "No seek" limitation of 0.9.3 is gone; 26 system calls (0–25).

## 1.0.3

- `SYS_FSERROR` (26) tells a program why its last file call failed, in the words the shell prints (`kernel/filesystem.md`; `errno-*`). 27 system calls (0–26).

## 1.0.4

- A zombie nobody can wait for is freed, and `spawn` reclaims the oldest zombie when the table is full (`kernel/processes.md`; `zombie`, `zombie-ps`). The "Zombies" limitation of 0.9.3 is gone.

## 1.0.5

- The shell's usage lines and every file-system error reason follow `lang` (`kernel/localization.md`; `l10n-*`). The same words reach the editors, `draw` and `SYS_FSERROR`.

## 1.0.6

- The `calc` title, the `edit` status line and the `draw` title use the `calc`, `edit` and `draw` keys in the current language (`kernel/localization.md`; `l10n-*-tlh`, `l10n-draw-la`). The rest of the apps' help text is still English.

## 1.0.7

- `diff` computes numerical derivatives: `d <f(x)> at <x0>`, a central difference on the `sci` evaluator (`apps/calculators.md`; `diff-*`). The banner lists `diff` as an app, no longer as planned.

## 1.0.8

- `diff` computes numerical integrals: `i <f(x)> from <a> to <b>`, composite Simpson on 1000 panels (`apps/calculators.md`; `diff-int*`).

## 1.0.9

- `edit` and `vedit` search: Ctrl+F, then F3 to find the same text again (`apps/editors.md`; `ed-find*`).

## 1.0.10

- `diff` solves y′ = f(x, y) by Euler's method: `euler <f(x,y)> from <x0> to <x1> y0 <y0> step <h>` (`apps/calculators.md`; `diff-euler*`).

## 1.0.11

- `edit` and `vedit` undo the last edit with Ctrl+Z, one level (`apps/editors.md`; `ed-undo*`).

## 1.0.12

- `vedit` shows control characters with Ctrl+T: `$` for a line end, `>` for a tab and `^` for any other control character (`apps/editors.md`; `ved-ctl*`). This completes the 1.0.x list in `TODO.md`.

## 1.1.0

- The timer preempts a loaded program after a 50 ms slice, so a program that spins without a system call no longer starves the others. Kernel code still switches only cooperatively (`kernel/processes.md`; `sched-preempt`). The "Cooperative scheduling" limitation of 0.9.3 is gone.

## 1.1.1

- A `spawn` whose entry is in the program's own image is a thread: it shares the program's memory, with its own stack and pid (`kernel/processes.md`; `thread`). This completes milestone 1.1.

## 1.2.0

- `SYS_SEND` (27) and `SYS_RECV` (28) pass four-byte messages through a queue of 8 per process; a full queue returns −2 (`kernel/messages.md`; `msg`). 29 system calls (0–28).

## 1.2.1

- `SYS_KEYEVENTS` (29) lets one process also receive each key press as a `MSG_KEY` message, the same character `SYS_GETC` returns (`kernel/messages.md`; `keyev*`). 30 system calls (0–29). This completes milestone 1.2.

## 1.3.0

- The kernel can switch to 320 × 200 × 256 graphics (VGA mode 13h) and back to text mode, and write and read a pixel (`kernel/graphics.md`; `gfxtest`, `gfx-text`). Lines, rectangles, text and `graph` follow in later 1.3 tasks.

## 1.3.1

- Lines (Bresenham) and filled rectangles in graphics mode (`kernel/graphics.md`; `gfxprim`, `gfxprim-text`). Drawing above row 103 can still change the text screen and the font.

## 1.3.2

- Strings in graphics mode with an original 5 × 7 font for printable ASCII (`kernel/graphics.md`; `gfxtext`, `gfxtext-text`).

## 1.3.3

- `graph` plots y = f(x) for x and y from −10 to 10 (`apps/calculators.md`; `graph`, `graph-domain`, `graph-syntax`, `graph-mem`). The banner lists `graph` as an app; only `topo` is planned. Graphics mode now saves and restores the text screen and the font (`kernel/graphics.md`). This completes milestone 1.3.

## 1.4.0

- A window manager in graphics mode: up to 4 windows, each with a frame, a title bar and a client area, drawn over a desktop; created and closed by the kernel (`kernel/windows.md`; `wintest`, `wintest-text`). Moving, resizing and focus follow in later 1.4 tasks.

## 1.4.1

- Windows can be moved and resized; a move or size that would leave the screen or go below the minimum is refused and changes nothing (`kernel/windows.md`; `winmove`, `winmove-text`).

## 1.4.2

- Windows have a z-order: the top window has the keyboard focus and a blue title bar, the others a grey one. Tab brings the bottom window to the top; typed characters go to the focused window's text (`kernel/windows.md`; `winfocus`, `winfocus-none`, `winfocus-text`). This completes milestone 1.4.

## 1.5.0

- Widgets inside windows, starting with a text label; up to 16 widgets in all, dropped with their window (`kernel/widgets.md`; `labeltest`, `labeltest-text`). Button, edit field and list follow in later 1.5 tasks.

## 1.5.1

- A button widget: Enter or Space, while its window has the focus, posts `MSG_BUTTON` with the button's code to the process that added it, through the 1.2 message queue (`kernel/widgets.md`; `buttontest`, `buttontest-2`, `buttontest-none`, `buttontest-text`).

## 1.5.2

- A one-line edit field: typed printable characters go into a caller's buffer, up to a set length, and Backspace deletes (`kernel/widgets.md`; `fieldtest`, `fieldtest-full`, `fieldtest-text`).

## 1.5.3

- A list widget: items in a column with one selected; Down and Up move the selection and stop at the ends (`kernel/widgets.md`; `listtest`, `listtest-end`, `listtest-up`, `listtest-text`). This completes milestone 1.5.

## 1.6.0

- The `desktop` command: graphics mode with a window listing `files`, `calc`, `edit`, `vedit` and `draw`; Up and Down choose, Esc returns to the shell (`apps/desktop.md`; `desktop`, `desktop-quit`). The shell prompt is still what the system boots to; an `autoexec.bat` line `desktop` boots into the desktop. `tools/qemu_screen.py` can read text off the graphics screen (`<gfx>`; `gfx-read-list`; `desktop-boot`, `desktop-boot-quit`).

## 1.6.1

- On the desktop, Enter on `calc` runs the calculator in a window: a 52 × 20 view of a text screen in a page of its own; Esc in `calc` closes the window and the desktop is back (`apps/desktop.md`; `desktop-calc`, `desktop-calc-back`, `desktop-calc-mem`, `desktop-calc-text`). `putc`, `cls` and `scroll_up` write through `txt_base`.

## 1.6.3

- On the desktop, Enter on `draw` runs the ASCII drawing program in the same kind of window as `calc`. `draw` and the shared status-row routine `sb_row` write the text screen through `txt_base` and set `txt_dirty`. The window shows the rows that end at the cursor, so the canvas while drawing and the message row while `draw` asks a question (save as, unsaved changes, brush) (`apps/desktop.md`, `apps/draw.md`; `desktop-draw`, `desktop-draw-save`, `desktop-draw-back`, `desktop-draw-mem`, `desktop-draw-text`).

## 1.6.4

- On the desktop, Enter on `edit` or `vedit` opens the editor in a 52 × 20 window with an empty buffer; it saves as usual (Ctrl+S or F2 asks for a name) and Esc closes the window (`apps/desktop.md`; `desktop-edit`, `desktop-edit-save`, `desktop-vedit-save`, `desktop-edit-mem`). The editor writes through `txt_base` and fits its rows and columns to `txt_rows` and `txt_cols`.

## 1.6.5

- `g` in `draw` opens an 80 × 50 pixel canvas, three times larger in graphics mode (over the desktop when `draw` runs in a window). Space plots, `p` draws strokes, F2 saves `<drawing>.px` (4006 bytes: `SQPX`, width, height, one colour byte per pixel), and it is loaded again when the canvas opens. `drawpx` checks a stroke on the screen and through save and load (`apps/draw.md`; `drawpx`, `drawpx-text`, `drawpx-mem`, `draw-pixels`, `desktop-draw-pixels`, `desktop-draw-pixels-back`).

## 1.7.0

- Kernel objects: classes (name, parent, method table of selector names) and objects in a table of 32; `obj_send` runs the first method for the selector in the object's class or its parents, with the object as self, and returns CF set for an unknown selector (`kernel/objects.md`; `objtest`, `objtest-text`). Up to 32 classes and 32 objects.

## 1.7.1

- Instance fields: a class names its own fields, laid out after its parent's; an object holds up to 7 dword fields. `obj_field` finds an index by name, `obj_get` / `obj_set` work by index and refuse one the class does not have (`kernel/objects.md`; `objfields`).

## 1.7.2

- Installer steps I.1 and I.2 (`guides/install.md`): the ATA driver probes the secondary channel too (drives 2 and 3, not in the device table). `install` picks a target that is neither the boot disk nor the data disk; `install part` writes an MBR with one type-7F partition from LBA 2048; `install format` formats SQFS with an empty root in it; `install ls` lists that root. Each write asks y/n first. BIOS and IDE only (`install-*` checks).

## 1.7.3

- `objs` lists the recorded classes with their parents and the live objects with their classes and a count; `obj_free` gives a slot back and refuses anything that is not a live object (`kernel/objects.md`; `objs-empty`, `objs-tree`, `objtest-mem`).

## 1.7.4

- Installer step I.3 (`guides/install.md`): `install copy` writes the kernel to sectors 1 to 192 of the target and copies the data disk's root files into its SQFS partition, after a y/n question; files over 64 KB and subdirectories are skipped. The boot disk must be an IDE disk (`install-copy`, `install-copied`).

## 1.7.5

- Installer step I.4 (`guides/install.md`): `install boot` writes the boot code into the target's sector 0, keeping its partition table, and marks partition 1 active, after a y/n question. Booted with no data disk, the system uses partition 1 of the boot disk as its file system (`install-alone`).

## 1.7.6

- The desktop's entries are `Program` objects (under `DesktopObject`), made when the desktop starts and freed when it closes; the list shows what each answers to `name`, and Enter sends `open`, which runs the program in a window. `files` opens in a window too (`apps/desktop.md`; `desktop-files`, `desktop-files-back`, `desktop-objs`).

## 1.7.7

- Installer step I.5 (`guides/install.md`): `run install` asks once (Enter installs, Esc writes nothing) and then partitions, formats, copies and writes the boot code, one line per step, in the current language (`inst-*` checks).

## 1.8.0

- `obj_save` and `obj_load` write an object to a file and read it back; text fields (marked in the class's `CLS_TEXT`) are saved as text, up to 31 characters, in files of up to 256 bytes; a file whose class is not recorded is refused (`kernel/objects.md`; `objstore`).

## 1.8.1

- Installer step I.6: `tools/build.sh` writes `build/cd.iso`, an El Torito floppy-emulation CD around `floppy.img`. Booting from it works; installing from it needs an ATAPI driver (2.x).

## 1.8.2

- `objcat <file>` loads an object file and prints its class and fields (`kernel/objects.md`). After a reboot the file still reads: when the class is not yet recorded, the class name and field values are printed from the file (`obj-persist`).

## 1.8.3

- The desktop's entries are object files in `/desktop`, written the first time and loaded each time; a removed file's entry is not listed; `entry` holds the program's name as text (`apps/desktop.md`; `dk-store`, `dk-store-cat`, `dk-store-rm`, `dk-store-left`, `dk-store-open`).

## 1.9.0

- Desktop folders: a `Folder` class and a text field `in` on `DesktopObject`; the desktop shows one folder at a time (Enter opens, Backspace returns to the top level); `/desktop/Tools.obj` is an empty folder written with the defaults (`apps/desktop.md`; `dk-folder`, `dk-folder-open`, `dk-folder-back`, `dk-folder-cat`, `dk-folder-quit`).

## 1.9.1

- On the desktop, `m` picks up an object, `p` drops it into the folder shown (its `in` field is set and its file saved), and Esc puts it back; folders are dropped only at the top level (`apps/desktop.md`; `dk-hold`, `dk-hold-esc`, `dk-move`, `dk-move-top`, `dk-move-cat`, `dk-move-open`, `dk-move-fold`).

## 1.9.2

- On the desktop, `r` renames the chosen object (saved; a folder's contents follow it) and Delete removes it and its file after `y`; a non-empty folder is refused (`apps/desktop.md`; `dk-rename-win`, `dk-rename`, `dk-rename-esc`, `dk-delete-ask`, `dk-delete-no`, `dk-delete`, `dk-delete-full`).

## 1.9.3

- A network layer with a loopback interface: frames of 1 to 1514 bytes, 8 waiting per interface, one page each while queued (`kernel/network.md`; `nettest`, `nettest-mem`).

## Notes

- Items listed here are accepted characteristics of the current milestone.
- Defects that violate these specifications belong in `knownbugs.md`.
- Future milestones (see `plannedmilestones.md`) remove limitations by design.
