# OS/2 × ISM Flight Lab — gap matrix

**Tracker:** [squirrel-os2#225](https://github.com/squirelworks/squirrel-os2/issues/225)  
**Lane:** `-b55f` (ISM ground-station / Flight Lab host — not desktop/Warp W.6)  
**Inventoried against:** squirrelsoft `main` @ `3802359` (`squirrelflightlab/` S7.1–S7.2b,
`squirrelismbench/`); ISM `fighter-jet/avionics/computing-platform.md` and
`fighter-jet/interfaces/`

This note answers roadmap item 1 of #225: what Steve’s Flight Lab (and its sims /
HIL hooks) need from Squirrel OS/2. It is a **host-platform** gap list only.

## Boundary (do not cross)

| Runs on | Owns |
|---------|------|
| Small RTOS + **SquirrelBIOS** bring-up / BIT | Flight-critical FBW, FCC laws, vote monitors, essential HUD symbols |
| **Squirrel OS/2** (this tree) | Ground / lab: Flight Lab, mission planning, flight-data download, maintenance laptop, **HIL bench host** |

OS/2 must **not** host flight-critical control loops. Soft’s HIL path talks to Eric’s
RC flight controller / data-logger and to ISM bay I/O over serial/USB; the FCC image
stays off this OS. See ISM `computing-platform.md` and Soft `fl_planned_hil_connect`
(stub today).

## What Soft already has (host Linux/desktop today)

| Piece | Location | Notes |
|-------|----------|-------|
| Flight Lab scaffold | `squirrelsoft/squirrelflightlab/` | Portable C11 core + CLI; `make test` + happy-path demo |
| ISM YAML load | `fl_yaml` / `fl_iface` | Soft-owned YAML **subset** + top-level allowlists; fixtures from ISM `interfaces/` |
| Param / FCS co-check | `fl_ism` / `fl_fcs` | `.ismfj-params` / `.ismfj-iface`; scripted pass/fail report |
| Aero + 6-DOF sketch | `fl_aero` / `fl_dyn` | Parametric CL/CD/Cm; Euler step; history CSV; ASCII CL plot |
| Scenarios | `fl_scenario` | `trim_cruise`, `pull_up`, `roll` |
| HIL / CFD / tunnel | `fl_planned` | **Stub only** — “serial/USB to real PCB” named, not implemented |
| Consumer HID bench | `squirrelismbench/` | Keyboard/mouse fixtures (Eric lane); separate from fighter HIL |
| Planned numerics lib | Soft #174 `libs/squirrelnum` | RK45, Brent, splines, LA, quaternions — **not on Soft `main` yet** |
| Planned strip charts | Soft ROADMAP S7.4 | `sqgui` window on the same core — open |
| Shared Soft cores | `libs/sqmath`, `sqgui`, `sqdsp` | Freestanding-friendly; OS/2 `sqgui` back end still missing |

