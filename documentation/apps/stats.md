# Statistics (C.3)

`run stats [file.csv]` holds two lists of numbers and computes statistics, regressions and plots from them. It is a program on the data disk (`programs/stats.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`). Every entry is evaluated by the kernel's `sci` engine through `GUI_EVAL`, so `sqrt(2)`, `1/3` or `2^10` can be typed as well as plain numbers.

## The table

L1 and L2, up to 99 numbers each, are on the left; 18 rows show at a time. The cell after the last entry of a list is where a new one goes.

| Key | Action |
|-----|--------|
| Up, Down, PgUp, PgDn | move in the list |
| Tab, Left, Right | the other list |
| left click | that cell |
| a digit, `-`, `.` or `(` | start typing an entry with that character |
| Enter | start typing; the entry's value is filled in to change |
| Enter (while typing) | keep the entry and go down. A wrong expression shows the `sci` message and typing goes on |
| Esc (while typing) | drop what was typed |
| Delete | remove the entry; the ones below move up |
| Ctrl+S | save both lists as CSV, to the file named on the command line or `stats.csv` |
| Ctrl+N | empty both lists |
| Esc | quit |

## Results

The panel on the right shows the help until one of these is pressed. The result is computed again whenever the data changes.

| Key | Shows |
|-----|-------|
| `v` | the current list: n, mean, sum, sum x², sx (sample standard deviation, n − 1), sigma x (population, n), min, Q1, median, Q3, max |
| `x` | L1 as x and L2 as y (the same length): n, the means, sum x, sum y, sum xy, sx, sy, and the correlation r |
| `r` | a regression of L2 on L1, with the points and the curve. Each further `r` gives the next model |
| `h` | a histogram of the current list: about √n bins (1 to 12) of equal width from its minimum, with n, the bin count, the start and the width |
| `b` | a box plot of the current list: whiskers from min to max, the box from Q1 to Q3, the median in red, and the five numbers |
| `p` | a scatter plot of the pairs |

Quartiles are the medians of the lower and upper halves of the sorted list, with the median itself left out when n is odd (1, 2, 3, 4, 5 gives Q1 = 1.5, Q3 = 4.5).

## Regressions

| Model | Form | Fitted by | Needs |
|-------|------|-----------|-------|
| linear | y = a·x + b | least squares | 2 points |
| quadratic | y = a·x² + b·x + c | least squares (normal equations, Gauss–Jordan with partial pivoting) | 3 points |
| cubic | y = a·x³ + b·x² + c·x + d | the same | 4 points |
| exponential | y = a·bˣ | a line through (x, ln y) | every y > 0 |
| logarithmic | y = a + b·ln x | a line through (ln x, y) | every x > 0 |
| power | y = a·xᵇ | a line through (ln x, ln y) | every x, y > 0 |
| logistic | y = c / (1 + a·e^(−b·x)) | c by golden-section search between 1.000001 and 10 times the largest y; for each c, a line through (x, ln(c/y − 1)) | every y > 0, 3 points |

Each shows its coefficients and r² = 1 − SSres/SStot, computed on y itself for every model (so it compares models fairly; calculators that report r² of the transformed line give other values for exponential, power and logarithmic fits). Too few points, too few distinct x values, or a logarithm of a number that is not positive gives a message on the status row instead.

Numbers in the table are rounded to fit 9 characters, in the panel 12; noise below 1e-10 shows as 0. The full values are kept and saved.

## CSV files

A line holds an L1 value and an L2 value separated by a comma (a semicolon or a tab also works); either may be empty, so lists of different lengths fit. A first line that is not numbers is taken as a header and skipped. Files up to 8 KB are read. Saved files hold every digit `sci` prints.

## Self-check

`run stats test` checks one-variable statistics of 1 to 5; two-variable statistics and the linear fit of (1..5, 2 4 5 4 5) (a = 0.6, b = 2.2, r = 0.7746); exact data for each of the other models (2x² − 3x + 1, x³ − x, 2·3ˣ, 1 + 2 ln x, 3x², 10/(1 + 4e^(−x))), recovering the coefficients and r² = 1 to a millionth; the histogram of 1 to 8 (3 bins of 3, 2, 3) and its quartiles 2.5, 4.5, 6.5; saving, emptying and loading `stest.csv`; and the error for lists of different lengths. It prints `stats: PASS`, or `stats: FAIL` and a letter for the first check that failed.

Checks: `stats`, `stats-one`, `stats-reg`, `stats-quad`, `stats-differ`, `stats-csv` (save with Ctrl+S, load from the command line), `stats-quit`.
