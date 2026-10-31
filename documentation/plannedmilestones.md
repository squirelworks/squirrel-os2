# Squirrel-OS/2 Planned Milestones

## Naming and scope decision (2026-10-14)

The project keeps the name Squirrel-OS/2.

- **1.0.0** is a usable minimal system (file system, browser, editor, drawing program, calculator).
- **2.0.0** is the first release that can honestly be described as Warp-like  
  (preemptive scheduler, windowing system, object-oriented desktop).
- Pre-2.0 releases are not marketed as OS/2.
- If the project one day outgrows the Warp inspiration, the name can still remain;  
  the code stays original either way.

## Competitor Landscape (analysis)

| Project | Status | What exists | Gap relative to Squirrel-OS/2 1.0.0 goal |
|---------|--------|-------------|------------------------------------------|
| **osFree** | Deep alpha | FreeLdr, CMD tools, experimental L4 personality, partial SOM, DOS/WIN16 work | No complete bootable GUI OS; userland-focused |
| **Voyager** | Stalled / archived | CLI fragments; WPS sources restricted | Not an active full system |
| **ArcaOS** | Commercial, functional | Full Warp 4.52 derivative: WPS, PM, HPFS/JFS, drivers, UEFI, SMP, apps | Closed source; licensed IBM base |
| **OS2World** | App/driver archive | Native programs, drivers, libraries | Not an OS |

Squirrel-OS/2 remains original code only. The 1.0.0 target is a small functional system (file system + browser + applications including dual editors), not full Warp API compatibility.

## Vision for 1.0.0

A functional original operating system that:

- Boots and owns the machine
- Provides a file system
- Includes a file browser
- Loads and runs a normal text editor, a verbose text editor, a drawing program, and a calculator suite

## Milestone Ladder (0.0.4 → 1.0.0)

### 0.0.x — Hardware ownership
- **0.0.1** — Boot sector: VGA text + periodic beep (done)
- **0.0.2** — Native PIT timer (done)
- **0.0.3** — Protected-mode transition + GDT (done)
- **0.0.4** — IDT + restore native timer in protected mode (done)
- **0.0.5** — Keyboard input (IRQ1) + basic console (done)
- **0.0.6** — Simple memory map and page allocator (done — bump allocator)

### 0.1.x — Kernel services
- **0.1.0** — Cooperative task switch (done)
- **0.1.1** — System call interface (int 0x80 or equivalent) (done — `int 0x80`: putc, puts, getc, yield; see `kernel/syscalls.md`)
- **0.1.2** — Basic process model (create, exit, wait) (done — cooperative spawn/exit/wait/getpid, `run` spawns; see `kernel/processes.md`)

### 0.2.x — Storage
- **0.2.0** — Block device driver (ATA PIO or virtio-blk) (done — ATA PIO LBA28, `kernel/block-device.md`)
- **0.2.1** — Minimal file system (flat directory or simple hierarchical) (done — SQFS, flat, `kernel/filesystem.md`)
- **0.2.2** — File open/read/write/close (done — plus create/delete/rename, syscalls 10–16)
- **0.2.3** — File browser (list, navigate, launch) (done — `run files`, `apps/files.md`)

### Session bookmark (2026-10-14)
In-memory file system and interactive application stubs are implemented:
- Commands: `ls`, `cat <name>`, `run <name>`
- Basic calculator (`calc`): interactive integer arithmetic + percentage
- Calculator suite scaffolds: `sci`, `graph`, `matrix`, `diff`, `topo`
- Editors: interactive `edit` and `vedit` (shared buffer, insert/backspace/enter, Esc exit)
- Drawing program: interactive text-mode canvas (`run draw`, arrows/plot/erase/clear, Esc exit)
- Location: `kernel/pm.asm`, notes in `releases/fs-and-apps.md` and `releases/0.3.1.md`
- Designs: `documentation/apps/editors.md`, `documentation/apps/calculators.md`, `documentation/apps/draw.md`

This is a natural end-of-day point. Next session can resume at either:
- polish basic calculator (chained operations, previous-result recall), or
- persistent block device + real file system, or
- richer application stubs / syscall interface (0.1.1).

### 0.3.x — Applications
- **0.3.0** — Program loader: moved to 0.4.0 / 0.4.1 below
- **0.3.1** — Calculator suite
  - Basic (`calc`): interactive integer arithmetic + percentage — polished (precedence, parentheses, `ans`, chaining, errors, history file) in `kernel/calc.asm`
  - Scientific (`sci`): floating-point + transcendentals — done in 0.3.4 (`kernel/sci.asm`, x87 FPU)
  - Graphing (`graph`): function plots — scaffolded (needs graphics)
  - Matrix (`matrix`): linear algebra — done in 0.3.4 (add, multiply, scale, det, transpose, inverse; `kernel/matrix.asm`)
  - DiffEq / Calculus (`diff`): numerical derivatives, integrals, ODEs — scaffolded
  - Topology (`topo`): simplicial homology sketches — scaffolded (long-term)
  - Design: `documentation/apps/calculators.md`
