# Guides

## Building and running

Requirements: NASM and Python 3 to build; QEMU (or another PC emulator) to run.
The machine needs a Pentium-class CPU (CPUID, FPU, 4 MB pages) and at least 4 MB of memory.

The quick way (0.9.3):

```bash
tools/build.sh          # build/os.img, build/floppy.img, and build/data.img with the sample programs
tools/run.sh            # QEMU: boot os.img with data.img as the data disk
tools/run.sh --floppy   # the same, booting from the floppy image
```

`build/data.img` is only made when it is missing, so what you save survives a rebuild;
`tools/build.sh --fresh` starts a new one. In the OS, type `ls`, `run files`, `run edit notes`,
`run draw pic`, `run calc`, or `run hello world` (a program from the data disk).

Other emulators:

- **Bochs:** `tools/bochs_smoke.sh` boots the image in Bochs (with Bochs's own BIOS),
  runs a scripted session through `autoexec.bat`, reboots and checks the files are still there.
  Its `bochsrc` is a working starting point for an interactive Bochs setup.
- **VirtualBox / VMware:** convert the images first, e.g.
  `VBoxManage convertfromraw build/os.img os.vdi` (and `data.img`), and attach them to an IDE
  controller as primary master and primary slave. Untested so far.
- **Real hardware:** untested. `build/floppy.img` written to a floppy, or `build/os.img` written
  to a disk that the BIOS boots as a hard disk, should work on a PC with a legacy BIOS (not UEFI-only).
- **Installing to a computer's own disk:** the installer is being built step by step; see
  `install.md`.

The manual way:

```bash
cd kernel
nasm -f bin boot.asm -o boot.bin
nasm -f bin pm.asm -o pm.bin
cat boot.bin pm.bin > os.img
qemu-system-i386 -drive format=raw,file=os.img
```

To use the data disk (0.2.0+), attach a second image as primary slave:

```bash
dd if=/dev/zero of=data.img bs=1M count=1
qemu-system-i386 -drive format=raw,file=os.img,index=0,media=disk \
                 -drive format=raw,file=data.img,index=1,media=disk
```

A blank disk is formatted at first boot. To put programs on it from the host (0.4.0+), use
`tools/sqfs.py` (see `kernel/loader.md`):

```bash
nasm -f bin -i programs/ programs/hello.asm -o hello
python3 tools/sqfs.py data.img format 1024
python3 tools/sqfs.py data.img put hello      # then in the OS: run hello world
```

## Regression run

`tools/regress.sh` builds the image and types scripted commands into headless QEMU,
checking the VGA text screen. Needs Python 3 as well. `tools/qemu_screen.py IMAGE KEYS...`
does a single session and prints the screen, which is handy when adding a check.
Uppercase letters and `+ * % ! ? : _` are sent with Shift. In graphics mode the key
`<gfx>` reads the text drawn with the kernel's font off a screen dump (any pixel
offset, any colours) and prints each run of it as a `gfx: ...` line after the text
screen, so a check can look for words in windows (1.6.0).

The hidden shell command `trap` executes `ud2` to show the CPU exception report, and
`overflow` makes the shell run off its own stack to show the stack-overflow report (KB-17).

## Stress run

`tools/soak.py` keeps one QEMU boot busy for a long time and checks that nothing
leaks or breaks: it runs `run stress` five times (threads filling the process table
under preemption, a message ring, a message flood, preempted FPU work, the whole
4 MB heap, thread churn and three programs exec'd at once; see `programs/stress.asm`),
then the three graphics tests ten times while a background thread keeps printing,
then fills `edit` to its 16 KB limit and saves. At the end only the shell may be
left in `ps`, `mem` must report as much free memory as at the start, and `systest`
must pass. `--rounds N` and `--gfx N` make it longer. It prints `soak: PASS` or
`soak: FAIL`. It is not part of `tools/regress.sh`.

`run stress <part>` runs one part on its own: `threads`, `ring`, `flood`, `fpu`,
`heap`, `churn` or `exec`.

## Adding documentation

- Place design notes in `architecture/`.
- Place implementation records in `kernel/`.
- Place how-to material in `guides/`.
- Record version milestones in `releases/`.

Keep entries dated and tied to actual code changes.
