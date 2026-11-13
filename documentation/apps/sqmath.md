# sqmath, the expression engine v2 (C.1)

sqmath works out one line of mathematics at a time: real and complex numbers, decimals with many places, quantities with SI units, variables and user functions. It is an include file in NASM, `programs/sqmath.inc`, that any program can use; the Notebook's math cells use it (`notebook.md`). It is the in-OS form of the `sqmath` core that ROADMAP C.1 describes; a C port to squirrelsoft is optional.

## Lines

```
1 + 2*3                      7
(1+2i)*(3-i)                 5 + 5i
sqrt(-4)                     2i
e^(i*pi)                     -1
a = 2 [km] + 300 [m]         a = 2300 m
a to [km]                    2.3 km
9.8 [m/s^2] * 70 [kg]        686 N
v = 90 [km/h] to [m/s]       v = 25 m/s
f(x) = x^2 + 1               (a function, up to 4 parameters)
f(3)                         10
digits 50                    decimals with 50 places from here on
1/3                          0.33333333333333333333333333333333333333333333333333
30!                          265252859812191058636308480000000
digits 0                     doubles again
```

`#` starts a comment. `ans` is the last value. A number may be written `2.5`, `.5` or `1.5e-3`. A missing `*` is understood between a number and a name, a bracket or a unit: `2pi`, `3x`, `2(1+i)`, `5 [kg]`.

## Operators and functions

`+ - * /`, `^` (from the right), `-` in front, and `!` after a whole number. The constants are `pi`, `e` and `i`. The functions are `sqrt abs exp ln log` (base 10) `sin cos tan asin acos atan` (radians) `re im conj arg floor ceil round`. `sqrt`, `ln`, `exp`, `sin`, `cos`, `abs` and `^` also work on complex numbers; `sqrt` and `ln` of a negative number give a complex one. A complex part far smaller than the other (below a millionth of a millionth of it) is shown as 0, so `e^(i*pi)` is `-1`.

## Decimals

`digits n` (1 to 150) makes every number a decimal with n places after the point: `+ - * /`, whole powers, `!` and `sqrt` are exact to those places (5 more are kept inside and the last one shown is rounded), and so are `pi` and `e` (worked out by series). Other functions and powers that are not whole work in doubles. `digits 0` goes back to doubles; decimals kept in variables become doubles then.

## Units

A unit is written in square brackets after a number, or alone: `3 [km]`, `[m/s^2]`, `5 [kg*m^2]`, `[s]`. Units: `m g s A K mol cd`, `min h day`, `Hz N J W Pa C V ohm`, `L t`, `in ft yd mi lb`, `eV cal atm bar`, with the prefixes `k M G c m u n` (`km`, `mg`, `kPa`, `us`). A unit binds to the number before it, so `3 [m] / 2 [s]` is 1.5 m/s. Values are kept in SI units and shown in base units (`m/s`, `kg*m^2`) or by name when they are newtons, joules, watts, pascals, hertz or volts. `x to [unit]` shows x in another unit with the same powers. Adding quantities with different units is an error (`the units do not match`); `floor`, `ceil`, `round` and the functions other than `abs`, `sqrt`, `re`, `im`, `conj` and `arg` want a number without a unit.

## Variables and functions

`name = expression` keeps a value. `f(a, b) = expression` keeps a function; its parameters hide variables of the same name while it runs, and it may call other functions (16 deep at most). A name sqmath does not know is asked of the program (`sqm_get`): in the Notebook, a Nut variable from the cells above.

## Errors

`division by zero`, `outside the function domain`, `the units do not match`, `unknown name`, `unknown unit`, `unknown function`, `the wrong number of arguments`, `the number is too large`, `a ) is missing`, `this cannot be read here`, and others; the line stops there.

## For programs

`%include "sqmath.inc"` after the program's code (it uses `gui.inc` for `GUI_EVAL`), and `SQM_BSS` after `SQX_BSS`.

| Routine | In | Out |
|---------|----|-----|
| `sqm_init` | | memory from `SYS_SBRK`; CF if there is none |
| `sqm_reset` | | every variable and function forgotten; doubles again |
| `sqm_line` | esi = a line | CF on an error (`sqm_err`), or `sqm_out` = the text to show and `sqm_kind`: `SK_VALUE` (the value), `SK_SET` (`a = value`), `SK_DEF` (the definition), `SK_DIGITS`, `SK_NONE` (an empty line) |
| `[sqm_get]` | 0, or a routine: esi, ecx = a name | st0, or CF |
| `[sqm_set]` | 0, or a routine: esi, ecx = a name, st0 = a real value just kept (in SI) | |

## Inside

The line is read by recursive descent and worked out as it is read, on a stack of 128-byte values: a type (double, complex, decimal), the powers of the seven SI base units (m, kg, s, A, K, mol, cd), the real and imaginary parts, and a decimal's sign and magnitude. A decimal is a 768-bit binary integer that is the value times 10^F (F = places + 5): adding is adding, a product is divided by 10^F, a quotient is (a times 10^F) divided by b, by shifting and subtracting, and `sqrt` is Newton's method from the double's root. `pi` is 16 atan(1/5) − 4 atan(1/239) and `e` the sum of 1/k!, both in decimals. Doubles are read and shown by the `sci` engine (`GUI_EVAL`).

`run notebook test` checks 37 lines of sqmath (complex arithmetic, units and conversions, functions, 50-place decimals of 1/3, π, √2 and e, 2^100 and 30!, and errors), and a math cell that uses and gives Nut variables. Check: `notebook-math`.
