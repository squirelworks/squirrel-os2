# CAS (C.5)

`run cas` is a small computer algebra system: it works with formulas in `x` exactly, as fractions, roots and symbols, and falls back to numbers only where it has to. It is a program on the data disk (`programs/cas.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`). It is a console: type a line, press Enter, and the answer appears below it.

## Input

Numbers are exact: `2/4 + 1/3` gives `5/6`, and `1.25` is `5/4`. Write `*` and `/`, or leave the `*` out (`2x`, `3(x+1)`, `x sin(x)`). `^` is a power. The constants are `pi` and `e`. The functions are `sin cos tan asin acos atan exp ln log abs sqrt` (`log` is `ln`). Any single letter is a variable; `x` is the one that the commands below work on. `ans` is the last answer.

A line that is not a command is simplified: like terms and powers are collected, square factors come out of roots (`sqrt(12)` gives `2*sqrt(3)`), and `sin`, `cos` and `tan` of a multiple of `pi/6` or `pi/4` are given exactly. When a constant answer is not a plain number, its value follows it after `~`.

## Commands

| Command | What it does |
|---------|--------------|
| `simplify(f)` | the same as typing `f` |
| `expand(f)` | multiplies out: `expand((x+2)^3)` gives `x^3 + 6*x^2 + 12*x + 8` |
| `factor(p)` | factors a polynomial over the rationals: `factor(x^4 - 1)` gives `(x + 1)*(x - 1)*(x^2 + 1)` |
| `solve(a = b)` | the roots of a polynomial exactly (rational roots, then the quadratic formula, with `i` for complex ones); any other equation numerically (`solve(cos(x) = x)` gives `x ~ 0.7390851332`). `solve(f)` means `f = 0` |
| `diff(f)`, `diff(f, n)` | the derivative, or the nth |
| `integrate(f)` | an antiderivative of sums of `c x^n`, `c/(ax+b)`, `sin`, `cos`, `tan`, `exp`, `ln` of a linear argument, and `c^(ax+b)` |
| `int(f, a, b)` | the definite integral: exact through the antiderivative when there is one, otherwise by Simpson's rule (shown after `~`) |
| `limit(f, a)` | the limit at a point, with L'Hôpital's rule for `0/0`; `limit(f, inf)` and `limit(f, -inf)` too |
| `series(f, a, n)` | the Taylor polynomial of degree n (5 when left out, 12 at most) about a (0 when left out) |

An answer that cannot be found is said in words (`no antiderivative found; int(f, a, b) gives a number`), and a mistake in the input gives `Error:` and what is wrong.

## Keys

Enter runs the line. Up and Down bring back earlier lines (the last 12). PgUp and PgDn scroll the console. Esc quits.

## Inside

An expression is a tree of 16-byte nodes in a pool on the heap: exact rationals, floats, `pi` and `e`, variables, powers, functions, products and sums. Subtraction is a sum with `-1 *`, division a power `-1`, and a square root a power `1/2`, so the simplifier only has to know products, sums and powers. It flattens a product or sum, puts one number in front, adds the powers of equal bases (or the coefficients of equal terms) and sorts what is left into one order, so that equal expressions come out the same. Rational arithmetic runs on the FPU and reports an overflow instead of wrapping.

`run cas test` checks 51 commands against their answers and prints `cas: PASS` (or each answer that differs).
