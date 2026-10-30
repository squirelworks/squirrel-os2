# Programs

Original user programs for the 0.3.0 program loader. They are separate files on the data disk,
not part of the kernel image. See `documentation/kernel/loader.md`.

| File | Format | What it does |
|------|--------|--------------|
| `hello.asm` | SQX | Greets and echoes its argument (`run hello world`) |
| `wc.asm` | SQX | Lines, words and bytes of a file (`run wc notes`) |
| `elfhello.asm` | ELF32 | Hand-written ELF header; checks its bss is zeroed |
| `sqx.inc` | — | SQX header macro and syscall numbers |

Build and install:

```bash
nasm -f bin -i programs/ programs/hello.asm -o hello
python3 tools/sqfs.py data.img put hello
```
