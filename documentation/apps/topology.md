# Topology and matrices (C.9)

Two windowed programs on the data disk, built on `SYS_GUI` and `gui.inc` (`gui-programs.md`). They take over from the kernel's text-mode `topo` scaffold, which stays for now.

## Topology (`run topology`)

Simplicial complexes up to dimension 3 on at most 16 vertices. The window shows the face counts (V, E, F, T), the Euler characteristic, and the Betti numbers b0, b1, b2 over Z/2 and over Q, and draws the 1-skeleton with the vertices on a circle. When the two rows of Betti numbers differ it says `Z/2 and Q differ: 2-torsion`.

A complex is typed as its maximal simplices, vertex numbers 0 to 15 separated by spaces, simplices separated by commas: `0 1 2, 0 2 3` is two triangles sharing an edge. Faces are added automatically.

| Key | Action |
|-----|--------|
| Up, Down | choose a ready-made complex; it is computed at once |
| Enter or Tab | `Custom`: edit the text (it starts with the last complex) |
| Delete | while editing, clears the line |
| Enter | while editing, computes |
| Esc | stops editing; otherwise quits |

Ready-made complexes: point, interval, circle, figure 8, disk, sphere (boundary of a tetrahedron), torus (7 vertices), Möbius band, RP2 (6 vertices), Klein bottle (9 vertices), 3-sphere (boundary of a 4-simplex).

Ranks of the boundary maps are taken over Z/2 with bit vectors (each column reduced against a basis kept by pivot bit) and over Q by Gaussian elimination with partial pivoting on doubles, in a 128 × 128 matrix from `SYS_SBRK` (a pivot below 1e-9 counts as 0). bₖ = dim Cₖ − rank ∂ₖ − rank ∂ₖ₊₁.

Errors (`Vertices are 0 to 15`, `At most 4 vertices a simplex`, `Too large (128 simplices a dimension)`) appear on the status row and leave the last result in place.

`run topology test` checks every ready-made complex against its known Betti numbers over both fields and prints `topology: PASS`. Regress checks: `topology`, `topology-gfx` (torus), `topology-rp2` (2-torsion), `topology-custom`, `topology-bad`.

## Matrices (`run matrixgui`)

Two matrices, A and B, from 1 × 1 to 4 × 4, edited in a grid; results appear under it. An entry is any `sci` expression (`2`, `-1.5`, `sqrt(2)`, `pi/4`), evaluated by `GUI_EVAL`.

| Key | Action |
|-----|--------|
| arrows | move between entries |
| a digit, `-`, `.`, `(` or Enter | start typing an entry; Enter or an arrow keeps it, Esc drops it |
| Tab | edit A or B |
| Ctrl+arrows | fewer or more rows and columns |
| `+` `-` `*` | A + B, A − B, A × B |
| `d` `i` `t` `k` | determinant, inverse, transpose, rank of the matrix being edited |
| `s` | solve A X = B |
| `c` | copy the result into the matrix being edited |
| Esc | quit |

Determinant, inverse, solve and rank use Gauss–Jordan elimination with partial pivoting; a pivot below 1e-12 counts as 0, so a singular matrix reports `The matrix is singular`. Entries below 1e-10 show as 0, and each value is fitted to 8 characters. Mismatched sizes give `The sizes do not match`.

`run matrixgui test` checks every operation on A = [1 2; 3 4] and B = [5 6; 7 8] and the error cases, and prints `matrixgui: PASS`. Regress checks: `matrixgui`, `matrixgui-mul`, `matrixgui-inv`, `matrixgui-det`, `matrixgui-sing`, `matrixgui-quit`.
