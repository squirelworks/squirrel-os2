# File Browser (`files`, 0.2.3; directories 0.9.2)

Location: `kernel/browser.asm`. Start it with `run files`, or open the `files` entry from the browser itself.

## Behaviour

- Lists the entries of the current directory with their sizes; files whose name is a built-in app are tagged `[app]`.
  The title says which directory (`Files (data disk) in /docs`). Without a data disk it lists the built-in (ROM) files instead.
- Directories are listed as `name/  <dir>`; outside the root a `../` entry comes first (0.9.2).
- **Enter** on a directory goes into it, and on `../` goes up. The shell stays in the directory the browser was in when you leave.
- **Up/Down, PgUp/PgDn, Home/End** move the selection; the list scrolls in an 18-row window.
- **Enter** on an `[app]` file launches that app as a child process (the browser waits, then reloads
  the list in case the app changed files). Enter on any other file views it.
- **v** views the selected file, then waits for a key.
- **d** deletes the selected entry after a `y/n` confirmation (disk only). If the file system refuses
  (a directory that is not empty, or the current one), the browser says why and waits for a key.
- **Esc** returns to the shell.

## Design notes

- Runs as its own process (spawned by the shell through `app_host`), reading raw scancodes with
  `kbd_getscan`, so it never blocks other processes.
- App association is by name, through the shell's `run_table`. Since the program loader (0.4.0),
  Enter on an executable file will load it instead.
- Entering a directory sets the shell's current directory (`fs_cwd`), so names the browser passes on
  (to `edit`, `cat`, the loader) are relative to it, the same as at the prompt.

## Next

- Rename and create from inside the browser.
- Make a directory from inside the browser.
