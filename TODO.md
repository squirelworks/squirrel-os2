# Squirrel-OS/2 task list

Laundry list for the author who opens pull requests. The goals and the milestone
summaries are in [ROADMAP.md](ROADMAP.md). History is in
`documentation/plannedmilestones.md`.

## How to take a task

- Work top to bottom. A task lower on this list waits until the open tasks above it are on `main`, except where a task says it is independent.
- One task, one PR. Branch from current `main`. Do not stack a PR on another feature branch.
- Original code only. Update the design note in the same PR. If the version moves, add `documentation/releases/X.Y.Z.md` and the row in `documentation/releases/PROCESS.md`.
- Check the box in this file in that same PR. If `main` has moved, rebase and keep both edits.
- Behaviour changes get a `check` in `tools/regress.sh` (the screen must contain the expected text). Run `tools/regress.sh` before pushing. Docs-only tasks have a reading check instead.
- New user-visible strings go in `localization/en`, `localization/la`, and `localization/tlh`, then `kernel/strings.inc` is regenerated. `tools/regress.sh` already fails when that file is stale.

## Known bugs

`documentation/knownbugs.md` has **no open defects**. KB-1 through KB-17 are resolved (KB-7 in 0.3.2 / 0.3.3, KB-8 through KB-10 in 0.9.2, KB-11 through KB-15 in 0.9.3, KB-16 after 1.3.3, KB-17 after 1.4.1). Leave those entries in place.

- [x] **KB-16** — A wait that closes a cycle of waits returns −1 instead of panicking the kernel. Check `waitcycle`.
- [x] **KB-17** — A stack overflow is reported and ends only that process, through guard pages and a double-fault task. Checks `stackover`, `stack-shell`.

A new defect that contradicts `documentation/specifications.md` or a milestone gets an entry there and a checkbox in this file, in the same PR that records it. Do not file a bug for an item this list already calls an accepted limit.

## 0.9.3 — Release readiness (done)

Added after the roadmap was written, from the question "has it been run in a VM?". Release note: `documentation/releases/0.9.3.md`.

- [x] **0.9.3-floppy** — Boot from a 1.44 MB floppy image (CHS fallback in the boot sector; KB-11, KB-12). Checks `floppy-boot`, `floppy-data`, `floppy-e820`.
- [x] **0.9.3-cpu** — Say "needs a Pentium-class CPU" and halt instead of crashing (KB-13). Checks `cpu-nopse`, `cpu-nofpu`.
- [x] **0.9.3-calc-hist** — `calc` history at `/calc.hist` (KB-15). Check `calc-hist-root`.
- [x] **0.9.3-planned** — Banner lists `graph`, `diff`, `topo` as planned. Check `ver-planned`.
- [x] **0.9.3-build** — `tools/build.sh`, `tools/run.sh`, `tools/bochs_smoke.sh`, and `documentation/guides/getting-started.md` (QEMU, Bochs, VirtualBox).

## 1.0.0 — Ship the minimal system

Do these first. The release task is last, and only after the others are on `main`.

- [x] **1.0-banner** — Make the boot banner report the current version. Done in 0.9.3: the banner says `0.9.3`, and the `ver-banner` check fails if it does not.
  `banner_rest` in `kernel/pm.asm` said `0.2.3`.
  **Acceptance:** after boot, the VGA screen contains the current version. A new `tools/regress.sh` check fails if it does not. The 1.0.0 release task is what changes the string to `1.0.0`.

- [x] **1.0-spec** — Write the current specification.
  `documentation/specifications.md` stops at 0.0.3 while claiming it is updated with each release.
  **Acceptance:** the file has a 0.9.2 section that a reader can check against the tree: boot to a shell, SQFS (64 entries, 15-character names, paths to 63 characters, no seek), browser, `calc` / `sci` / `matrix`, `edit` / `vedit` (16 KB buffer), ASCII `draw`, loaders, shell (pipes, history, batch), paging, heap, devices, `en`/`la`/`tlh`, crash reports. Limits named in the kernel notes are listed as intentional, including cooperative scheduling, ring 0, no FPU save, and `graph` / `diff` / `topo` still scaffolds. Older sections stay.

