# Games (G.1–G.9)

Location: `programs/<game>.asm`, built as SQX programs and installed on the data disk by
`tools/build.sh` (they are not in the kernel image). Start one with `run <game>`.

All the games are original code. They share two include files:

- `programs/games.inc`: console output, a line reader (`g_readline`, lower-cases, Backspace edits,
  Esc on an empty line or the end of redirected input quits), a seeded xorshift32 random number
  generator with a Fisher–Yates shuffle, word and number parsing, and the self-test helpers
  (`g_expect`, `g_report`).
- `programs/cards.inc`: playing cards (one byte, `suit * 16 + rank`), deck, colour, printing
  (` AS`, `10H`, ` QC`; ` ##` face down) and parsing (`qh`, `10s`, `ts`).

## Common behaviour

- The games are line-oriented: they print the board, read one command, and print the board
  again. They work on the text console, through pipes and `<` redirection, and in
  `tools/regress.sh`. Each also has a graphical front end (below).
- `run <game> <number>` seeds the deal or the computer's choices with that number, so a game
  can be replayed; without a number the seed comes from the time-stamp counter.
- `run <game> test` runs the game's rules self-check and prints `<game>: PASS` (or the number
  of the check that failed and `<game>: FAIL`; the exit code is 0 or 1).
- `n` starts a new game, `q` (or Esc on an empty line) quits.
- `run <game> gui [seed]` plays the same game on the graphics screen (below).

### On the graphics screen

`run <game> gui [seed]` (`run mines gui [seed] [big]`) opens the 320 x 200 screen through
`SYS_GUI` and `programs/gui.inc` and plays the same rules, the same seeded deals and the same
computer players as the text game. Everything is played with the mouse or the keyboard: click
a card, tile, square or cell to pick it and click where it goes, or move the white cursor with
the arrow keys and press Enter (or Space). A yellow frame marks what is picked up, the status
bar at the bottom says what to do, `n` starts a new game and `q` or Esc goes back to the shell.
The drawing they share is in `programs/gamegui.inc`: the green table and status bar, cards
(32 x 44, rank and suit sign in the corner, a large sign in the middle, a blue lattice back),
the 7 x 7 suit signs, fanned columns, discs, frames, and a small text builder for status lines.
All of the art is original.

| Game | On the screen | Keys besides the arrows and Enter |
|------|---------------|-----------------------------------|
| Klondike | stock, waste, foundations (with their suit signs while empty), seven fanned columns | `d` draw, `a` everything to the foundations |
| FreeCell | four cells and four foundations on top, eight columns; Up and Down change rows | `a` everything to the foundations |
| Hearts | your hand along the bottom (cards to pass are raised), the trick in the middle, scores on top; the computer's cards come one by one | click or Space picks a card to pass, Enter passes |
| Mines | the field of raised tiles; numbers in colour, flags, the mines when you lose | `f` flags the cell under the cursor |
| Reversi | the board with black and white discs; dots mark your moves, a red dot the computer's last | — |
| Chess | the board with original piece drawings, files and ranks, dots where the picked piece may go, the last move framed; your and its last moves on the right | `1`–`4` level; Esc drops a picked piece; pawns promote to a queen |
| Mahjongg | the pyramid drawn layer by layer, each tile with its number and its sign (acorn, leaf, star) | `h` frames a pair you can take |

`tools/regress.sh` plays a few moves of each on the screen and reads the status bar back
(`klondike-gui`, `freecell-gui`, `hearts-gui`, `mines-gui`, `mines-gui-big`, `reversi-gui`,
`chess-gui`, `mahjongg-gui`).