- **0.3.2** — Text editor project (done — full-screen `edit`/`vedit` with load/save, `apps/editors.md`)
  - Shared buffer primitives (insert, delete, cursor, capacity) — basic insert/backspace/enter/esc implemented in `kernel/pm.asm`
  - Normal editor (`edit`): minimal status line, ordinary feedback
  - Verbose editor (`vedit`): full status (line, column, offset, char code, mode, size, capacity) — prefix shown; numeric still scaffolded
  - Both load/save via in-memory FS first, then persistent FS
  - Design: `documentation/apps/editors.md`
  - Current: interactive mode via keyboard ISR (`run edit`, `run vedit`, Esc to exit)
- **0.3.3** — Drawing program (done — ASCII drawer with load/save, lines, rectangles, fill, `apps/draw.md`)
  - 64×18 canvas drawn in place, pen, brush, status line, `kernel/draw.asm`
  - Design: `documentation/apps/draw.md`
  - Pixel / framebuffer drawing deferred until graphics primitives and window manager exist

### 0.4.x — Program loader & user programs
- **0.4.0** — Flat binary loader (done — SQX format, `run <file>`, `kernel/loader.md`)
- **0.4.1** — ELF32 loader (done — static `ET_EXEC`, `PT_LOAD` only, native parser in `kernel/loader.asm`)
- **0.4.2** — User programs (done — `hello`, `wc`, `ls`, `cat`, `elfhello` in `programs/`, `SYS_READDIR`)

### 0.5.x — Shell & command environment
- **0.5.0** — Pipes and redirection (done — `|`, `>`, `>>`, `<`, `echo`; `kernel/shell.md`)
- **0.5.1** — Command history and line editing (done — arrows, Home/End, Delete, Esc, 16-line history in `shell.hist`; kernel image grows to 64 KB)
- **0.5.2** — Batch files run line by line (done — `batch <file>`, `run x.bat`, `#` comments, `@` quiet lines, Esc stops, `autoexec.bat` at boot)

### 0.6.x — Memory management
- **0.6.0** — Physical page allocator with free lists (done — E820 map, free list + bitmap, `mem`/`memtest`, `kernel/memory.md`)
- **0.6.1** — Per-process address spaces (page directory bookkeeping)
- **0.6.2** — Stack/heap growth

### 0.7.x — Device model
- **0.7.0** — Driver registration table (name, probe, ops)
- **0.7.1** — Console and keyboard as devices
- **0.7.2** — ATA block device registered as a driver

### 0.8.x — Integration foundations
- **0.8.0** — Hierarchical directories or long names in SQFS
- **0.8.1** — Localization runtime (select `localization/` strings at run time)
- **0.8.2** — Better exception / crash reporting

### 0.9.x — Integration
- **0.9.0** — File browser launches the applications (calc, edit, vedit, draw)
- **0.9.1** — Files persist across reboot
- **0.9.2** — Stability and polish pass

### 1.0.0 — Functional OS
- Boots to a usable environment
- File system present and browsable
- Text editor (`edit`), verbose editor (`vedit`), drawing program, and calculator suite load and run
- Original Squirrel-OS/2 code throughout

## Path to 2.0 — Warp-style revival

Version 2.0 is the point at which Squirrel-OS/2 offers a recognizable OS/2 Warp personality: preemptive multitasking, a graphical windowing system, an object-oriented desktop, and enough services that it feels like a modern Warp rather than a minimal demo.

It does **not** target binary compatibility with existing OS/2 applications (that remains osFree’s goal). It targets original implementations of the major Warp concepts.

### What “Warp-like” means here

| Warp concept | Squirrel-OS/2 2.0 interpretation |
|--------------|----------------------------------|
| Preemptive multitasking | Priority-based scheduler, threads |
| Presentation Manager | Original windowing + graphics API |
| Workplace Shell | Object-oriented desktop built on the windowing system |
| SOM | Lightweight object model sufficient for the desktop |
| File systems | Hierarchical FS with long names and metadata |
| Device model | Loadable drivers for console, storage, input |
| Networking | Basic TCP/IP stack and utilities |
| Command environment | Native shell with pipes and redirection |

