# Grapher (C.2)

`run grapher [function]` is a 2D graphing calculator in a full-screen window. It is a program on the data disk (`programs/grapher.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`), and evaluates with the kernel's `sci` engine through `GUI_EVAL`, so a function takes everything `sci` takes: `+ - * / ^`, parentheses, `pi`, `e` and `sin cos tan asin acos atan sqrt ln log exp abs`, in radians. It is the C.2 successor of the built-in `graph` (`calculators.md`), which stays until it is retired.

## Functions

Up to four at once, each in its own colour (blue, red, green, magenta). The function row under the plot shows the current one with its colour.

| Typed | Kind |
|-------|------|
| `y = x^2 - 1`, or just `x^2 - 1` | explicit, evaluated at every column of the plot |
| `r = 1 + cos(t)` | polar, t from 0 to 2π in 240 steps |
| `x = 4*cos(t), y = 2*sin(t)` | parametric, t from 0 to 2π in 240 steps |
| `x^2 + y^2 = 25`, `y^2 = 1/x`, `x = 3` | implicit: any other equation in x and y |
| `y < x`, `x^2 + y^2 >= 4` | inequality (`<`, `>`, `<=`, `>=`): the region where it holds is shaded |

An implicit curve is drawn where F = lhs − rhs is zero: F is sampled every second pixel, each grid edge where it changes sign gets a zero by linear interpolation, and the zeros on the edges of each grid cell are joined. A zero is kept only if F there is under half the larger of the two samples, so a pole, where F jumps through infinity (`y^2 = 1/x` at x = 0), is not drawn. An inequality shades the grid points where it holds with a dot every other pixel in each direction, on white pixels only, so axes and other curves stay visible; its boundary is drawn like an implicit curve, dashed for `<` and `>`. Roots, extrema, intersections and trace are for y =, r = and x =, y = functions.

`a`, `b` and `c` standing alone are sliders, each 1 at the start and from −10 to 10 in steps of 0.01: `y = a*sin(b*x)`, `x^2/a^2 + y^2/b^2 = 1`. Their values go into the functions as numbers, so moving a slider redraws every function that uses it.

A `t` that stands alone is the parameter (`tan` and `sqrt` are not touched). Points where a function is undefined (`sqrt(x)` for x < 0, `1/x` at 0) are left out, and two neighbouring points more than the plot's height apart are not joined, so `tan(x)` shows no vertical lines at its poles. A syntax error is reported on the status row (`Error: syntax at column 4`) and the function stays in the editor.

## Keys

| Key | Action |
|-----|--------|
| Enter | edit the current function on the function row (Enter plots it, Esc leaves it as it was) |
| Tab | the next function slot |
| Delete | remove the current function |
| `+` / `-` | zoom in / out (half or twice the ranges, about the centre) |
| arrows | pan a quarter of the view |
| Home | the standard window, x and y from −10 to 10 |
| left click | centre the view on that point |
| `t` | trace: a cross on the current curve, its coordinates on the status row (`x=… y=…`, with `t=…` first for polar and parametric). Left and Right move along the curve one column or one t step; Up and Down go to the next function; Esc ends tracing |
| `z` | roots of the current function in view: `roots: -9.4248  -6.2832 …` |
| `m` | minima and maxima in view: `min(-7.854, -1)  max(-4.7124, 1) …` |
| `i` | where the current function meets the next explicit one: `meet: (-1, 0)  (2, 3)` |
| `a` / `b` / `c` | choose that slider: the status row shows `a = 1` and its bar. Left and Right change it by 0.1, Up and Down by 1, a click or drag on the bar sets it, another of `a`, `b`, `c` switches, Esc or Enter ends |
| Esc | quit |

Found points are marked with small black squares and listed on the status row as far as it reaches (up to eight are kept). Numbers there are rounded to a hundred-thousandth of the view's scale (6.2832 in the standard window). `z`, `m` and `i` work on explicit functions.

How they are found: the function (for `m` its slope, f(x + d) − f(x − d); for `i` the difference f − g) is evaluated at every column of the plot; each sign change is narrowed by 60 halvings. A sign change across a pole is dropped, because the value there does not come near zero.

The axes are dark grey with a tick at every power of ten that gives about 6 to 60 ticks across the view.

## Self-check

`run grapher test` plots y = x² − 1 and reads back from the screen the pixel where the curve crosses x = 0 (the first slot's colour) and one off the curve (white); it finds the roots −1 and 1, the minimum (0, −1), and with y = x + 1 in the second slot the meeting points x = −1 and 2; it plots the polar circle r = 2 and reads its colour back at (2, 0); the implicit circle x² + y² = 25 at (5, 0) and (0, −5); the shading of y < x at (5, −5) and none at (−5, 5); and y = a·x with the slider a at 2 at (2, 4). It prints `grapher: PASS`, or `grapher: FAIL` and a letter for the first check that failed.

Checks: `grapher`, `grapher-roots`, `grapher-ext`, `grapher-meet`, `grapher-trace` (a parametric ellipse, one step), `grapher-zoom`, `grapher-syn`, `grapher-quit`, `grapher-impl` (an implicit circle; `z` says it is for y = f(x)), `grapher-ineq` (trace refuses an inequality), `grapher-slider` (a moved to 2.2), `grapher-form` (`y < x < 2` is refused).

Editing redraws only the function and status rows, so typing stays quick with implicit curves on screen (one implicit curve takes about a fifth of a second to draw under QEMU).

## Not yet

Tables of values belong to C.3 (`../../ROADMAP.md`).
