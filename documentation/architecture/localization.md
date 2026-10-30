# Localization Design

## Goal

Every user-visible string in Squirrel-OS/2 exists in English (`en`), Latin (`la`), and Klingon (`tlh`).

## Current stage

Scaffold only. String tables live in `localization/{en,la,tlh}/strings.txt`.

## Next steps (when resumed)

1. Kernel string lookup by key.
2. Language selection at boot or via command.
3. Applications use the same key set.
4. Expand the catalog as new UI appears.

## Policy

- No new user-facing text without the three translations.
- English is the fallback.
- Original Squirrel-OS/2 strings only; no external message catalogs.
