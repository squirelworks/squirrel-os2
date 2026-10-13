# Squirrel-OS/2

An original operating-system effort in the spirit of OS/2 Warp.

All material under this tree is project-native.  
Third-party and contemporary sources remain outside this directory.

## Layout

```
squirrel-os2/
├── README.md
├── documentation/          ← ongoing project documentation
│   ├── architecture/
│   ├── kernel/
│   ├── guides/
│   └── releases/
├── kernel/                 ← original kernel code
│   └── boot.asm
└── docs/                   (legacy pointer; prefer documentation/)
```

## Documentation

See `documentation/README.md` for the living documentation set.

## Current milestone

Boot sector 0.0.1 — firmware hand-off, VGA text output, periodic beep.  
Details in `documentation/releases/0.0.1.md`.
