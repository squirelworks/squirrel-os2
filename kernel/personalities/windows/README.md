# Windows personality (scaffold)

Maps PE/PE32+ binaries onto the native Squirrel process model.

## Planned scope (incremental)

1. Console subsystem: `WriteFile` / `ReadFile` / `ExitProcess` and a handful of kernel32 calls.
2. Basic file and process APIs.
3. Later: graphics mapping onto the Squirrel desktop (not a full Win32 GDI peer).

## Notes

- Calling convention and structure layouts must be documented from public headers only.
- No ReactOS or WINE sources.
- Prefer native x86_64 execution; cross-arch translation is out of scope for the first implementation.

Status: directory only.
