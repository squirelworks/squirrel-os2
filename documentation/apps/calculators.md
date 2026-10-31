# Calculators

Squirrel-OS/2 provides a family of original calculators. All implementations are native. No external math libraries or contemporary calculator code are used.

## Basic Calculator (`calc`)

For taxes, budgeting, and trivial arithmetic.

- Integer arithmetic: addition, subtraction, multiplication, division
- Percentage operator (`%`) for tax and discount calculations
- Interactive line mode: enter an expression, press Enter, see the result
- Clear / quit via Esc or the command `q`
- Status shows last result and operation count
- Suitable for everyday use on the console

Current status (2026-10-30): polished evaluator in `kernel/calc.asm`, running as its own process.

### Expressions

| Input | Meaning | Example → result |
|-------|---------|------------------|
| `+ - * /` | Signed 32-bit integer arithmetic, `* /` before `+ -`, left to right | `2 + 3 * 4` → 14 |
| `( )` | Grouping, nestable | `(2 + 3) * 4` → 20 |
| unary `-` | Negation | `-7 / 2` → -3 (truncates toward zero) |
| `a + b%`, `a - b%` | Add/subtract b percent **of a** (tax, discount) | `100 + 15%` → 115, `100 - 10%` → 90 |
| `a * b%`, `a / b%` | Multiply/divide by b/100 | `200 * 15%` → 30, `50 / 20%` → 250 |
| `a % b` | Binary percent: a × b / 100 (kept from 0.3.1) | `200 % 15` → 30 |
| `ans` | Previous result | `ans * 2` |
| line starting with `+ * / %` or `- ` | Continue from `ans` | after 20: `+ 1` → 21 |

A `%` is postfix when it ends a term (followed by the end of the line, `)` or an operator), otherwise binary.
So `200 % -3` reads as `200% - 3`; write `200 % (-3)` for the binary form.

### Errors

`Error: syntax at column N`, `Error: division by zero`, `Error: overflow` (any intermediate result outside
±2^31, including `a*b` before a percent division), `Error: number too large`.

### Commands at the `calc>` prompt

- `clear` resets `ans` and the count.
- `hist` prints the history file.
- `q` / `quit` / Esc return to the shell.

### History file

With a data disk mounted, every successful line is appended to `calc.hist` as `expression = result`.
It persists across reboots and can also be read with `cat calc.hist` or the file browser.

## Scientific Calculator (`sci`)

For engineering and scientific work. Implemented in `kernel/sci.asm` (0.3.4), running as its own process.

Arithmetic is double/extended precision on the x87 FPU, which the kernel enables at boot (`fpu_init`: CR0.MP and NE set, EM and TS clear, all FPU exceptions masked).
Transcendentals use the FPU's own instructions (`fsin`, `fcos`, `fptan`, `fpatan`, `fyl2x`, `f2xm1`, `fscale`), composed by original code.
The FPU state is not saved on a process switch, so only one process should use floating point at a time. Today that is `sci` or `matrix`.

| Input | Meaning | Example → result |
|-------|---------|------------------|
| numbers | Decimal with optional fraction and exponent | `6.02e23 * 2` → 1.204e24 |
| `+ - * /` | Usual precedence, left to right | `0.1 + 0.2` → 0.3 |
| `^` | Power, right-associative, binds tighter than unary minus | `2 ^ 10` → 1024, `-2 ^ 2` → -4 |
| `( )` | Grouping | `(-2) ^ 3` → -8 |
| `pi`, `e`, `ans` | Constants and the previous result | `ans * 2` |
| `sin cos tan` | Trigonometry, in the current angle mode | `sin(pi / 6)` → 0.5 |
| `asin acos atan` | Inverses, result in the current angle mode | `atan(1)` → 45 in `deg` mode |
| `sqrt ln log exp abs` | Root, natural and base-10 logarithm, e^x, absolute value | `log(1000)` → 3 |