Third-party sims (OpenVSP / AVL / CalculiX) are **optional cross-checks** on the
host, never SoT (Soft #172 / #176). Do not require them inside the OS guest.

## Gap matrix

Status: **Have** = usable on OS/2 today for this use · **Partial** = related
capability exists but not enough · **Gap** = must build for #225 · **Soft** =
belongs in squirrelsoft first, then package onto OS/2 · **Out** = not an OS/2 job

### A. Runtime / process model

| Need | Soft / ISM demand | OS/2 today | Status | Follow-up |
|------|-------------------|------------|--------|-----------|
| Run Flight Lab as a native program | Freestanding-ish C11 core + thin I/O | Programs are NASM (or foreign personalities); freestanding C link-in is open (`2.9-freestanding-c`, #212) | **Gap** | Wire freestanding C, then a small libc shim (`open`/`read`/`write`/`printf`/`malloc` subset) for Soft cores |
| FPU / doubles | `math.h`, `-lm`, rigid-body + aero | Per-process FPU save (1.0.1); calc suite uses x87 | **Have** | Keep FPU discipline; no change for gap list |
| Preemptive multitasking | Lab UI + logger + HIL loop | Priority RR + PIT preemption + aging | **Have** | Raise HIL process priority when timing lands |
| Threads / shared buffers | Logger vs plotter | Threads share address space | **Partial** | Enough for v1; document no locks |
| Python numerics / scripts | Host analysis only today | No guest Python | **Out** / **Soft** | Keep Python on build host; guest path is C |
| POSIX / libc | CLI uses `stdio` / `stdlib` / `string` | No general libc; Linux ELF personality is a subset | **Gap** | Prefer Soft freestanding I/O layer over full glibc |

### B. Numerics

| Need | Soft / ISM demand | OS/2 today | Status | Follow-up |
|------|-------------------|------------|--------|-----------|
| Euler / RK integration | `fl_dyn` Euler now; Soft #174 wants RK4 / DP45 | `diff` has Euler ODE; no general integrator library | **Partial** | Soft lands `squirrelnum` (#174); OS packages that core (not reimplement in NASM) |
| Quaternions / LA / Brent / splines | Soft #174; FCS / attitude helpers | Matrix calc / `sqmath` are expression/CAS oriented | **Gap** (Soft first) | Soft #174 → then OS package |
| Analytic verification suite | Soft #172 | N/A on OS | **Soft** | Host CI; OS only needs to run the same C tests later |
| OpenVSP / AVL / CalculiX | Optional file compare | Not on OS | **Out** | Stay on Linux build hosts |

### C. File formats

| Need | Soft / ISM demand | OS/2 today | Status | Follow-up |
|------|-------------------|------------|--------|-----------|
| ISM interface YAML | `fl_iface` loads full `fighter-jet/interfaces/` snapshot | No YAML in tree; text files on SQFS/FAT fine | **Gap** (package) | Ship Soft parser + fixtures on `data.img`; refresh from ISM, do not fork SoT |
| `.sqflt` / `.ismfj-*` | Project + param texts | Ordinary text files | **Have** (FS) | Packaging task copies samples |
| CSV aero / history / logs | Soft writes CSV tables | Text editors + FAT/SQFS | **Have** (FS) | Plotting of CSV is separate (D) |
| RINEX / UBX (GNSS lab adjacent) | Soft `squirrelgnss` | Not required for Flight Lab v0 | **Out** for #225 | Optional later ground tool |
| Pass/fail report artifacts | `fcs-check` text reports | File write works | **Have** | — |

### D. Plotting / UI

| Need | Soft / ISM demand | OS/2 today | Status | Follow-up |
|------|-------------------|------------|--------|-----------|
| ASCII / CSV plots | Soft CLI today | Shell + files | **Have** | Enough for headless lab smoke |
| Live strip charts | Soft S7.4 on `sqgui` | Native `grapher` / calc GUIs exist; **no** Soft `sqgui` OS back end | **Gap** | Port `sqgui` canvas to `SYS_GUI` (suite CONTINUANCE M2); then Flight Lab window |
| Warp-look operator UI | HIL bench UI (ISM #80) | ProgMan / widgets / clipboard | **Partial** | Reuse native widgets or Soft+`sqgui`; do not steal W.6 from `-2eaf` |
| HUD/HMI tooling | ISM #82 Soft | Graphics primitives exist | **Soft** | Soft app; OS only hosts |

### E. Serial / USB data path (Eric RC + bay I/O) — #225 item 2

| Need | Soft / ISM demand | OS/2 today | Status | Follow-up |
|------|-------------------|------------|--------|-----------|
| User COM/UART API | Soft GNSS already uses POSIX serial; Flight Lab HIL names serial/USB | COM1 is debug/QEMU scrape only; **no** `com1` char device for programs | **Gap** | Character device + syscalls (open/read/write/poll) for 16550 UART; QEMU `-serial` regress |
| USB CDC-ACM / bulk serial | ISM `ISM-Bay-Debug` USB (lab only); Eric RC logger | xHCI + USB kbd + USB MSD only | **Gap** | USB CDC (or vendor bulk) class driver on xHCI; mock device in QEMU |
| Framing / BIT line | ISM `firmware-bringup.yaml` `uart_stdio_profile` (`help`/`bit`/…) | N/A | **Soft** + thin OS I/O | Soft parses lines; OS provides byte stream |
| Baud / 8N1 config | Soft GNSS 4800–921600 | N/A | **Gap** | Ioctl-style device control on the serial node |
| Record / replay files | Soft receiver recordings | Files yes | **Have** | Soft reads recordings; OS file I/O enough |

### F. Soft real-time timing — #225 item 3

| Need | Soft / ISM demand | OS/2 today | Status | Follow-up |
|------|-------------------|------------|--------|-----------|
| ~100 Hz HIL / bus loop | ISM bus defaults 100 Hz; IMU topic 200 Hz | PIT **100 Hz** ticks; `GUI_TICKS` | **Partial** | 100 Hz host loop is the soft-RT floor; document jitter; do not claim hard RT |
| Sub-tick sleep / deadlines | Deterministic HIL step | `yield` / block on I/O; no `nanosleep` | **Gap** | `SYS_SLEEP` (ms) and/or wait-until-tick; optional high-res PIT channel or APIC timer later |
| Priority for HIL task | Bench loop must not starve under UI | `SYS_SETPRIO` 0..3 + aging | **Partial** | Document HIL at prio 3; measure under load in regress |
| Jitter budget | Soft-RT “good enough for bench” | Untested for HIL | **Gap** | Regress: loop period histogram under QEMU `-icount` + a loaded GUI |
| Flight-critical scheduling | ARINC 653-style partitions | N/A | **Out** | Stays on RTOS |

### G. Packaging Flight Lab for OS/2 — #225 item 4

| Need | Soft / ISM demand | OS/2 today | Status | Follow-up |
|------|-------------------|------------|--------|-----------|
| Build Soft core into OS image | Same sources as desktop | Soft apps ported historically by rewrite in NASM | **Gap** | Freestanding C path (#212) + `data.img` install of `squirrelflightlab` |
| libc / I/O shim | Soft CLI `fopen` / `printf` | — | **Gap** | Minimal shim over SQFS/FAT + console |
| Fixtures on guest | `fixtures/ism-interfaces/`, samples | `tools/sqfs.py put` | **Partial** | Packaging PR copies a frozen fixture set |
| `sqgui` on OS | S7.4 strip charts | Native GUI only | **Gap** | After runtime C + sqgui back end |
| Release story | Lab laptop image | Installer / USB boot exist | **Partial** | Document which image + how to copy Soft build |

### H. Lab setup guide — #225 item 5

| Need | Status | Follow-up |
|------|--------|-----------|
| How to boot OS/2 as the ground station | **Gap** (docs) | After serial + packaging: `documentation/guides/ism-flightlab-setup.md` |
| Wire Eric RC / bay UART into QEMU and real hardware | **Gap** | Depends on item 2 |
| Safety: no FCC laws on OS/2 | **Have** (this note) | Repeat in setup guide |

## Roadmap mapping (#225)

| #225 box | This matrix | Suggested next PR (one focused PR each) |
|----------|-------------|-----------------------------------------|
| [x] Gap list (this document) | Whole matrix | Docs PR on OS/2 (`cursor/ism-flightlab-gaps-b55f`) |
| [ ] Serial/USB data path | §E | `com` char device + QEMU check; then USB CDC |
| [ ] Soft-RT timing | §F | `SYS_SLEEP` / tick wait + HIL jitter regress |
| [ ] Package Flight Lab | §G (+ Soft pointer) | Freestanding shim + put CLI on `data.img` (after C wire-up or minimal NASM host stub that shells Soft objects) |
| [ ] Lab setup guide | §H | Docs after serial + one packaged smoke |

Related Soft work that unblocks packaging but is **not** owned by this OS issue:
`squirrelnum` (#174), nested YAML allowlists (#177), HIL connect implementation
(Soft side of ISM #80), `sqgui` strip charts (S7.4).

## Suggested OS/2 acceptance seeds (for later PRs)

Do not invent checks in this docs PR. Later behaviour PRs should add roughly:

1. `com-echo` — open UART, write a line, read it back through QEMU chardev loop.  
2. `hil-tick` — HIL-priority loop prints period stats; expect bound under load.  
3. `flightlab-smoke` — guest runs packaged `squirrelflightlab demo` (or `fcs-check`) and prints a Soft `PASS` / `ok` line scraped by `regress.sh`.

## Inventory sources

- Soft: `squirrelflightlab/README.md`, `docs/overview.md`, `Makefile`, ROADMAP **S7** / **S8**
- Soft issues: #168 (app), #170 (YAML, done), #172–#177 (verification / numerics / allowlists)
- ISM: `fighter-jet/avionics/computing-platform.md`, `software-partitioning.md`,
  `interfaces/schema-manifest.yaml`, `firmware-bringup.yaml`, `avionics-bus.yaml`
- OS/2: `documentation/kernel/processes.md`, `syscalls.md`, `hardware.md`,
  `architecture/overview.md` (freestanding C decision), H.5/H.6 USB notes
