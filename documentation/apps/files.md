# File Browser (`files`, 0.2.3)

Location: `kernel/browser.asm`. Start it with `run files`, or open the `files` entry from the browser itself.

## Behaviour

- Lists every file on the data disk with its size; files whose name is a built-in app are tagged `[app]`.
  Without a data disk it lists the built-in (ROM) files instead.
- **Up/Down, PgUp/PgDn, Home/End** move the selection; the list scrolls in an 18-row window.
- **Enter** on an `[app]` file launches that app as a child process (the browser waits, then reloads
  the list in case the app changed files). Enter on any other file views it.
- **v** views the selected file, then waits for a key.
- **d** deletes the selected file after a `y/n` confirmation (disk files only).
- **Esc** returns to the shell.

## Design notes

- Runs as its own process (spawned by the shell through `app_host`), reading raw scancodes with
  `kbd_getscan`, so it never blocks other processes.
- App association is by name, through the shell's `run_table`. Since the program loader (0.4.0),
  Enter on an executable file will load it instead.
- Navigation is flat because SQFS has one directory; subdirectories would add an "enter directory" action here.

## Next

- Rename and create from inside the browser.
- Open text files in `edit` once the editors can load files.