Input can come from a file or pipe (`run sci < sums`), one expression per line (0.5.0).

Commands: `deg` / `rad` switch the angle mode (shown in the prompt, `rad` at first boot); `q`, `quit` or Esc return to the shell.

Results show up to 10 significant digits, in plain notation for 1e-6 ≤ |x| < 1e15 and as `d.ddde±n` otherwise.

Errors: `syntax at column N`, `division by zero`, `overflow` (result beyond the double range) and `outside the function domain` (`sqrt(-1)`, `ln(0)`, `asin(2)`, a negative base with a fractional power, `0 ^ 0`).

## Graphing Calculator (`graph`)

For visualization of functions.

- Plot y = f(x) over a range in text mode or later VGA graphics
- Zoom and pan
- Multiple functions
- Points and asymptotes indicated

Scaffolded (listed as "planned" in the banner since 0.9.3). Depends on graphics primitives (milestone 1.3) and a function evaluator.

## Matrix Calculator (`matrix`)

For linear algebra. Implemented in `kernel/matrix.asm` (0.3.4), using the same FPU setup and number formatting as `sci`.

- Variables `A`–`Z` plus `ans`, each up to 6×6 doubles. Stored at `0x50000` and kept while the system runs.
- `A = [1 2; 3 4]` defines a matrix. Rows are separated by `;` and entries by spaces or commas; negative and decimal entries are allowed.
- A line without `NAME =` stores its result in `ans`. Every result is printed (a 1×1 result as a single number).

| Input | Meaning |
|-------|---------|
| `A + B`, `A - B` | Element-wise, same size required |
| `A * B` | Matrix product (columns of A = rows of B) |
| `2 * A`, `A * 0.5` | A 1×1 operand (a plain number) scales the other side |
| `-A` | Negation |
| `det A` | Determinant (Gaussian elimination with partial pivoting) |
| `trans A` | Transpose |
| `inv A` | Inverse (Gauss–Jordan with partial pivoting) |
| `( )`, literals inline | `det [2 0; 0 3]`, `inv (A * B)` |

Commands: `list` shows the defined matrices and their sizes, `clear` forgets them all, and `q`, `quit` or Esc quits.

Errors: `matrix sizes do not match`, `matrix is not square`, `matrix is singular` (a pivot below 1e-12), `rows have different lengths`, `larger than 6x6`, `undefined matrix`, `expression too complex` (more than 64 intermediate results) and `syntax at column N`.

When a matrix is printed, rounding noise below 1e-10 shows as 0 (so `A * inv A` prints the identity). Columns are right-aligned to 13 characters.

## Differential Equations and Calculus Calculator (`diff`)

For derivatives, integrals, and ordinary differential equations.

- Symbolic or numerical differentiation (finite differences, or later symbolic rules)
- Numerical integration (trapezoid, Simpson — original)
- Simple ODE solvers (Euler, Runge-Kutta, original)

Scaffolded. Builds on the scientific evaluator and numerical methods written in-house.

## Topology Calculator (`topo`)

For algebraic and point-set topology experiments.

- Simplicial complex entry
- Homology group computation (over ℤ/2 or small fields, original chain complex reduction)
- Betti numbers
- Fundamental group sketches for simple spaces

Scaffolded. Long-term; requires symbolic algebra primitives and careful memory management. Not expected before 2.x.

## Design Notes

- All calculators share a common input buffer and expression parser where possible
  (`calc.asm`'s recursive-descent parser is the starting point for `sci` and `matrix`).
- The basic calculator is usable today; the others are progressive enhancements.
- No code is copied from external sources.
- Integration path: console apps now, windowed desktop objects in 2.0.

## Commands

```
run calc      # interactive basic
run sci       # scientific stub
run graph     # graphing stub
run matrix    # matrix stub
run diff      # calculus / DiffEq stub
run topo      # topology stub
```

See `documentation/plannedmilestones.md` for the schedule.
