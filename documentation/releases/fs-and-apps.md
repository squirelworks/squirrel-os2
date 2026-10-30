# In-memory file system + application stubs

- Date: 2026-10-14
- Artifacts: `kernel/pm.asm`, `kernel/boot.asm`
- Features:
  - Flat in-memory file table (`calc`, `sci`, `graph`, `matrix`, `diff`, `topo`, `edit`, `vedit`, `draw`, `help`)
  - Commands: `ls`, `cat <name>`, `run <name>`
  - Application stubs + interactive programs:
    - Basic calculator (`calc`) — interactive integer arithmetic (+ - * / %) 
    - Scientific, graphing, matrix, DiffEq/calculus, topology calculators — scaffolded stubs
    - Text editor (`edit`) — interactive buffer (insert, backspace, enter, Esc)
    - Verbose editor (`vedit`) — same buffer + status prefix
    - Drawing program — prints a small ASCII art
  - Keyboard-driven command line and mode-specific input
- Status: implemented (in-memory only; no persistence yet)

This covers the spirit of 0.2.x (file listing/open) and 0.3.x (application stubs) without a block device.

See `documentation/apps/editors.md` for the two-editor design.
See `documentation/apps/calculators.md` for the calculator suite.
