# Personalities — Foreign Application Layers

Each subdirectory implements one foreign personality (binary loader hooks + ABI/API translation) that maps onto the native Squirrel syscall and process model.

All code in this tree is original. No external OS sources are copied.

## Layout

- `common/` — shared helpers (format detection, process setup, mapping utilities)
- `windows/` — PE loader + Win32/Win64 translation
- `linux/` — ELF loader + Linux syscall ABI
- `darwin/` — Mach-O loader + Darwin/XNU translation
- `unix/` — POSIX / System V variants (shares heavily with linux)
- `android/` — Bionic / ART path (later)
- `ios/` — restricted Darwin/iOS path (research)

See `documentation/architecture/foreign-compatibility.md` for the overall design.

Status: scaffold only.
