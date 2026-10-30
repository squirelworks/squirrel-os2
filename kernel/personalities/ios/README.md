# iOS personality (placeholder)

Extremely constrained. Modern iOS binaries require code signing, entitlements, and a closed framework set.

## Possible long-term approaches

- Research-only Mach-O loader for unsigned or specially prepared binaries.
- Full user-mode emulation of an older iOS environment (heavy).
- Explicitly out of scope until the Darwin personality and sandboxing are mature.

Status: placeholder directory only. No implementation planned in the near term.
