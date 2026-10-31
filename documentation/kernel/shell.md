# Shell Command Line (0.5.0–0.5.2)

Location: `../../kernel/shell.asm` (pipeline driver), `../../kernel/pm.asm` (`run_simple`, the built-in commands)

## Line editing and history (0.5.1)

Location: `../../kernel/lineedit.asm`

| Key | Action |
|-----|--------|
| Left / Right | Move the cursor |
| Home / End | Start / end of the line |
| Backspace / Delete | Erase before / at the cursor |
| typing | Inserts at the cursor |
| Up / Down | Older / newer command from the history; Down past the newest returns to the line being typed |
| Esc | Clears the line |
| Enter | Runs the line wherever the cursor is |

Lines up to 120 characters may wrap onto the next screen row. The editor redraws from where
the line started and follows the screen when it scrolls.

The last 16 commands are kept in memory (`KSCRATCH+0x2800`). Blank lines and an immediate
repeat are not stored. With a data disk, each command is also appended to `shell.hist`.
At boot the newest 16 lines of that file are loaded, so history survives a reboot. The file is
rewritten from memory (compacted to 16 lines) at boot when it holds 64 lines or more, and
after every 64 new commands. It is an ordinary file: `cat shell.hist`, `rm shell.hist`.

## Redirection and pipes

| Syntax | Meaning |
|--------|---------|
| `cmd > file` | Output of `cmd` goes to `file`, replacing it |
| `cmd >> file` | Output is appended to `file` |
| `cmd < file` | `cmd` reads `file` as its input |
| `a \| b` | Output of `a` is the input of `b`; any number of stages |

Examples:

```
echo hello > greet          ls | run wc            run calc < sums > results
echo more >> greet          echo a b | run cat | run wc
```

Spaces around `|`, `<` and `>` are optional. File names follow the SQFS rules (up to 15 characters).
The command line holds up to 120 characters. There is no quoting yet, so a `|`, `<` or `>` always splits.

## How it works

Stages run one after another, not concurrently:

1. `do_command` copies the line, cuts it at `|`, and strips `< name`, `> name` and `>> name` from each stage.
2. For a stage whose output goes to a pipe or a file, `putc` switches to **capture** mode and appends every character to a 32 KB buffer instead of the screen (backspace removes the last one). `cls` and the apps' return-to-shell banner (`app_home`) do nothing while capturing, so the captured text is just the command's own output.
3. For a stage with input, the previous stage's buffer (or the `<` file, read into a buffer) becomes **redirected input**. `SYS_GETC` returns its bytes and then `-1` at the end. The line reader shared by `calc`, `sci` and `matrix` takes whole lines from it and echoes them, and quits at the end like Esc.
4. After the stage, a `>` file is written from the buffer, or the buffer is handed to the next stage.

Two buffers alternate (`0x60000` and `0x68000`, 32 KB each), so a stage reads one while writing the other. Output beyond 32 KB is dropped with the note `(output cut at 32 KB)`.

What reads redirected input: programs using `SYS_GETC` (`cat` and `wc` without a file name) and the calculators. The full-screen apps (`edit`, `vedit`, `draw`, `files`) read the keyboard directly and ignore it. What gets captured: everything printed through `putc` (built-in commands, calculators, loaded programs). The full-screen apps draw straight to video memory, so they show on screen as usual.

There is no separate error stream yet. Error messages of a stage are captured with its output.

## Batch files (0.5.2)

Location: `../../kernel/batch.asm`

```
batch <file>        run a script
run <name>.bat      the same, for files ending in .bat
```

A batch file is plain text, one command line per line, and each line may use pipes and redirection.

- Lines starting with `#` are comments. Blank lines are skipped.
- Each line is echoed as `> line` before it runs. A leading `@` hides the echo (`@echo hi` prints just `hi`).
- Pressing Esc stops the script before its next line (`Batch stopped`).
- A script that starts another one (`batch other` or `run other.bat`) hands over to it, as DOS did. The rest of the first script is not run.
- `autoexec.bat` on the data disk runs at boot, before the first prompt.

How it works: `batch` only queues the script (up to 4 KB, read into `KSCRATCH+0x3000`). After the
current command line finishes, `do_command` runs the queued lines one by one through the same
pipeline driver as typed lines. Because of this, a script never runs inside another command's
pipeline, and redirecting the `batch` command itself (`batch x > out`) captures nothing. Put the
redirections on the lines inside the script instead.

## Built-in commands

`ls`, `cat <f>`, `echo <text>`, `batch <file>`, `put <f> <text>`, `mk <f>`, `rm <f>`, `mv <f> <new>`, `format`, `ps`, `disk`,
`run <app|file> [args]`, and the tests `systest`, `proctest`, `blktest`, `fstest`, `memtest`, `gfxtest`, `gfxprim` and `gfxtext` (1.3, `graphics.md`), `wintest`, `winmove` and `winfocus` (1.4, `windows.md`), `labeltest` (1.5, `widgets.md`), `keys`.

A command that needs arguments, typed alone (`put`, `mk`, `rm`, `mv`, `mkdir`, `cat`, `run`, `batch`),
prints a `Usage:` line instead of `Unknown command`; `echo` alone prints an empty line (0.9.2,
`sh_usage` in `pm.asm`). File commands that fail say why (see `filesystem.md`).