| Game | Program | Roadmap | Self-check |
|------|---------|---------|------------|
| Klondike solitaire | `klondike` | G.1 | `klondike: PASS` (29 checks) |
| FreeCell | `freecell` | G.2 | `freecell: PASS` (21 checks) |
| Mines | `mines` | G.3 | `mines: PASS` (16 checks) |
| Hearts | `hearts` | G.4 | `hearts: PASS` (41 checks) |
| Chess | `chess` | G.5 | `chess: PASS` (19 checks) |
| Mahjongg solitaire | `mahjongg` | G.7 | `mahjongg: PASS` (17 checks) |
| Reversi | `reversi` | G.8 | `reversi: PASS` (15 checks) |

G.6 (Contract Bridge) and G.9 (Checkers or Go) are not written yet.

## Klondike (`klondike`, G.1)

Draw-one Klondike. Seven columns of 1–7 cards with the top card face up, 24 in the stock.

- `d` draws a card from the stock to the waste; with the stock empty it turns the waste over
  (the cards come round in the same order).
- A move names a source (`1`–`7` or `w` for the waste) and a target (`1`–`7` or `f` for the
  foundations): `35`, `m 3 5`, `w4`, `3f`, `w f`. Between columns the longest run of face-up
  cards that fits on the target moves; only a king goes on an empty column. A face-down card
  left on top turns up by itself.
- `a` moves every card it can to the foundations, until none moves.
- The screen: the stock count, the waste's top card, the four foundations (clubs, diamonds,
  hearts, spades), then the columns; `##` is a face-down card.

Self-check (29 checks): a seeded deal has the right column sizes, 24 in the stock and all 52
cards once; the same seed deals the same, another seed differently; colour and rank rules
between columns, a run moving as a whole, kings only on empty columns, the card under a moved
run turning up; foundations in suit order; drawing and turning the waste over; auto-move
finishing a game; the move parser.

## FreeCell (`freecell`, G.2)

All 52 cards dealt face up into eight columns (7, 7, 7, 7, 6, 6, 6, 6), four free cells and four
foundations.

- Places: columns `1`–`8`, free cells `a`–`d`, foundations `f`. `35` moves column 3 to column 5,
  `3a` to free cell a, `a5` from cell a to column 5, `3f` / `af` to the foundations; `auto` moves
  everything it can up.
- A run moves between columns when it is in order (each card one lower and the other colour) and
  no longer than (free cells + 1) × 2 ^ (empty columns, not counting an empty target). Onto an
  empty column the longest run that fits the room goes.

Self-check (21 checks): the deal shape and all 52 cards; free-cell moves and an occupied cell
refused; run moves allowed and refused by the room rule, doubled by empty columns; colour and
rank refusals; auto-move to a win; the move parser.

## Hearts (`hearts`, G.4)

You (South) against West, North and East, played clockwise; first to 100 points ends the game,
lowest score wins.

- Each round starts with passing three cards: left, right, across, then no pass. Type them like
  `qs kh 2c`.
- The 2 of clubs leads the first trick; follow suit when you can; no hearts or queen of spades on
  the first trick unless you hold nothing else; hearts are not led until one has been played
  (unless your hand is all hearts). Play a card by name: `qs`, `10h`, `th`, `2c`.
- Each heart is 1 point, the queen of spades 13. Taking all 26 shoots the moon: everyone else
  gets 26.
- The computer players pass the queen, king and ace of spades first, then high hearts. They lead
  their lowest legal card; following suit they play the highest card that still loses the trick
  (or, if they must win it, their highest when last to play, else their lowest); void in the
  suit they drop the queen of spades, then their highest heart, then their highest card.

Self-check (41 checks): the deal; who leads; following suit, the first-trick and broken-hearts
rules on a fixed position; trick winner and points; shooting the moon; passing (cards reach the
right player, 52 cards in play); eight whole seeded rounds with the computer in every seat, each
card checked legal and 26 points taken; the card parser.

## Chess (`chess`, G.5)

You play White against an original alpha-beta engine.

- Moves in coordinate notation: `e2e4`, `g1f3`, `e7e8n` (a promotion without a letter makes a
  queen), `o-o` and `o-o-o`. `moves` prints the game as PGN move text, `save game.pgn` writes a
  PGN file (tags, moves, result) to the data disk, `level 1`–`level 4` sets the search depth
  (default 3).
