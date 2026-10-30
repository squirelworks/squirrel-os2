# Linux personality (scaffold)

Maps ELF binaries that use the Linux syscall ABI onto native Squirrel services.

## Planned first subset

- Static ELF loader (stub exists: `kernel/loaders/elf_stub.asm`)
- Syscalls: `read`, `write`, `open`/`openat`, `close`, `exit`/`exit_group`, `brk`/`mmap` (minimal), `getpid`
- Console and simple file I/O sufficient to run many small Unix tools

Shares infrastructure with the `unix` personality where practical.

Status: ELF validation stub implemented; mapping and real translation pending (see plannedmilestones F.1–F.4).
