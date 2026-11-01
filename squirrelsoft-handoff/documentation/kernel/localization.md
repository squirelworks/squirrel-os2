# Localization Runtime (0.8.1)

Location: `../../kernel/lang.asm`, generated `../../kernel/strings.inc`, generator `../../tools/mkstrings.py`, sources `../../localization/<code>/strings.txt`.

## Build

`tools/mkstrings.py` reads every `localization/<code>/strings.txt` (`key=value` per line; `#` comments) and writes `kernel/strings.inc`:

- `LS_<KEY>` numbers for each key English defines, plus `LS_COUNT` and `LANG_COUNT`
- `lang_codes`: 4 bytes per language, English first
- `lang_tables`: per language, one pointer per key, or 0 where that language leaves the key out
- the strings themselves (printable ASCII only)

A language may not define keys English lacks. The generated file is checked in, so building the kernel needs only NASM. `tools/mkstrings.py --check` (run by `tools/regress.sh`) fails when it is stale.

## Kernel

| Item | Meaning |
|------|---------|
| `lstr` | One pointer per key: the current language's text, or English where it has none |
| `lang_select` | `eax` = language index; refills `lstr` (English at boot) |
| `lang_set_code` | `esi` = code (`en`, `la`, `tlh`); CF if unknown |
| `show_banner` | Localized product name, then the version and the (English) command help |
| `lputs_nl` | Prints `esi` and a newline. Strings are stored without one, so they can be used inline. |

Code prints a string with `mov esi, [lstr+LS_FILES*4]`. Strings used so far: the banner name, the prompt, the `ls` header, `Not found`, `Unknown command`, the `keys` prompt, the `systest` result, the `lang` messages, (1.0.5) the shell's `Usage:` lines and every file-system error reason, and (1.0.6) the titles of `calc`, `edit` and `draw`.

File-system errors (1.0.5): `fs_errkey` maps each `FE_*` code to a key (`fe_exists`, `fe_nodir`, …; `FE_NOTFOUND` uses `notfound`), and `fs_errstr` returns the text in the current language. The shell (`fs_why`), the editors' and `draw`'s message lines, and `SYS_FSERROR` all go through it, so they say the same thing. Usage lines print the localized `usage` word, the command syntax (kept as typed, `put <file> <text>`), and for `put` and `run` a localized hint.

## Shell

```
> lang
Language: en (en la tlh)
> lang la
> ls
Tabulae:
...
> lang fr
Lingua ignota (en la tlh)
```

The choice lasts until reboot. A `lang la` line in `autoexec.bat` makes it stick.

## Not yet

- Many messages (the command help, `ok`, the editors' own messages, the apps' help text) are still English-only literals. They move to keys under the policy in `localization/README.md`.
- No per-program language: loaded programs print their own text.
