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
| Cooperative scheduling | A process that never yields starves the others. Preemption is milestone 1.1. |
| Ring 0 | Programs run in ring 0. Paging keeps program areas apart, but a program can write over kernel memory. User mode is 2.x. |
| Stacks | 8 KB per process slot, not grown. A stack overflow resets the machine (`kernel/crash-reports.md`). |
| No FPU save | The x87 state is not saved on a process switch, so only one process should use floating point at a time (`sci` or `matrix`). Task 1.0-fpu. |
| Zombies | A process nobody waits for keeps its slot. Task 1.0-zombie. |
| Program size | 64 KB per program image, at `0x30000`. Heap through `SYS_SBRK`. |
| File system | 64 entries in all, 15-character names, 63-character paths. No seek. Sequential reads and writes per descriptor. No cache, journal or fsck. Programs see a failed file call as −1 without its reason (task 1.0-errno). |
| Boot disk | `hd0` is never written. Without a data disk the system runs with no files. |
| Editors | Files over 16 KB load truncated, with a warning. No search, undo or control-character display (tasks 1.0-edit-*). |
| Drawing | ASCII only, on a fixed 64 × 18 canvas. No pixel graphics (milestone 1.3 and 1.6-draw-pixels). |
| Scaffolds | `graph`, `diff` and `topo` print a scaffold message and return. The banner lists them as planned. `graph` waits for 1.3, `diff` for the 1.0-diff-* tasks, and `topo` for 2.x. |
| Localization | Most messages are still English literals. The boot-sector and CPU-check messages are English only by design, because they print before the string tables exist. |
| Pipes | Stages run one after another, not concurrently. Output beyond 32 KB per stage is cut. There is no quoting and no separate error stream. |
| Drivers | Polled I/O only, with no interrupt-driven ATA. Devices are fixed at boot, with no `/dev` namespace and no loadable drivers. |
| No GUI, mouse or network | Milestones 1.3 to 1.6 and 2.0. |

## 1.0.0

1.0.0 is the 0.9.3 system tagged, and the two 0.9.3 sections above describe it. The only changes are the version string and the one-boot `walk-1.0` check (`releases/1.0.0.md`).

## Notes

- Items listed here are accepted characteristics of the current milestone.
- Defects that violate these specifications belong in `knownbugs.md`.
- Future milestones (see `plannedmilestones.md`) remove limitations by design.
