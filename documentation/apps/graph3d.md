# 3D Grapher (C.7)

`run graph3d [function]` draws a surface or a curve in space. It is a program on the data disk (`programs/graph3d.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`), and evaluates with the kernel's `sci` engine through `GUI_EVAL` (x and y as variables), so a function takes everything `sci` takes.

## Functions

| Typed | Kind |
|-------|------|
| `z = sin(x)*cos(y)`, or just `sin(x)*cos(y)` | a surface over the square −d ≤ x, y ≤ d (d = 3 at first) |
| `x = cos(t), y = sin(t), z = t/5` | a curve, t from 0 to 2π in 240 steps |

A `t` that stands alone in a curve is the parameter (`tan` and `sqrt` are not touched). A syntax error is reported on the status row (`Error: syntax at column 4`) and the function stays in the editor.

A surface is evaluated on a 21 × 21 grid and drawn as 400 quadrilaterals (two filled triangles each), sorted by the depth of their centres and drawn farthest first, so nearer parts hide the ones behind (the painter's algorithm). Each is filled in the colour of its mean height on a 32-step ramp from blue (lowest) through cyan, green and yellow to red (highest), set in VGA DAC entries 64–95 with `GUI_PALETTE`, and edged in dark grey. Points where the function is undefined or larger than 10³⁰ leave out the quadrilaterals around them. x and y are scaled to the square and z to its range, so any function fills the picture. A light grey square under it marks the floor, with `x` and `y` at the ends of the positive axes.

A curve keeps one scale on all three axes (the largest of its ranges), so a circle stays round; each piece is coloured by its height.

The status row shows the ranges: `x, y: -3 to 3  z: -0.9975 to 0.9975`, or `t: 0 to 2 pi  z: 0 to 1.2566`.

## Keys

| Key | Action |
|-----|--------|
| Left / Right | turn about the z axis by 15° |
| Up / Down | look from higher or lower, by 10°, from 0° (side on) to 90° (straight down) |
| `+` / `-` | zoom in / out (1.25 times) |
| PgUp / PgDn | twice / half the square (d) |
| Home | the first view: turned 30°, from 25° above, no zoom |
| `w` | edges only (a wireframe in blue), and back |
| Enter | edit the function on the function row (Enter draws it, Esc leaves it as it was) |
| Esc | quit |

## Projection

A point (x, y, z), scaled to about −1…1, is turned by the angle a about the z axis: x′ = x cos a − y sin a, y′ = x sin a + y cos a. Seen from the elevation e, the screen has x′ across and z cos e + y′ sin e up; the depth is y′ cos e − z sin e. The projection is parallel (no perspective).

## Self-check

`run graph3d test` draws z = x² + y² and checks that z runs from 0 to 18 over −3…3; that looking straight down the corner (3, 3) lands up and to the right of the centre; that the middle of the bowl is coloured on the screen; that the helix x = cos t, y = sin t, z = t/5 has a z range of 2π/5 and its start reaches the screen; that turning by 90° moves it; and that `z = x*(` is a syntax error. It prints `graph3d: PASS`, or `graph3d: FAIL` and a letter for the first check that failed.

Checks: `graph3d`, `graph3d-surf`, `graph3d-curve`, `graph3d-size`, `graph3d-syn`, `graph3d-quit` (wireframe, then Esc).
