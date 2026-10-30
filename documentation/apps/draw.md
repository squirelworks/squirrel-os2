# Drawing Program

Squirrel-OS/2 provides an original drawing program. All code is native to the project. No external graphics libraries or contemporary drawing tools are used.

## Current Stage — ASCII drawer only

While the GUI is unfinished, the drawing program is an ASCII drawer and nothing more. It runs entirely in VGA text mode on a fixed character canvas. No pixel graphics, no framebuffer drawing, and no mode-13h or linear-framebuffer paths exist yet.

This matches the present kernel (console, keyboard ISR, no windowing system).

### Features (basic interactive)

- Fixed canvas (32 columns × 10 rows of characters)
- Movable cursor via arrow keys (clamped to canvas)
- Plot character (default `*`) with Space
- Erase with `x` or Backspace
- Clear canvas with `c`
- Status line showing cursor position
- Esc to exit back to the command prompt
- Redraws the canvas after each change

### Commands

```
run draw
```

### Design Notes

- Canvas is stored in a fixed buffer (`draw_canvas`).
- Cursor position is tracked separately (`draw_cx`, `draw_cy`).
- Uses the existing keyboard ISR path and VGA text output (same style as the editors and calculator).
- Suitable for simple diagrams, sketches, and ASCII art.
- Load/save of the canvas to the in-memory file system is the next small step inside this ASCII stage.

## Later (after GUI exists)

Pixel drawing, freehand, lines, rectangles, fills, and save-as-bitmap wait for the graphics primitives and window manager (milestones 1.3–1.4 and beyond). Until those land, `draw` remains the ASCII canvas above.
- Integration as a desktop object once the window manager exists (milestone 1.4+)

## Related

- Kernel integration: `kernel/pm.asm` (`run_draw`, draw mode in keyboard ISR)
- Milestone: 0.3.3 in `documentation/plannedmilestones.md`
