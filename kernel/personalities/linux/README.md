# Linux personality

Runs static Linux i386 ELF32 programs (P.1, P.2). Original code.

- `linux.asm` (included from `pm.asm`): `lx_start` builds the Linux initial stack
  (argc, argv, envp, auxv); `lx_isr` translates Linux `int 0x80` calls (`exit`, `exit_group`,
  `read`, `write`, `open`, `close`, `lseek`, `getpid`, `brk`, `mmap`, `mmap2`, `munmap`) onto
  native services, other numbers return `-ENOSYS`.
- The loader (`kernel/loader.asm`) marks an ELF with `EI_OSABI = 3` as Linux by setting
  `PCB_LINUX` to its entry point.
- Tests: `programs/lxhello.asm`, `programs/lxfile.asm`, `programs/lxcat.asm`.

The full table, the fd and memory mapping, and what is missing are in
`documentation/architecture/foreign-compatibility.md`. Shares infrastructure with the `unix`
personality (P.10) where practical.