- [x] **1.0-docs** — Bring the entry-point docs up to 0.9.2.
  These still send a reader back to 0.0.1 or to unfinished stubs: `kernel/README.md` (next step is a PIT handler), `documentation/architecture/overview.md` ("Current Stage (0.0.1)" and PIT/GDT as next targets), `documentation/apps/calculators.md` (command list still calls `sci` and `matrix` stubs), `documentation/kernel/processes.md` ("one address space", and `sci` listed as a stub), the 0.3.2 line in `documentation/plannedmilestones.md` (vedit numerics "still scaffolded"; `documentation/apps/editors.md` says they ship).
  **Acceptance:** each of those places describes 0.9.2 and points at `ROADMAP.md` for what is next. No code change. `tools/regress.sh` still passes.

- [x] **1.0-walk** — Exercise the 1.0 applications in one boot.
  Existing checks cover `calc`, `edit`, `draw`, and the browser in separate sessions. `documentation/releases/PROCESS.md` wants them checked together.
  **Acceptance:** one new `tools/regress.sh` check, in a single QEMU session, runs `calc` on `2 + 2` (screen contains `= 4`), saves a line from `edit`, quits, `cat`s that file back, opens `draw` and quits, opens `run files` and quits, and the shell still accepts `systest`. The check's expected string is present only if that whole walk happened.

- [x] **1.0-release** — Tag 1.0.0.
  Start only after the four tasks above are on `main`.
  **Acceptance:** `documentation/releases/1.0.0.md` states the minimal-system goal and points at the walk check. The banner says `1.0.0` and the 1.0-banner regression expects `1.0.0`. `PROCESS.md`'s release table and "next planned" line, `documentation/README.md`, and the 1.0.0 bullet in `documentation/plannedmilestones.md` match. `tools/regress.sh` passes.

## 1.0.x — Holes already written down

Each item is its own patch release after 1.0.0 (its own release note). Independent of each other. Stay below the 1.0.0 section: do not start these while a 1.0.0 box is open. They may proceed before 1.1, and 1.1 does not start until **1.0-fpu** is on `main`.

- [x] **1.0-seek** — Add a seek operation on an open file.
  `documentation/kernel/filesystem.md` lists "no seek" as a limit. Reads and writes stay sequential apart from this call.
  **Acceptance:** a program writes `abcd`, seeks to the second byte, reads `bcd`, and prints `seek: PASS`. A `tools/regress.sh` check expects that string. The filesystem note describes the call and drops the "no seek" limit.

- [x] **1.0-errno** — Let a program read why a file call failed.
  Syscalls return −1. The shell prints the reason via `fs_why` (`Not found` is the localized string, not the `error` slot in `fs_errmsg`).
  **Acceptance:** a user program opens a missing name and prints `Not found`, the same words `cat missing` prints. A regression check covers it. `SYS_OPEN` of a directory prints the same reason the shell prints (`Is a directory`). Design note updated.

- [x] **1.0-fpu** — Save and restore the x87 state on a process switch.
  `documentation/apps/calculators.md`: the FPU is not saved, so only one of `sci` or `matrix` may run at a time. Required before preemption.
  **Acceptance:** a program loads a known floating-point value, switches to another process that uses the FPU, switches back, and prints `fpu: PASS` only if the value survived. A regression check expects `fpu: PASS`. The calculator note drops the "only one process" warning.

- [x] **1.0-zombie** — Free a process slot when nobody waits.
  `documentation/kernel/processes.md`: a zombie nobody waits for keeps its slot (`PROC_MAX` is 8). Pids stay unreused.
  **Acceptance:** a program exits children without waiting, more times than there are free slots, then a further spawn still works and `ps` does not fill with zombies. A regression check expects a `PASS` line. The limitation paragraph is updated.

