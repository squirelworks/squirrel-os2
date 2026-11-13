# Notebook (C.8)

`run notebook [file]` opens a notebook: a page of cells that mix notes, code, graphs, tables and geometry. The cells are run from the top, and they share their variables, so a table can use a number that a program worked out, and a program can use a distance measured in a figure. The code is written in Nut (`nut.md`). The notebook is a program on the data disk (`programs/notebook.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`). Without a file name it uses `notebook.nb`.

## Cells

| Kind | What is in it | What is shown |
|------|---------------|---------------|
| note | text; a line that starts with `# ` is a heading | the text, wrapped |
| code | a Nut program | the program on grey, and under it what it printed (green) or the error (red) |
| graph | one curve a line: an expression in `x`, `y =` in front if wanted (four curves at most). `x: a b` sets the range of x (-10 to 10 when left out), `y: a b` the range of y | the curves, the axes, each curve's formula in its colour, and the ranges. Without `y:` the range of y is found from the values and rounded out |
| table | rows of cells split by `\|`: a number, text (in `"…"` or not), or `=` and an expression | a grid with columns A to F and the rows numbered. Each cell is a variable: `A1`, `B1`, … `C2` is column C of the second row. A formula may use the cells before it and every variable from the cells above the table |
| geo | `A = (x, y)` makes a point (x and y may be any expressions). `seg A B`, `line A B`, `circle A B` (through B) or `circle A r` (radius r), `poly A B C ...` draw. `dist A B`, `angle A B C` (at B, in degrees) and `area A B C ...` measure; `d = dist A B` also makes `d` a variable | the figure, scaled to fit its box, the points red with their names, and the measurements |

For example:

```
%% note
# Triangles
%% geo
A = (0, 0)
B = (4, 0)
C = (0, 3)
poly A B C
d = dist B C
%% table
side | =d
half | =A1 / 2
%% code
print "the long side is", d
%% graph
x: 0 d
x * (d - x)
```

`x` in a graph is the graph's own variable: after the graph it is left at the last value drawn. An error is shown in red in the cell where it happened (`! line 2: unknown variable`, `! A1: division by zero`, `! curve 1: outside the function domain`), and the cells after it still run.

## Keys

| Key | |
|-----|---|
| Up, Down | the cell before or after (the blue bar on the left marks it) |
| PgUp, PgDn, Home, End | scroll the page; the first or the last cell |
| Enter, or a click on the marked cell | edit it. A click on another cell marks that one |
| N, C, G, T, O | a new note, code, graph, table or geometry cell after the marked one, opened for editing |
| Del | remove the marked cell |
| Ctrl+Up, Ctrl+Down | move the marked cell up or down |
| Ctrl+R | run every cell again |
| Ctrl+S | save |
| Esc | quit |

The editor shows the whole cell's text. The arrows, Home and End move the cursor; Backspace and Delete remove; Enter starts a new line; Tab puts in two spaces. Esc ends the edit and runs the notebook again. A cell holds up to 2047 characters, and a notebook up to 32 cells.

## The file

A notebook is a text file. Each cell starts with a line `%% kind` (`note`, `code`, `graph`, `table`, `geo`) and its text follows. Text before the first `%%` line is a note. It can be written with any editor.

## Inside

Every cell's text has a 2 KB slot on the heap. Running the notebook resets Nut, then runs each cell in turn into two pools: text to show (output, table rows, measurements, errors) and numbers to draw (a graph's 300 values a curve as floats, a figure's points, segments, lines and circles). Drawing reads the pools, so scrolling does not run anything again. The page's layout comes from drawing each cell once without drawing (a dry run) to measure it.

`run notebook test` runs the Nut tests (`nut.md`), then loads a notebook with every kind of cell and checks what each cell shows, that the graph's line is drawn where it should be, that editing (typing, Home, End, Delete, Backspace, Up), new cells, removing and moving cells change the results, that the page scrolls, and that saving and loading give the same notebook. It ends with errors in a graph, a table and a figure. It prints `notebook: PASS`, or a letter for the step that failed and what the cell showed. Checks: `notebook`, `notebook-code`, `notebook-cells`, `notebook-err`, `notebook-save`, `notebook-quit`.
