# Squirrel-OS/2 Documentation

Ongoing documentation for the Squirrel-OS/2 project.

Squirrel-OS/2 is an original operating-system effort in the spirit of OS/2 Warp.  
All material under this tree is project-native. External or contemporary sources are kept separate and are not copied here.

## Structure

| Directory       | Purpose                                      |
|-----------------|----------------------------------------------|
| `architecture/` | High-level design, goals, and system model   |
| `kernel/`       | Kernel design notes and implementation log   |
| `guides/`       | Build, run, and contribution guides          |
| `releases/`     | Release notes and version history            |

## Status

Documentation is active.

- Architecture overview expanded
- PIT timer design added (`architecture/pit-timer.md`)
- Release process formalized (`releases/PROCESS.md`)
- Milestone plan added (`plannedmilestones.md`) — 1.0.0 defined
- Known bugs list added (`knownbugs.md`) — no open defects as of 0.9.3 (KB-11 to KB-15 found and resolved in 0.9.3)
- Specifications added (`specifications.md`) — capabilities and intentional limitations, current to 0.9.3
- Forward plan: [`../ROADMAP.md`](../ROADMAP.md). Task list: [`../TODO.md`](../TODO.md). Milestone history: `plannedmilestones.md`
- 0.1.1 syscall interface implemented (`kernel/syscalls.md`, `releases/0.1.1.md`); regression script `tools/regress.sh`
- 0.1.2 process model implemented (`kernel/processes.md`, `releases/0.1.2.md`)
- 0.2.0 ATA PIO block driver implemented (`kernel/block-device.md`, `releases/0.2.0.md`)
- 0.2.1/0.2.2 SQFS file system implemented (`kernel/filesystem.md`, `releases/0.2.1.md`)
- 0.2.3 file browser implemented (`apps/files.md`, `releases/0.2.3.md`)
- 0.3.x apps: calculator polish, editors (`releases/0.3.2.md`), draw (`releases/0.3.3.md`)
- 0.4.0–0.4.2 program loader and user programs (`kernel/loader.md`, `releases/0.4.0.md`, `releases/0.4.2.md`)
- 0.3.4 scientific and matrix calculators (`apps/calculators.md`, `releases/0.3.4.md`)
- 0.5.0 pipes and redirection (`kernel/shell.md`, `releases/0.5.0.md`)
- 0.5.1 line editing and command history (`kernel/shell.md`, `releases/0.5.1.md`)
- 0.5.2 batch files (`kernel/shell.md`, `releases/0.5.2.md`)
- 0.6.0 page allocator (`kernel/memory.md`, `releases/0.6.0.md`)
- 0.6.1 paging and per-process address spaces (`kernel/memory.md`, `releases/0.6.1.md`)
- 0.6.2 program heaps with `SYS_SBRK` (`kernel/memory.md`, `releases/0.6.2.md`)
- 0.7.0–0.7.2 device model: registry, console, keyboard, disks (`kernel/drivers.md`, `releases/0.7.0.md`)
- 0.8.0 SQFS directories (`kernel/filesystem.md`, `releases/0.8.0.md`)
- 0.8.1 localization runtime (`kernel/localization.md`, `releases/0.8.1.md`)
- 0.8.2 crash reports and shell restart (`kernel/crash-reports.md`, `releases/0.8.2.md`)
- 0.9.0 browser launches the 1.0 apps (`releases/0.9.0.md`)
- 0.9.1 files persist across reboots (`releases/0.9.1.md`)
- 0.9.2 stability and polish pass (`releases/0.9.2.md`, `knownbugs.md`)
- 0.9.3 release readiness: floppy boot, CPU check, build/run scripts, Bochs (`releases/0.9.3.md`, `guides/getting-started.md`)
- **1.0.0 released** — the usable minimal system (`releases/1.0.0.md`, `specifications.md`)
- 1.0.1 each process keeps its own FPU registers (`releases/1.0.1.md`, `kernel/processes.md`)
- 1.0.2 `SYS_SEEK` on open files (`releases/1.0.2.md`, `kernel/filesystem.md`)
- 1.0.3 `SYS_FSERROR`: programs read why a file call failed (`releases/1.0.3.md`)
- 1.0.4 zombies nobody waits for are freed (`releases/1.0.4.md`, `kernel/processes.md`)
- 1.0.5 shell usage lines and file-system errors localized (`releases/1.0.5.md`, `kernel/localization.md`)
- 1.0.6 calc, edit and draw titles follow `lang` (`releases/1.0.6.md`, `kernel/localization.md`)
- 1.0.7 numerical derivatives in `diff` (`releases/1.0.7.md`, `apps/calculators.md`)
- 1.0.8 numerical integrals in `diff` (`releases/1.0.8.md`, `apps/calculators.md`)
- 1.0.9 search in `edit` and `vedit` (`releases/1.0.9.md`, `apps/editors.md`)
- 1.0.10 Euler ODE stepper in `diff` (`releases/1.0.10.md`, `apps/calculators.md`)
- 1.0.11 one-level undo in `edit` and `vedit` (`releases/1.0.11.md`, `apps/editors.md`)
- 1.0.12 `vedit` control-character display (`releases/1.0.12.md`, `apps/editors.md`)
- 1.1.0 the timer preempts a spinning program (`releases/1.1.0.md`, `kernel/processes.md`)
- 1.1.1 threads: a spawn in a program's own image shares its memory (`releases/1.1.1.md`, `kernel/processes.md`)
- 1.2.0 message queues: `SYS_SEND` and `SYS_RECV` (`releases/1.2.0.md`, `kernel/messages.md`)
- 1.2.1 key events: `SYS_KEYEVENTS` posts each key to a process's queue (`releases/1.2.1.md`, `kernel/messages.md`)
- 1.3.0 graphics mode 13h, a pixel written and read back (`releases/1.3.0.md`, `kernel/graphics.md`)
- 1.3.1 lines and filled rectangles (`releases/1.3.1.md`, `kernel/graphics.md`)
- 1.3.2 text in graphics mode, original 5 × 7 font (`releases/1.3.2.md`, `kernel/graphics.md`)
- 1.3.3 `graph` plots y = f(x) (`releases/1.3.3.md`, `apps/calculators.md`)
- 1.4.0 windows: create, draw and close (`releases/1.4.0.md`, `kernel/windows.md`)
- 1.4.1 windows: move and resize (`releases/1.4.1.md`, `kernel/windows.md`)
- 1.4.2 windows: z-order and keyboard focus (`releases/1.4.2.md`, `kernel/windows.md`)
- 1.5.0 widgets: a text label in a window (`releases/1.5.0.md`, `kernel/widgets.md`)
- 1.5.1 widgets: a button that posts a message (`releases/1.5.1.md`, `kernel/widgets.md`)
- 1.5.2 widgets: a one-line edit field (`releases/1.5.2.md`, `kernel/widgets.md`)
- 1.5.3 widgets: a list with a selection (`releases/1.5.3.md`, `kernel/widgets.md`)
- 1.6.0 `desktop` lists the programs in a window (`releases/1.6.0.md`, `apps/desktop.md`)
- 1.6.1 `calc` runs in a window on the desktop (`releases/1.6.1.md`, `apps/desktop.md`)
- 1.6.3 `draw` runs in a window on the desktop (`releases/1.6.3.md`, `apps/desktop.md`)
- 1.6.4 `edit` and `vedit` run in windows on the desktop (`releases/1.6.4.md`, `apps/desktop.md`)
- 1.6.5 pixel drawing in `draw` (`releases/1.6.5.md`, `apps/draw.md`)
- 1.7.0 objects: classes and messages (`releases/1.7.0.md`, `kernel/objects.md`)
- 1.7.1 objects: instance fields (`releases/1.7.1.md`, `kernel/objects.md`)
- 1.7.2 installer steps I.1 and I.2: the target disk, its partition table and SQFS (`releases/1.7.2.md`, `guides/install.md`)
- 1.7.3 objects: the `objs` listing and `obj_free` (`releases/1.7.3.md`, `kernel/objects.md`)
- 1.7.4 installer step I.3: `install copy` puts the kernel and the data disk's files on the target (`releases/1.7.4.md`, `guides/install.md`)
- 1.7.5 installer step I.4: `install boot`; an installed disk boots and uses its own partition (`releases/1.7.5.md`, `guides/install.md`)
- 1.7.6 the desktop's entries are objects, and `files` opens in a window (`releases/1.7.6.md`, `apps/desktop.md`)
- 1.7.7 installer step I.5: `run install`, the localized install program (`releases/1.7.7.md`, `guides/install.md`)
- 1.8.0 object files: `obj_save` and `obj_load` (`releases/1.8.0.md`, `kernel/objects.md`)
- 1.8.1 installer step I.6: `build/cd.iso`, a bootable CD image (`releases/1.8.1.md`, `guides/install.md`)
- 1.8.2 objects: `objcat` prints a saved object after a reboot (`releases/1.8.2.md`, `kernel/objects.md`)
- 1.8.3 the desktop's entries are kept as object files in `/desktop` (`releases/1.8.3.md`, `apps/desktop.md`)
- 1.9.0 desktop folders: a `Tools` folder that Enter opens and Backspace leaves (`releases/1.9.0.md`, `apps/desktop.md`)
- 1.9.1 pick up, move and drop on the desktop: `m`, `p`, Esc (`releases/1.9.1.md`, `apps/desktop.md`)
- 1.9.2 rename and delete on the desktop: `r`, Delete (`releases/1.9.2.md`, `apps/desktop.md`)
- 1.9.3 network layer: interfaces, packet queues and loopback; `nettest` (`releases/1.9.3.md`, `kernel/network.md`)
- 1.9.4 NE2000 network card, polled; `devices` shows its MAC address (`releases/1.9.4.md`, `kernel/network.md`)
- 1.9.5 Ethernet framing and ARP; `arp <ip>` (`releases/1.9.5.md`, `kernel/network.md`)
- 1.9.6 IPv4 and ICMP echo; `ping <ip>` (`releases/1.9.6.md`, `kernel/network.md`)
- 1.9.7 UDP; `net_sendto` and `net_recvfrom`; `run udptest` (`releases/1.9.7.md`, `kernel/network.md`)
- 1.9.8 a small TCP client; `fetch <ip> <port> <path>` (`releases/1.9.8.md`, `kernel/network.md`)
- 1.9.9 priority scheduling; `run priotest` (`releases/1.9.9.md`, `kernel/processes.md`)
- 1.9.10 polled PS/2 mouse on the desktop; `mousetest` (`releases/1.9.10.md`, `kernel/mouse.md`)
- 1.9.11 `ifconfig` for inet / mask / gw (`releases/1.9.11.md`, `kernel/network.md`)
- 1.9.12 devices registered at run time; `run drvtest` (`releases/1.9.12.md`, `kernel/drivers.md`)
- Next: 2.0.0 once the owner says so (`../TODO.md`, `../ROADMAP.md`).