- [x] **1.0-l10n-shell** — Localize the shell's usage lines and file-system errors.
  `documentation/kernel/localization.md`: most messages are still English literals. Keys already exist for some of them.
  **Acceptance:** `lang la` then a bare `mkdir`, and `lang tlh` then a failed `rm` of a missing name, show the Latin and Klingon strings from `localization/`. A regression check expects one of those translated strings. English boot behaviour is unchanged. `strings.inc` is regenerated.

- [x] **1.0-l10n-apps** — Use the existing `calc`, `edit`, and `draw` string keys.
  `localization/README.md` marks those keys "(not yet)".
  **Acceptance:** `lang tlh` then `run calc` shows the Klingon title from the string table, and the same for `edit` and `draw`. A regression check expects one translated title. `strings.inc` is regenerated.

- [x] **1.0-diff-deriv** — Numerical derivative in `diff`.
  `diff` is a scaffold that says the numerical work is pending. Use finite differences on the existing scientific evaluator. No second math library, and no symbolic rules.
  **Acceptance:** `run diff` on a derivative of `sin(x)` at 0 prints a value near 1 (the check can accept `1.000`). The scaffold sentence is gone for this operation. `documentation/apps/calculators.md` describes the input. A regression check covers it.

- [x] **1.0-diff-integ** — Numerical integral in `diff`.
  Start after **1.0-diff-deriv** is on `main`. Trapezoid or Simpson, original code, same evaluator.
  **Acceptance:** integrating a constant `1` from 0 to 2 prints a value near 2. A regression check expects that. The calculator note describes it.

- [x] **1.0-diff-ode** — One ODE stepper in `diff`.
  Start after **1.0-diff-integ** is on `main`. Euler is enough. Runge–Kutta can be a later task if Euler is in.
  **Acceptance:** one step of `y' = y` from `y(0) = 1` prints a value the check can match exactly for a stated step size. A regression check expects it. The note describes the method.

- [x] **1.0-edit-search** — Search in `edit` and `vedit`.
  `documentation/apps/editors.md` lists search under "Not yet".
  **Acceptance:** a file containing `zebra` can be searched, the cursor lands on it, and the message line says so. A regression check expects that message. The "Not yet" line drops search.

- [x] **1.0-edit-undo** — One-level undo in the editors.
  Listed as not yet. One level, not a history stack.
  **Acceptance:** type a character, undo, and the character is gone. A second undo does not erase more. A regression check covers the first undo. The editors note says one-level undo is present.

- [x] **1.0-vedit-controls** — Show control characters in `vedit`.
  Listed as not yet: a display toggle. The buffer contents do not change.
  **Acceptance:** a toggle shows a newline or tab as a visible token on screen, toggling again restores the normal glyph, and a regression check expects the token. The editors note describes the key.

Files larger than 16 KB stay truncated, with the existing warning. That cap belongs in the 1.0 specification, not in a new buffer.

## 1.1 — Preemptive scheduler and threads

Start only after **1.0-fpu** is on `main`. `yield` and `proctest` keep their current results.

- [x] **1.1-preempt** — Switch on a timer tick when another process is ready.
  **Acceptance:** a process that spins without calling `yield` does not block a second process from printing. A regression check expects the second process's line (and still expects `proctest`'s existing line). `documentation/kernel/processes.md` describes the tick path and drops "no preemption".

- [x] **1.1-thread** — Treat a same-address-space spawn as a thread, and test it.
  `proc_spawn` already shares the parent's address space until the loader builds a new one.
  **Acceptance:** a user program spawns an entry in its own image, both sides update one counter, and it prints `thread: PASS`. A regression check expects that. `processes.md` calls this the thread primitive. No second scheduler, and no priority field.

## 1.2 — Messages

- [x] **1.2-queue** — Send and receive a short message between two processes.
  **Acceptance:** a parent sends four bytes, the child prints them, and a regression check expects that text. A full queue returns a documented failure the check also covers. `SYS_GETC` is unchanged.

