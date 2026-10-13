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

## Notes

- Each milestone receives a release note under `releases/`.
- Design details live in `architecture/` and `kernel/`.
- External / contemporary sources stay outside this tree.
- Scope is deliberately smaller than osFree or ArcaOS; the goal is a working original system, not binary compatibility.
