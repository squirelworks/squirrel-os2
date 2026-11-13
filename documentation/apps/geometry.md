# Geometry (C.6)

`run geometry [file]` draws constructions that stay true when their points move. It is a program on the data disk (`programs/geometry.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`). The canvas on the left shows the axes and a unit grid (20 pixels a unit at first). The list on the right shows each object with its numbers. Without a name the drawing saves as `drawing.geo`.

## Objects

Free points can be moved; everything else is worked out from its parents again after every change, in the order it was made:

| Command | Object |
|---------|--------|
| `(x, y)` | a free point (x and y may be any `sci` expression: `(sqrt(2), pi/4)`) |
| `mid A B` | the midpoint of A and B |
| `seg A B` | the segment AB |
| `line A B` | the line through A and B |
| `perp l A` | the perpendicular to the line (or segment) l through A |
| `par l A` | the parallel to l through A |
| `bis A B` | the perpendicular bisector of AB |
| `abis A B C` | the bisector of the angle ABC (at B) |
| `circle A B` | the circle with centre A through B |
| `circle A r` | the circle with centre A and radius r (a number or expression) |
| `inter o p` | where two lines, segments or circles meet: one point for two lines, two for a circle |
| `dist A B` | the distance AB |
| `angle A B C` | the angle ABC at B, in degrees (0 to 180) |
| `area A B C` | the area of the triangle ABC |
| `del X` | remove X and everything built on it |

`N=` in front of a command names the object (`P=(1,2)`, `K=mid A B`; up to 7 letters and digits, case matters). Otherwise points get the next free letter (A, B, …, then P1, P2, …). Segments are named s1, s2, …, other lines l1, l2, …, circles c1, … and measurements m1, ….

An intersection on a segment exists only where the segment is. An object whose parents do not meet (parallel lines, circles apart, a point past a segment's end) is listed as `?` and not drawn, until its parents move so that it exists again.

In the list, points show their coordinates (`D (-1.9365, 3.5)`), segments their length, lines their slope (or `vertical`), circles their radius, and measurements their value (`m2 = 90 deg`).

## Keys and mouse

| Key | Action |
|-----|--------|
| any character | start a command on the status row (Enter runs it, Esc drops it, Backspace corrects) |
| Enter | start an empty command |
| left click on the canvas | a new free point there; on a free point: select it |
| drag | move the selected free point |
| Tab | select the next free point (its name turns red in the list, a box marks it) |
| arrows | move the selected point by 0.25 |
| + / - | zoom in / out |
| Home | the first view |
| Backspace | remove the last object |
| Delete | remove the selected point and everything built on it |
| Ctrl+S | save |
| Esc | quit |

A command that cannot be done leaves a message on the status row, for example `That name is taken`, `Those are not the right kinds of object` (`perp A B` with a point for the line), or the list of commands for an unknown one.

## Files

A drawing is saved as text, one named command a line (`A=(0,0)`, `k=circle C 2`, `D=inter1 c1 k`), with free points at 10 significant digits. Opening a file runs its lines as commands. `inter1` and `inter2` make one of the two meeting points.

## Self-check

`run geometry test` covers these cases:

- a 3-4-5 triangle: its distance, its 90° angle, its area 6;
- every construction, and intersections of lines, a segment with a circle (one point off the segment), two circles, and parallel lines (none);
- a point moved with Tab and the arrows, with the measurements and the midpoint following it;
- a circle and a free point read back from the screen;
- removing a point together with everything built on it;
- error messages;
- a save and load.

It prints `geometry: PASS`, or `geometry: FAIL` and a letter for the first check that failed.

Checks: `geometry`, `geometry-cmds` (a figure typed as commands), `geometry-move`, `geometry-err`, `geometry-save` (shown with `cat`), `geometry-quit`.
