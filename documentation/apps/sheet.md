# Sheet, a spreadsheet with charts (C.4)

`run sheet [file.csv]` is a spreadsheet of 26 columns (A–Z) by 99 rows. It is a program on the data disk (`programs/sheet.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`); the cells live in memory from `SYS_SBRK`. Without a name the sheet saves as `sheet.csv`.

## Cells

A cell holds up to 46 characters:

- a **number**: anything that starts like one (a digit, `-`, `+`, `.` or `(`) and that the kernel's `sci` engine can work out, so `2.5`, `-3` and `(1/3)` are numbers. Numbers are shown on the right of the cell, rounded to fit.
- a **formula**, which starts with `=`: `sci`'s operators and functions (`=sqrt(B1)*2^A1`), cell references (`B7`; `$B$7`, `$B7` or `B$7` keep that part fixed when copied), and the range functions `sum`, `avg`, `min`, `max` and `count` over a block (`=sum(A1:C4)`).
- **text**: anything else, shown on the left.

Every cell is worked out again after each change. Formulas are worked out row by row, so a column of running totals is quick. A reference to an empty cell counts as 0. Text in a formula is an error, but the range functions skip text and empty cells. A cell that depends on itself, directly or through others, shows `#CYC`. A cell that cannot be worked out (division by zero, a syntax error, a reference to an error, `avg` of no numbers) shows `#ERR` in red. When the cursor is on such a cell, the status row says which it is. When you type a formula that fails, the status row shows `sci`'s message (`Error: division by zero`). References are put in as their values with 10 significant digits.

The entry bar at the top shows the cursor's cell and its entry as typed (yellow while typing). The status row shows a number's full value (`= 2`) and the keys.

| Key | Action |
|-----|--------|
| arrows, Tab | move (Tab: right) |
| PgUp / PgDn | 8 rows |
| Home / Ctrl+Home | column A / cell A1 |
| typing | start a new entry in the cell |
| Enter, F2 | change the cell's entry |
| while typing: Enter, Tab, arrows | keep the entry and move (down, right, that way) |
| while typing: Esc | drop it |
| Delete | empty the cell, or every cell of the selection |
| F3 | start a selection at the cursor; moving the cursor extends it |
| left click / drag | move the cursor / select |
| Ctrl+C / Ctrl+V | copy the cell or the selection (up to 256 cells); paste with its top left at the cursor |
| Ctrl+D / Ctrl+R | fill the selection down from its first row / right from its first column |
| Ctrl+G | chart the selection; again without a selection: the next chart type, then no chart |
| Ctrl+S | save |
| Ctrl+N | a new, empty sheet |
| Esc | drop the selection; with none, quit. With unsaved changes Ctrl+N and Esc ask `Save changes? y/n` (Esc again stays) |

Pasting and filling move relative references along. If a cell is copied one column right, `=A1*$B$2+B3` becomes `=B1*$B$2+C3`. A reference moved off the sheet becomes `#REF`, and the formula shows `#ERR`.

## Charts

Ctrl+G with a selection draws a chart of it under the first 8 rows. Each column of the selection is a series, in blue, red, green, magenta, brown and cyan. If the first row holds text, it names the series. The title gives the chart type and the block (`Line A1:B5`), and the y range is shown on the left. Pressing Ctrl+G again cycles from a **line** chart to **bars** (each row a group, standing on 0) to a **scatter** plot (the first column is x, the others y) and then to no chart. The chart is linked to its cells, so it is redrawn from them after every change. Cells that are not numbers leave a gap.

## Files

Sheets are saved as CSV, one line a row up to the last row and column used. Each cell is saved as typed (formulas with their `=`), and a cell is quoted if it holds a comma or a quote. Opening reads the same form: quoted fields may hold commas and doubled quotes, and carriage returns are skipped.

## Self-check

`run sheet test` covers these cases, as keys fed to the program:

- numbers and a formula typed, and a change that goes through;
- `sum`, `avg`, `min`, `max`, `count`, a `sci` function, and an empty cell as 0;
- text and errors, and a cycle of three cells;
- copy and paste with relative and `$` references;
- a fill down to row 99, read back from row 1 through 98 formulas;
- a reference moved off the sheet;
- line and bar charts, read back from the screen, and a chart following a changed cell (its zero line appears);
- a CSV round trip with a quoted comma.

It prints `sheet: PASS`, or `sheet: FAIL` and a letter for the first check that failed.

Checks: `sheet`, `sheet-calc` (a formula typed: the entry bar and its value), `sheet-chart` (a chart of a named block), `sheet-cyc`, `sheet-csv` (saved and shown with `cat`), `sheet-quit` (`n` at the question).
