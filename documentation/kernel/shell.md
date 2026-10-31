# Shell Command Line (0.5.0)

Location: `../../kernel/shell.asm` (pipeline driver), `../../kernel/pm.asm` (`run_simple`, the built-in commands)

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

## Built-in commands

`ls`, `cat <f>`, `echo <text>`, `put <f> <text>`, `mk <f>`, `rm <f>`, `mv <f> <new>`, `format`, `ps`, `disk`,
`run <app|file> [args]`, and the tests `systest`, `proctest`, `blktest`, `fstest`, `keys`.
