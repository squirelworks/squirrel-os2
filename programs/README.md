# Programs

Original user programs for the program loader (0.4.0). They are separate files on the data disk,
not part of the kernel image. See `documentation/kernel/loader.md`.

| File | Format | What it does |
|------|--------|--------------|
| `hello.asm` | SQX | Greets and echoes its argument (`run hello world`) |
| `wc.asm` | SQX | Lines, words and bytes of a file (`run wc notes`), or of its input (`ls \| run wc`) |
| `elfhello.asm` | ELF32 | Hand-written ELF header; checks its bss is zeroed |
| `ls.asm` | SQX | Lists the disk with sizes; `run ls txt` filters by substring |
| `cat.asm` | SQX | Prints one or more files (`run cat a b`), or copies its input |
| `nest.asm` | SQX | Runs `hello` from inside itself, waits, then checks its own memory survived (0.6.1) |
| `crash.asm` | SQX | Reads unmapped memory: the fault ends only this program (0.6.1) |
| `heap.asm` | SQX | Grows its heap by 1 MB with `SYS_SBRK`, checks it, gives it back (`run heap`, `run heap after`, `run heap keep`) (0.6.2) |
| `fpu.asm` | SQX | Keeps a value on the FPU stack while a second copy of itself fills all eight registers, then checks it (`run fpu`, 1.0.1) |
| `seek.asm` | SQX | Writes `abcd`, seeks to the second byte and reads `bcd`; checks a seek past the end is refused (`run seek`, 1.0.2) |
| `errno.asm` | SQX | Opens its argument; on failure prints the reason from `SYS_FSERROR` (`run errno missing` → `errno: Not found`, 1.0.3) |
| `zombie.asm` | SQX | Starts 12 threads it never waits for, then one it does; spawning must keep working (`run zombie`, 1.0.4) |
| `stress.asm` | SQX | Stress test of processes, threads, messages, preemption, the FPU, the heap and exec; every part checks its result (`run stress`, `run stress ring`; used by `tools/soak.py`) |
| `waitcycle.asm` | SQX | Waits for the shell, and closes a cycle of waits with a thread; the wait that closes a cycle must return −1, not hang the kernel (`run waitcycle`, KB-16) |
| `stackover.asm` | SQX | Starts a thread that overflows its stack; the kernel must end only that thread, and the program's own memory and stack must be intact (`run stackover`, KB-17) |
| `devtest.asm` | SQX | Uses devices by name: writes through `con`, reads `hd1`, checks `hd0` refuses writes (0.7.x) |
| `udptest.asm` | SQX | Sends a UDP datagram to 127.0.0.1 and reads it back; a second process is refused that port (`run udptest`, 1.9.7) |
| `sqx.inc` | — | SQX header macro and syscall numbers |

Build and install:

```bash
nasm -f bin -i programs/ programs/hello.asm -o hello
python3 tools/sqfs.py data.img put hello
```