- [x] **1.2-key-event** — Post a key event as well as delivering `SYS_GETC`.
  Start after **1.2-queue** is on `main`.
  **Acceptance:** a program receives the same character through the queue that `SYS_GETC` would return, prints it, and a regression check expects it. The shell and `keys` checks still pass.

## 1.3 — Graphics primitives

Each command returns to text mode before it prints `PASS`, so the existing screen harness can see the result.

- [x] **1.3-pixel** — Enter a graphics mode, write a pixel, read it back, restore text mode.
  **Acceptance:** a `gfxtest` command prints `gfxtest: PASS` only if the byte read from the framebuffer is the byte written. A regression check expects that, then a later `systest` still passes (text mode is back).

- [x] **1.3-line-fill** — Line and filled rectangle.
  Start after **1.3-pixel** is on `main`.
  **Acceptance:** the self-check reads back a pixel on the line and a pixel inside the rectangle, misses a pixel outside it, and prints `gfxprim: PASS`. A regression check expects that.

- [x] **1.3-text** — Draw a bitmap string in graphics mode.
  Start after **1.3-pixel** is on `main`.
  **Acceptance:** the self-check reads back an ink pixel and a background pixel of a drawn glyph and prints `gfxtext: PASS`. A regression check expects that. The font is original.

- [x] **1.3-graph** — Make `graph` plot a function.
  Start after **1.3-line-fill** and **1.3-text** are on `main`. This is the milestone the `graph` stub names. A text-mode plot before that is not this task.
  **Acceptance:** `run graph` of `y = x` no longer prints `Scaffolded`. A regression check expects a success line from the command. `documentation/apps/calculators.md` describes the keys. `topo` stays a scaffold.

## 1.4 — Window manager

Keyboard only.

- [x] **1.4-create** — Create a window, draw its frame and title, close it.
  **Acceptance:** a test command prints `win: PASS` after creating a window and reading back a frame pixel, and closing removes it (a second read misses that pixel). A regression check expects `win: PASS`. Text mode or the graphics console is left so the shell works.

- [x] **1.4-move-resize** — Move and resize a window.
  Start after **1.4-create** is on `main`.
  **Acceptance:** after a move, the old frame pixel is gone and the new one is present. A regression check expects `winmove: PASS`.

- [x] **1.4-focus** — Two windows, z-order, and keyboard focus.
  Start after **1.4-move-resize** is on `main`.
  **Acceptance:** keys change which window is on top, and a character goes to the focused window's buffer. A regression check expects a line that only the focused window would print.

## 1.5 — Widgets

Start after **1.4-focus** and **1.2-key-event** are on `main`. One widget per PR.

- [x] **1.5-label** — Draw a text label inside a window.
  **Acceptance:** a self-check reads an ink pixel of the label and prints `label: PASS`. A regression check expects it.

- [x] **1.5-button** — A button that activates from the keyboard.
  **Acceptance:** the activation key posts an event and the test prints `button: PASS`. A regression check expects it.

- [x] **1.5-field** — A one-line edit field.
  **Acceptance:** typed characters appear in the field's buffer and the test prints them back as `field: PASS`. A regression check expects that line.

- [x] **1.5-list** — A list that moves a selection with the arrow keys.
  **Acceptance:** Down moves the selection and the test prints the newly selected name. A regression check expects that name.

## 1.6 — Desktop shell

- [x] **1.6-desktop** — Boot to a desktop that lists `files`, `calc`, `edit`, `vedit`, and `draw`.
  **Acceptance:** the screen shows those names, and a regression check expects them. Quitting the desktop reaches the existing shell (`systest: PASS`).

- [x] **1.6-calc** — Open `calc` in a window, evaluate `2 + 2`, close it.
  Start after **1.6-desktop** is on `main`.
  **Acceptance:** the desktop is back afterwards and a regression check has seen `= 4` during the session.

