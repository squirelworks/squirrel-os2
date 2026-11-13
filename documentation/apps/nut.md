# Nut (C.8)

Nut is a small scripting language for the Notebook (`notebook.md`). It is an interpreter in NASM, `programs/nut.inc`, that any program can include. It reads like BASIC and Lua: lines of statements, `end` to close a block, no semicolons.

## Values

A value is a number (a double) or a string (`"text"`). `true` is 1 and `false` is 0. Any number that is not 0 is true, and so is any string that is not empty.

```
x = 3                      # a variable; "let x = 3" is the same
name = "acorn"
print "x is", x * 2        # values separated by spaces, then a new line
```

`#` starts a comment that runs to the end of the line. A new line ends a statement; `;` does too. A statement may follow another on the same line when it starts with a keyword (`if 1 then print 2 end`).

## Operators

From the loosest to the tightest:

| Operators | |
|-----------|---|
| `or` | 1 if either side is true |
| `and` | 1 if both sides are true |
| `not` | 1 if the value is false |
| `== != <> < > <= >=` | 1 or 0. Two strings are compared letter by letter |
| `+ -` | `+` joins when either side is a string: `"a" + 1` is `"a1"` |
| `* / %` | `%` is the remainder. Dividing by 0 is an error |
| `^` | a power, worked out from the right: `2 ^ 3 ^ 2` is 512 |
| `-` in front | a negative |

## Statements

```
if x > 2 then ... elif x > 1 then ... else ... end
while x < 10 do ... end
for i = 1 to 10 do ... end          # step 1
for i = 10 to 1 step -3 do ... end
break                               # out of the innermost loop
fn area(w, h)                       # a function: up to 8 parameters
  return w * h
end
print area(3, 4)
```

A variable that is set inside a function belongs to that call, unless a variable of that name already exists outside every function: then that one is set. Parameters always belong to the call. Functions may call themselves, 100 deep at most.

## Built-in functions

`sin cos tan asin acos atan` (radians), `sqrt abs ln exp floor ceil round`, `min(a, b, ...)` and `max(a, b, ...)`, `len(s)` (a string's length), `str(n)` (a number as text), `num(s)` (text as a number), `rnd()` (a number from 0 up to 1), and the constant `pi`. Numbers are written as `sci` writes them (`1.5`, `0.1`, `1e+20`).

## Errors

An error stops the program and says what went wrong and on which line: `unknown variable`, `division by zero`, `outside the function domain` (`sqrt(-1)`, `ln(0)`), `a ) is missing`, `then is missing`, `end is missing`, `too many steps (a loop that never ends?)` after 500,000 statements, `calls too deep`, and so on. What was printed before the error is kept.

## For programs

`%include "nut.inc"` after the program's code, and `NUT_BSS` after `SQX_BSS`. Then:

| Routine | In | Out |
|---------|----|-----|
| `nut_init` | | memory from `SYS_SBRK` for the tokens, names, strings and output; CF if there is none |
| `nut_reset` | | every variable, function and line of output forgotten |
| `nut_run` | esi = a program | CF on an error (`nut_errmsg`, `nut_errline`); what it prints is added to `nut_out` (`nut_olen` bytes). Variables stay set for the next run |
| `nut_compile` | esi = an expression | eax = its first token, or CF |
| `nut_eval` | eax = a first token | eax = `V_NUM` (st0) or `V_STR` (edx = text, ecx = length), or CF |
| `nut_eval_x` | eax = a first token, `[nut_x]` = x | st0, the value with the variable `x` set to x (for graphs), or CF |
| `nut_setvar` | esi, ecx = a name, eax = `V_NUM` (st0) or `V_STR` (edx, ebx = length) | a global variable set; the name and text are copied |
| `n_numtext` | st0 | esi = the number as text (the FPU is reset) |

## Inside

The text is first cut into 16-byte tokens; names and strings are copied to a pool of their own, and numbers are read with `GUI_EVAL`. The interpreter then walks the tokens directly: there is no tree. A statement that is not taken (the other branch of an `if`, a function's body when it is defined) is walked in a skipping mode that checks its shape but does nothing. While the right side of an operator is worked out, the left side is kept on the CPU stack, so the FPU never holds more than a few values. Strings made while running (joined, `str`) go into a pool that is emptied by `nut_reset`.

`run notebook test` runs 20 Nut programs and compares what they print (or the error) with the right answer, before it checks a notebook.
