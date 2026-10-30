# Android personality (scaffold)

Special case. Android userland is built on a Linux kernel ABI plus Bionic and the ART runtime.

## Possible future paths

1. ELF/Bionic translation (NDK binaries) on top of the linux personality.
2. A managed ART-compatible runtime written originally (large effort).
3. Lightweight container-style isolation of a Linux personality plus Android libraries.

Not on the critical path for 3.0. Console/NDK tools first if pursued.

Status: directory only.
