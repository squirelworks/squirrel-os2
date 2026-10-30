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

Code prints a string with `mov esi, [lstr+LS_FILES*4]`. Strings used so far: the banner name, the prompt, the `ls` header, `Not found`, `Unknown command`, the `keys` prompt, the `systest` result, and the `lang` messages.

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

- Most messages (help text, app titles, errors) are still English-only literals. Moving them to keys is ongoing work under the policy in `localization/README.md`.
- No per-program language: loaded programs print their own text.
