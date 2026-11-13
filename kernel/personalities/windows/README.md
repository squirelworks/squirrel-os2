# Windows personality

Win32 PE32 console programs (P.5) run through `programs/winrun.asm`, an ordinary SQX program:
the PE loader (headers, sections, base relocations, import binding) and a stdcall KERNEL32 shim
live there, not in the kernel. The kernel loader only hands every `MZ` file to `winrun`.
Imports without a shim are bound to a stub that names them when called.

Test: `programs/winhello.asm`, a hand-written PE32. Details and the shim table:
`documentation/architecture/foreign-compatibility.md`.

Next: P.6 (USER/GDI onto the window manager), P.7 (PE32+). Public format descriptions only; no
ReactOS or Wine sources.
