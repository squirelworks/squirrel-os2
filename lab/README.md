# Optional lab / ground-station profile

Scaffold for using Squirrel OS/2 as the **ISM Flight Lab / ground-station host**
([issue #225](https://github.com/squirelworks/squirrel-os2/issues/225), lane `-b55f`).

## Scope

| This tree (`lab/`) | Not here |
|--------------------|----------|
| Ground / lab host hooks only (Flight Lab packaging later, HIL bench host, maintenance laptop) | Flight-critical FBW, FCC laws, vote monitors, essential HUD |
| Soft app SoT stays in `squirrelsoft/squirrelflightlab/` | Certified avionics partitions |

Flight-critical control stays on a **small RTOS + SquirrelBIOS** bring-up / BIT.
OS/2 must not host those loops. See #225 and (once merged) the gap matrix under
`documentation/guides/ism-flightlab-gaps.md`.

## Build profile (OFF by default)

Normal `tools/build.sh` and `tools/regress.sh` are **unchanged** and do not
build this profile. CI and everyday builds stay as they are.

Enable the optional profile explicitly:

```sh
ENABLE_SQUIRREL_LAB=1 ./lab/build.sh
# or:
. ./lab/profile.sh && enable_squirrel_lab && ./lab/build.sh
```

With the flag unset (the default), `./lab/build.sh` prints that the profile is
off and exits 0 — it never touches `build/` images or regress.

## Status (scaffold only)

This PR only adds the directory, this note, and the off-by-default hook.
**Not yet:** serial/USB data path, soft-RT HIL timing, Soft Flight Lab packaging
onto `data.img`, or a lab setup guide. Those are later #225 boxes.

## Priority

Background after core OS work. Do not block tip-cut, desktop/Warp, or the 2.9
long-mode chain for this profile. Soft owns Flight Lab packaging; OS/2 only
owns the optional host-side profile and later host gaps (#225).
