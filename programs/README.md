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
| `sqx.inc` | — | SQX header macro and syscall numbers |

Build and install:

```bash
nasm -f bin -i programs/ programs/hello.asm -o hello
python3 tools/sqfs.py data.img put hello
```
