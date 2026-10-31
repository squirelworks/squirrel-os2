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
Since 1.0.1 every process has its own x87 registers: the kernel saves them on each process switch (`processes.md`), so `sci`, `matrix` and programs can all use floating point at once.

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

For derivatives, integrals, and ordinary differential equations, done numerically (`kernel/diff.asm`). The function is an ordinary `sci` expression in the variable `x`. It is evaluated again at every sample point, so every `sci` function and constant works in it. There is no symbolic algebra.

```
Calculus Calculator (Esc to exit)
diff> d sin(x) at 0
= 1
diff> d x^3 at 2
= 12
diff> d exp(x) at 1
= 2.718281829
diff> i sin(x) from 0 to pi
= 2
diff> i exp(x) from 0 to 1
= 1.718281828
diff> euler y from 0 to 0.1 y0 1 step 0.1
= 1.1
diff> euler y from 0 to 1 y0 1 step 0.001
= 2.716923932
```

- **Derivative** (1.0.7): `d <f(x)> at <x0>`. It uses the central difference (f(x0+h) − f(x0−h)) / 2h, with h = 10⁻⁵·max(1, |x0|). The method's error shrinks with h², and the FPU's 64-bit mantissa keeps rounding error far below the 10 digits that are printed. Polynomials up to degree 2 come out exact, and smooth functions are right to about 10 digits.
- **Integral** (1.0.8): `i <f(x)> from <a> to <b>`. It uses the composite Simpson rule on 1000 panels, (h/3)·(f₀ + 4f₁ + 2f₂ + … + 4f₉₉₉ + f₁₀₀₀) with h = (b − a)/1000. Each sample point is computed as a + i·h, not as a running sum. The error shrinks with h⁴, so polynomials up to degree 3 come out exact, and smooth functions are right to the 10 printed digits. If `b < a`, the result is negative. There is no special handling for improper integrals: `i ln(x) from 0 to 1` samples ln(0) and reports `outside the function domain`.
- **ODE** (1.0.10): `euler <f(x,y)> from <x0> to <x1> y0 <y0> step <h>` solves y′ = f(x, y) with y(x0) = y0, and prints y(x1).
  - It uses Euler's method, yₖ₊₁ = yₖ + h·f(xₖ, yₖ), with xₖ = x0 + k·h.
  - It takes n = round(|x1 − x0| / h) steps, at least one when x1 ≠ x0. The step is then set to (x1 − x0)/n, so the last step lands exactly on x1. It can also run backwards, when x1 < x0.
  - Euler is first order: its error shrinks with h, not h². The y′ = y example gives 2.716923932 for e = 2.718281828 with h = 0.001. One step of y′ = y from y(0) = 1 with h = 0.1 gives exactly 1.1.
  - `step` must be greater than 0, and at most 100000 steps are allowed.
  - `y` exists only inside `euler`. In `d` and `i` it is a syntax error.
  - Runge–Kutta could be a later task.
- `x0`, `x1`, `y0`, `h`, `a` and `b` are plain `sci` expressions (`pi / 2`, `sqrt(2)`), but it may not use `x`.
- Angles are always radians in `diff`, whatever mode `sci` was left in.
- Errors are the same as in `sci`. A sample point outside the domain gives `outside the function domain` (`d ln(x) at 0` samples −10⁻⁵). A missing `at`, `from`, `to`, `y0` or `step` gives `syntax at column N`.
- `x` is a syntax error in `sci` itself.
- `q`, `quit` or Esc quits.


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
run calc      # basic: integer arithmetic and percentages
run sci       # scientific: floating point and functions (x87)
run matrix    # matrices up to 6 x 6
run graph     # scaffold: prints a message (needs graphics, milestone 1.3)
run diff      # scaffold: prints a message (TODO.md 1.0-diff-*)
run topo      # scaffold: prints a message (2.x)
```

See [`../../ROADMAP.md`](../../ROADMAP.md) and [`../../TODO.md`](../../TODO.md) for what is next.