### 1.x — Foundation for a desktop
- **1.1** — Preemptive scheduler and thread primitives
- **1.2** — Message-passing and event queue
- **1.3** — Basic graphics primitives (lines, fills, text, bitmaps)
- **1.4** — Window manager (create, move, resize, z-order, focus)
- **1.5** — Simple widget set (button, label, edit field, list)
- **1.6** — Desktop shell that hosts the three 1.0 applications as windows

### 1.7–1.9 — Object model and persistence
- **1.7** — Lightweight object system (classes, methods, inheritance)
- **1.8** — Persistent object store tied to the file system
- **1.9** — Drag-and-drop and basic object actions on the desktop

### 2.0 — Warp-style system
- Preemptive multitasking with threads
- Original windowing system and widget set
- Object-oriented desktop (Workplace Shell analogue)
- Hierarchical file system with a graphical browser
- Text editor (`edit`), verbose editor (`vedit`), drawing program, and calculator suite integrated as desktop objects
- Basic networking
- Native shell
- Original Squirrel-OS/2 code throughout

## Path to 3.0 — 64-bit Warp

Version 3.0.0 is Squirrel-OS/2 as a 64-bit operating system that retains the Warp character (preemptive multitasking, windowing, object desktop) while gaining the scale and services expected of a contemporary desktop OS.

Target: able to be considered alongside Linux, macOS, and Windows for general use.

### What 3.0 adds beyond 2.0

| Area | 3.0 expectation |
|------|-----------------|
| Address space | Native 64-bit kernel and userland |
| Memory | Demand-paged virtual memory, large RAM support |
| Scheduling | Preemptive, multi-core aware |
| Desktop | Mature object desktop, multi-monitor, accessibility |
| Storage | Journaling file system, large volumes, external media |
| Networking | Full TCP/IP, Wi-Fi, standard services |
| Applications | Self-hosting toolchain, package management, common apps |
| Hardware | UEFI boot, modern device drivers (storage, GPU, USB, audio) |
| Security | User isolation, signed updates, basic sandboxing |
| Foreign applications | Optional personality layers (Windows, Linux, Darwin, Unix, …) — see `architecture/foreign-compatibility.md` |

### 2.x — Bridge to 64-bit
- **2.1** — 64-bit kernel bring-up (long mode, new GDT/IDT)
- **2.2** — 64-bit memory management and paging
- **2.3** — Multi-core scheduler
- **2.4** — UEFI boot path
- **2.5** — Modern storage and USB drivers
- **2.6** — 64-bit userland and syscall ABI
- **2.7** — Port windowing and desktop to 64-bit
- **2.8** — Networking stack and basic services
- **2.9** — Package manager and self-hosting build

### 3.0.0 — 64-bit Warp-style OS
- 64-bit preemptive kernel
- Mature windowing system and object desktop
- Journaling file system and graphical file management
- Networking and common connectivity
- Self-hosting development environment
- Sufficient applications and drivers for daily use
- Original Squirrel-OS/2 code
- Positioned as a peer to contemporary desktop operating systems
- Optional foreign-application personalities (scaffold exists; not required for 3.0.0 core)

### Foreign application personalities (post-2.0 / optional for 3.0+)

Scaffold and minimal stub exist (`documentation/architecture/foreign-compatibility.md`, `kernel/loaders/elf_stub.asm`).

Further work is recorded here and is not required for the core Warp desktop:

- **F.1** — Native process model able to host a foreign address space
- **F.2** — Segment mapping + entry-point transfer for a static ELF32
- **F.3** — Real translation of `write` and `exit` onto native console and process exit
- **F.4** — Tiny static test binary that prints and exits under the Linux personality
- **F.5** — PE header validation stub (parallel to the ELF stub)
- **F.6** — Personality registration table (windows / linux / darwin / unix)
- **F.7** — ELF64 and x86_64 / AArch64 native paths
- **F.8** — Basic file I/O syscalls (`open`/`read`/`close`) for the Linux personality
- **F.9** — Console Win32 subset (`WriteFile` / `ExitProcess`) for the Windows personality
- **F.10** — Sandbox / capability flags on foreign processes
- Android (Bionic/ART) and iOS remain later research items and do not block F.1–F.10.

## Notes

- 1.0.0 remains the first usable system.
- 2.0.0 is the first release that can reasonably be called a Warp-style revival.
- 3.0.0 is the 64-bit evolution aimed at competing with Linux, macOS, and Windows.
- Binary compatibility with classic OS/2 (full SOM, MVDM, WIN-OS/2) remains out of scope.
- Modern foreign-application personalities (Windows PE, Linux ELF, Darwin Mach-O, etc.) are scaffolded for post-2.0 work and are optional relative to the core Warp desktop.
- Each milestone still receives a release note under `releases/`.
- External / contemporary sources stay outside this tree.