- Full rules: castling (not out of, through or into check), en passant, promotion to any piece,
  checkmate and stalemate. The fifty-move rule and repetition are not claimed.
- The board is 0x88 (`square = rank * 16 + file`); moves are generated pseudo-legally and kept
  when the mover's king is not attacked afterwards. The engine is negamax alpha-beta with
  captures searched first and a captures-only quiescence search at the leaves; the evaluation is
  material plus a centre table for knights, bishops and pawns and a bonus for advanced pawns.
  Moves are written in SAN with disambiguation (`Nbd2`), captures, `=Q`, `+` and `#`.

Self-check (19 checks): perft from the start position (20, 400, 8902), from a position with
castling, en passant and promotions (48, 2039), and from an endgame with pins and en passant
(14, 191, 2812); make/unmake leaves the position unchanged; the engine mates in one and takes a
hanging queen; stalemate; the PGN of the fastest mate (`1. f3 e5 2. g4 Qh4# 0-1`);
disambiguation, `O-O` and under-promotion in SAN; an illegal move is refused.

## Mahjongg (`mahjongg`, G.7)

Tile solitaire on an original four-layer pyramid (10 × 6, 8 × 4, 6 × 2 and 2 × 2 on a 10 × 6
grid): 108 tiles, 27 kinds (Acorns, Leaves and Stars 1–9), four of each.

- Each grid cell shows its top tile (`A3`, `L9`, `S1`), the stack height, and `*` when the tile
  is free: nothing on it and its left or right side open on its layer.
- `c3 f5` removes the pair on those cells when both are free and match; `h` shows a pair.
- Every deal can be solved: it is made by playing a random game backwards (pairs of free tiles
  come off the full pyramid and are given the same kind), so that order is a solution.

Self-check (17 checks): 108 tiles; each kind four times; a move exists; replaying the deal order
clears the board pair by pair; seeds; freedom on the edge, between two tiles and under a stack;
mismatched and matching pairs; the cell parser.

## Mines (`mines`, G.3)

A Minesweeper-class game: open every cell that has no mine.

- `run mines [seed] [big]`: 9 × 9 with 10 mines, or `big` for 16 × 16 with 40.
- A cell is a column letter and a row number. `c5` opens it, `f c5` flags or unflags it.
- The first cell opened is never a mine: the mines are laid after it, away from it and its
  neighbours. Opening a cell with no neighbouring mine opens the area around it (flood fill
  with an explicit queue, no recursion).
- Board: `.` hidden, `F` flag, a digit for the mines around an open cell, blank for none,
  `*` for the mines once you lose.

Self-check (`run mines test`, 16 checks): a seeded board has exactly 10 mines, none next to the
first cell, and correct neighbour counts; the same seed gives the same board and another seed a
different one; one mine in a corner lets the flood open all 80 other cells and win; a flagged
cell does not open, opening a mine loses, a numbered cell opens alone; the cell parser; the big
board holds 40 mines.

## Reversi (`reversi`, G.8)

You play X and move first against the computer (O). Legal squares are marked `+`.

- Type a square like `d3`. A side with no legal move passes automatically; the game ends when
  neither side can move.
- The board is a 10 × 10 mailbox with wall squares around the 8 × 8 board, so the eight
  direction walks need no bounds checks.
- The computer searches two plies: for each of its moves it assumes your best reply, scoring
  positions with a square-weight table (corners high, the squares next to them low). Equal
  scores are broken with the seeded random numbers.

Self-check (`run reversi test`, 15 checks): four legal moves at the start; `d3` flips exactly
one disc; a move that flips nothing is refused and leaves the board alone; perft from the start
position gives 4, 12, 56 and 244 positions at depths 1–4; the computer takes a corner when it
can; a board with one colour only is over; and a full computer-against-computer game ends with
all 64 squares accounted for.
