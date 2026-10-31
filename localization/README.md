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
| usage | Usage: | Usus: | lo'meH: | shell usage lines (1.0.5) |
| usage_put | (adds a line to the file) | (lineam tabulae addit) | (teywI'Daq tlhegh chel) | shell usage lines (1.0.5) |
| usage_run | (apps: see the list above, or ls) | (programmata: vide indicem supra, vel ls) | (ghunmey: tetlh Dung yIlegh, pagh ls) | shell usage lines (1.0.5) |
| fe_error | error | error | Qagh | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_nofs | No file system mounted (attach a data disk). | Nullum systema tabularum (disci datorum adiunge). | teywI' pat tu'lu'be' (De' Hew yIrar). | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_name | Bad name: 1 to 15 characters, not . or .. | Nomen malum: I ad XV litterae, non . vel .. | pong QIH: 1 vo' 15 ngutlh, . pagh .. ghobe' | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_exists | Already exists | Iam exstat | tu'lu'pu' | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_nodir | No such directory | Nullum tale directorium | ghItlh pa' tu'lu'be' | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_table | Directory table full (64 entries) | Tabula directorii plena (LXIV) | ghItlh pa' tetlh teb (64) | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_busy | File is open | Tabula aperta est | teywI' poSmoHlu' | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_notempty | Directory not empty | Directorium non vacuum | ghItlh pa' chImbe' | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_cwd | That is the current directory | Id est directorium praesens | DaH ghItlh pa' 'oH | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_loop | A directory cannot move into itself | Directorium in se ipsum moveri non potest | ghItlh pa' 'oH'e' ghItlh pa' Daq vIHlaHbe' | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_io | Disk error | Error disci | Hew Qagh | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_full | Disk full | Discus plenus | Hew teb | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_isdir | Is a directory | Directorium est | ghItlh pa' 'oH | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |
| fe_nofd | Too many open files | Nimis multae tabulae apertae | teywI'mey poSmoHlu'bogh law'qu' | file-system errors (shell, editors, `draw`, `SYS_FSERROR`) (1.0.5) |

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
