# Localization

Squirrel-OS/2 will carry a basic localization set for every user-visible string:

| Code | Language |
|------|----------|
| `en` | English |
| `la` | Latin |
| `tlh` | Klingon |

## Layout

```
localization/
├── README.md
├── en/
│   └── strings.txt
├── la/
│   └── strings.txt
└── tlh/
    └── strings.txt
```

## Strings

| Key | English | Latin | Klingon | Used by |
|-----|---------|-------|---------|---------|
| banner | Squirrel-OS/2 | Sciurus-OS/2 | Squirrel-OS/2 | First banner line |
| prompt | > | > | > | Shell and batch prompt |
| files | Files: | Tabulae: | tebwI': | `ls` header |
| notfound | Not found | Non inventum | tu'lu'be' | `cat` |
| unknown | Unknown command | Mandatum ignotum | ra' tlhaQ | Shell |
| calc | Calculator | Calculator | Calculator | (not yet) |
| edit | Text Editor | Editor textus | ghItlh editor | (not yet) |
| draw | Drawing Program | Programma pingendi | naD program | (not yet) |
| hello | Hello from Squirrel-OS/2 | Salve ex Sciurus-OS/2 | nuqneH Squirrel-OS/2 | (not yet) |
| result | 2 + 2 = 4 | II + II = IV | cha' + cha' = loS | (not yet) |
| keys | Type keys, Enter to finish: | Claves preme, Enter ad finiendum: | leQmey yIbach, Enter yIbach rInmeH: | `keys` |
| systest_pass | systest: PASS | systest: PROBATUM | systest: Qapla' | `systest` |
| systest_fail | systest: FAIL | systest: DEFECIT | systest: luj | `systest` |
| lang_now | Language: | Lingua: | Hol: | `lang` (0.8.1) |
| lang_bad | Unknown language | Lingua ignota | Hol Sovbe'lu' | `lang` (0.8.1) |

## Runtime (0.8.1)

`tools/mkstrings.py` turns these files into `kernel/strings.inc`, which is built into the kernel, so no disk is needed to switch.
Run it after editing a `strings.txt`. `tools/regress.sh` fails if `strings.inc` is out of date.

In the shell, `lang` shows the current language, and `lang la` switches to Latin. To keep a choice across boots, put that line in `autoexec.bat`.
See `documentation/kernel/localization.md`.

## Policy

- Every new user-visible string gets an entry in all three files.
- Kernel and applications look up strings by key.
- Fallback is English if a translation is missing (a key left out of a file).
- Values are printable ASCII; the generator refuses anything else.
