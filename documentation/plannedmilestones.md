# Squirrel-OS/2 Planned Milestones

## Competitor Landscape (analysis)

| Project | Status | What exists | Gap relative to Squirrel-OS/2 1.0.0 goal |
|---------|--------|-------------|------------------------------------------|
| **osFree** | Deep alpha | FreeLdr, CMD tools, experimental L4 personality, partial SOM, DOS/WIN16 work | No complete bootable GUI OS; userland-focused |
| **Voyager** | Stalled / archived | CLI fragments; WPS sources restricted | Not an active full system |
| **ArcaOS** | Commercial, functional | Full Warp 4.52 derivative: WPS, PM, HPFS/JFS, drivers, UEFI, SMP, apps | Closed source; licensed IBM base |
| **OS2World** | App/driver archive | Native programs, drivers, libraries | Not an OS |

Squirrel-OS/2 remains original code only. The 1.0.0 target is a small functional system (file system + browser + three applications), not full Warp API compatibility.

## Vision for 1.0.0

A functional original operating system that:

- Boots and owns the machine
- Provides a file system
- Includes a file browser
- Loads and runs a text editor, a drawing program, and a calculator

## Milestone Ladder (0.0.4 → 1.0.0)

### 0.0.x — Hardware ownership
- **0.0.1** — Boot sector: VGA text + periodic beep (done)
- **0.0.2** — Native PIT timer (done)
- **0.0.3** — Protected-mode transition + GDT (done)
- **0.0.4** — IDT + restore native timer in protected mode (next)
- **0.0.5** — Keyboard input (IRQ1) + basic console
- **0.0.6** — Simple memory map and page allocator

### 0.1.x — Kernel services
- **0.1.0** — Cooperative or preemptive task switch
- **0.1.1** — System call interface (int 0x80 or equivalent)
- **0.1.2** — Basic process model (create, exit, wait)

### 0.2.x — Storage
- **0.2.0** — Block device driver (ATA PIO or virtio-blk)
- **0.2.1** — Minimal file system (flat directory or simple hierarchical)
- **0.2.2** — File open/read/write/close
- **0.2.3** — File browser (list, navigate, launch)

### 0.3.x — Applications
- **0.3.0** — Program loader (flat binary or simple ELF)
- **0.3.1** — Calculator
- **0.3.2** — Text editor
- **0.3.3** — Drawing program (VGA framebuffer or text-mode canvas)

### 0.9.x — Integration
- **0.9.0** — File browser launches the three applications
- **0.9.1** — Files persist across reboot
- **0.9.2** — Stability and polish pass

### 1.0.0 — Functional OS
- Boots to a usable environment
- File system present and browsable
- Text editor, drawing program, and calculator load and run
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
- Text editor, drawing program, and calculator integrated as desktop objects
- Basic networking
- Native shell
- Original Squirrel-OS/2 code throughout

## Notes

- 1.0.0 remains the first usable system.
- 2.0.0 is the first release that can reasonably be called a Warp-style revival.
- Binary compatibility, full SOM, MVDM, and WIN-OS/2 are explicitly out of scope for 2.0.
- Each milestone still receives a release note under `releases/`.
- External / contemporary sources stay outside this tree.