- [x] **1.6-edit** — Open `edit` and `vedit` in a window, type a character, save, close.
  Start after **1.6-desktop** is on `main`.
  **Acceptance:** the saved character is visible to `cat` after the window closes. A regression check expects it.

- [x] **1.6-draw** — Open the ASCII `draw` in a window, plot one cell, save, close.
  Start after **1.6-desktop** is on `main`.
  **Acceptance:** the saved drawing contains that cell and a regression check expects it. Pixel drawing is the next task, not this one.

- [x] **1.6-draw-pixels** — Pixel drawing in `draw`.
  Start after **1.6-draw** and **1.3-line-fill** are on `main`. This is the "Later" section of `documentation/apps/draw.md`.
  **Acceptance:** a stroke sets a pixel the self-check reads back, save/load keeps it, and a regression check expects `drawpx: PASS`.

## 1.7 — Object model

Split from `documentation/plannedmilestones.md` once 1.6 was on `main`. Work top to bottom; each box is one PR and moves the version (1.7.0, 1.7.1, ...). The design note is `documentation/kernel/objects.md`, written with the first box.

- [x] **1.7-class** — Classes and messages: a class has a name, a parent and a method table; an object points at its class; sending a message looks the selector up in the class and then up the parent chain. Kernel routines `obj_class`, `obj_new`, `obj_send` (`kernel/object.asm`). No desktop objects in this PR.
  **Acceptance:** a test command `objtest` defines `Shape` with `name` and `area`, and `Square` under it overriding only `area`; sending `name` to a square runs the inherited method, `area` runs the override, and an unknown selector returns an error instead of crashing. It prints `obj: PASS` and a regression check expects it.
- [x] **1.7-fields** — Instance fields: a class lists its fields by name after its parent's, so a subclass keeps the parent's layout. `obj_get` / `obj_set` by field index, and a lookup by name.
  **Acceptance:** `objtest` sets a field through the parent's method and reads it through the subclass's; it prints `obj fields: PASS` and a regression check expects it.
- [x] **1.7-objs** — A shell command `objs` that lists the classes with their parents and the live objects with their classes. Objects are freed with `obj_free`, and the count goes back down.
  **Acceptance:** a check reads the class tree off the screen, and `mem` shows the same free memory before and after `objtest`.
- [ ] **1.7-desktop** — The desktop's entries become objects: a `Program` class (under a `DesktopObject` class with `name` and `open`) for calc, edit, vedit, draw, and `files`. Enter sends `open` to the selected object instead of reading the `dk_run` table.
  **Acceptance:** every `desktop-*` check still passes, and a new check opens a program through `open` and reads its window.

## 1.8 and after

Do not start these while any box above is open. When 1.7 is on `main`, split the next milestone into PR-sized boxes in this file before writing code. The shapes, from `documentation/plannedmilestones.md`:

- [ ] **1.8-store** — Save that object into SQFS and load it back after a reboot. The regression disk already persists across checks; the check reads the loaded value.
- [ ] **1.9-dnd** — Pick up, move focus, and drop a desktop object from the keyboard. A regression check expects the object's new parent. No mouse.
- [ ] **2.0-net** — Only once 1.9 is on `main`: split basic networking into its own tasks in this file, then implement the first of them (a loopback that a test program can send on and read back).

## Installer (unscheduled)

The author lifted the old gate ("not before the 1.5 and 1.6 boxes above are closed") on 2026-10-31: these boxes now run alongside the 1.x work, and stay out of the desktop and editor files. Each PR carries the OS version it ships in, like any other release (I.1 and I.2 shipped in 1.7.2). Each box is one PR. Design notes go in `documentation/guides/install.md` with the first box. The target is an IDE/ATA disk in BIOS mode; the regression run uses a blank QEMU disk as the target.

