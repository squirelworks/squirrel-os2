# Darwin / macOS personality (scaffold)

Maps Mach-O binaries onto the native Squirrel process model.

## Notes

- Start with console tools that use a small set of XNU syscalls.
- Higher-level frameworks (Cocoa, Foundation, etc.) are deferred; they require substantial original reimplementation or are out of scope.
- Code signing and entitlements are research topics; early work ignores them.

Status: directory only.
