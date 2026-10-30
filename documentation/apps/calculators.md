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

For engineering and scientific work.

- Floating-point arithmetic (when FPU support arrives)
- Trigonometric functions (sin, cos, tan and inverses)
- Logarithms and exponentials
- Constants (π, e)
- Degree / radian modes

Scaffolded. Requires floating-point unit integration and transcendental approximations (Taylor series or minimax, original implementations).

## Graphing Calculator (`graph`)

For visualization of functions.

- Plot y = f(x) over a range in text mode or later VGA graphics
- Zoom and pan
- Multiple functions
- Points and asymptotes indicated

Scaffolded. Depends on graphics primitives (milestone 1.3) and a function evaluator.

## Matrix Calculator (`matrix`)

For linear algebra.

- Matrix entry and display
- Addition, subtraction, multiplication
- Determinant, inverse, transpose
- Solve linear systems (Gaussian elimination, original)

Scaffolded. Requires dynamic allocation or fixed-size buffers and floating-point.

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
