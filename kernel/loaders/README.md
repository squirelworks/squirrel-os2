# ELF loader stub

Minimal original ELF parser and Linux personality entry stub.

## Files

- `elf_stub.asm` — 32-bit ELF magic/header/PT_LOAD validation + Linux syscall trampoline stub

## What it does today

- Validates ELF magic, class, type, machine
- Walks program headers and counts PT_LOAD segments
- Returns a status code
- Provides a placeholder Linux syscall trampoline for `write` and `exit`

## What it does not do yet

- Allocate or map address space
- Copy segments
- Set up Linux-style stack (argc/argv/envp/auxv)
- Actually transfer control to the entry point
- Translate more than two syscalls
- Handle ELF64 fully
- Dynamic linking or interpreter (PT_INTERP)

## Integration

The native loader that actually runs programs (SQX flat binaries and static ELF32) is
`kernel/loader.asm`, added in 0.4.0 (`documentation/kernel/loader.md`). This stub stays the
design sketch for the Linux personality (Linux ABI, syscall translation).


Intended to be called once a native process model and memory allocator exist.
Can be assembled independently or included from the main kernel when ready.

See `documentation/architecture/foreign-compatibility.md` for the surrounding design.