- [x] **I.1-target** — Find the target disk, show its size, and refuse to touch the boot disk. Write an MBR partition table with one Squirrel-OS/2 partition.
  **Acceptance:** a regression check reads the table back from the blank disk. Shell commands `install` and `install part` (`kernel/install.asm`); checks `install-list`, `install-esc`, `install-esc-blank`, `install-part`, `install-mbr`, `install-again`, `install-none`.
- [x] **I.2-format** — Format SQFS inside that partition (SQFS learns a starting LBA).
  **Acceptance:** after a reboot, `ls` on the new partition shows an empty root. Shell commands `install format` and `install ls`; the file system reaches its disk through `fs_dev`. Checks `install-fmt-nopart`, `install-ls-nofs`, `install-fmt-esc`, `install-fmt-esc-blank`, `install-format`, `install-sqfs`, `install-ls`, `install-back`.
- [x] **I.3-copy** — Copy the kernel and the sample programs from the boot media onto the target.
  **Acceptance:** a check compares the copied files with the originals. Shell command `install copy`: the kernel to sectors 1 to 192, the data disk's root files into the partition. Checks `install-copy-esc`, `install-copy-esc-blank`, `install-copy`, `install-copied`, `install-after-copy`.
- [ ] **I.4-bootable** — Write the boot sector to the target so the PC boots from it with the stick removed.
  **Acceptance:** QEMU boots from the target disk alone and reaches the shell prompt.
- [ ] **I.5-ui** — A text-mode `install` program that walks through I.1–I.4 with a confirm step before anything is written. Localized like the other programs.
  **Acceptance:** the batch-driven run installs to the blank disk; Esc at the confirm step leaves it blank.
- [ ] **I.6-cd** — Optional: a bootable CD image (El Torito floppy emulation around `floppy.img`) made by `tools/build.sh`.
  **Acceptance:** QEMU boots the `.iso` to the shell.

## Do not schedule

Kept here so they are not added as tasks by accident. Reasons are in `ROADMAP.md`.

- `topo` before 2.x.
- Text-mode `graph` ahead of **1.3-graph**.
- Priority levels inside 1.1.
- A mouse.
- Foreign personalities (F.1 is the first PR of that era, and not before 2.0).
- Porting the full kernel off x86.
- virtio-blk, ATA IRQ, a `/dev` directory, loadable drivers.
- Ring 3 and growing stacks (2.x, per `documentation/kernel/memory.md`).
- Classic OS/2 binary compatibility.

## Modern hardware (unscheduled)

Not before 2.0.0's prerequisites are on `main` (see `ROADMAP.md`). Each box is one PR, and the BIOS boot path and its regression checks keep passing. QEMU covers each one: OVMF for UEFI, `-device ahci`, `-device nvme`, `-device qemu-xhci` with `usb-kbd` and `usb-storage`.

- [ ] **H.1-uefi** — A UEFI loader that reads the memory map, loads the kernel, and enters it with the same handoff as the BIOS path.
  **Acceptance:** QEMU with OVMF boots to the shell prompt.
- [ ] **H.2-gop** — Text console on the UEFI GOP framebuffer (the 1.3 bitmap font), used when VGA text mode is not there.
  **Acceptance:** the UEFI boot prints the banner and a check reads it back from the framebuffer.
- [ ] **H.3-ahci** — AHCI/SATA disk driver registered as `hd0`/`hd1` like the ATA driver.
  **Acceptance:** SQFS mounts and the `persist-*` checks pass on an AHCI disk.
- [ ] **H.4-nvme** — NVMe disk driver behind the same interface.
  **Acceptance:** SQFS mounts and a file written before a reboot reads back after it.
- [ ] **H.5-usb-kbd** — xHCI controller and a USB keyboard feeding the existing `kbd` device.
  **Acceptance:** the shell takes input from `usb-kbd` with no PS/2 keyboard attached.
- [ ] **H.6-usb-storage** — USB mass storage, so the system can boot from and read the stick it was written to.
  **Acceptance:** SQFS on a `usb-storage` disk lists its files.
