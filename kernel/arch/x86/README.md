# x86 early kernel

Implemented in `early.asm`.

Protected-mode entry, VGA banner, halt.  
The full kernel with file system and applications remains in `../../pm.asm`.

```bash
nasm -f bin early.asm -o early-x86.bin
qemu-system-i386 -drive format=raw,file=early-x86.bin
```
