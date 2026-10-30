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

## Current strings (scaffold)

| Key | English | Latin | Klingon |
|-----|---------|-------|---------|
| banner | Squirrel-OS/2 | Sciurus-OS/2 | Squirrel-OS/2 |
| prompt | > | > | > |
| files | Files: | Tabulae: | tebwI': |
| notfound | Not found | Non inventum | tu'lu'be' |
| unknown | Unknown command | Mandatum ignotum | ra' tlhaQ |
| calc | Calculator | Calculator | Calculator |
| edit | Text Editor | Editor textus | ghItlh editor |
| draw | Drawing Program | Programma pingendi | naD program |

## Policy

- Every new user-visible string gets an entry in all three files.
- Kernel and applications look up strings by key.
- Fallback is English if a translation is missing.
- This is scaffolding; full message catalogs and runtime switching come later.
