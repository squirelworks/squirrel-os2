#!/usr/bin/env python3
"""Docs honesty linter (CONTINUANCE §3c).

Every `- [x]` box in TODO.md / ROADMAP.md / HANDOFF.md that names a regress
check must find that check in tools/regress.sh, and every check named by an
open `- [ ]` box must not exist yet. Cheap, deterministic, no network or QEMU.

A box "names a check" when its text contains:
  - an explicit "check(s) `name`" reference (comma / slash lists allowed),
  - a backtick token of the form `name: PASS` (the check is `name`), or
  - a backtick glob like `fat12-*` / `cp-*` that matches regress check names.

Harness inventory is the set of names passed to `check`, `check_all`,
`check_all_retry`, `check_retry` and `check_none` in tools/regress.sh.
Known historical mismatches can be listed in tools/docs_lint_allowlist.txt
without reticking many boxes.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC_NAMES = ("TODO.md", "ROADMAP.md", "HANDOFF.md")
REGRESS_PATH = ROOT / "tools" / "regress.sh"
ALLOWLIST_PATH = ROOT / "tools" / "docs_lint_allowlist.txt"

BOX_RE = re.compile(r"^(\s*)- \[([ xX])\]\s+(.*)$")
BACKTICK_RE = re.compile(r"`([^`]+)`")
# "Check `foo`" / "Checks `a`, `b`" / "Pixel-probe check `bevwidgets`" /
# "checks `dos-win`" — not "checked against `fn`".
EXPLICIT_CHECK_RE = re.compile(
    r"(?i)\bchecks?\s+`([^`]+)`"
)
PASS_TICK_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9_-]*): PASS$")
# Bare regress-shaped names outside an explicit Checks clause: kebab-case
# with at least one hyphen (wc-bar, floppy-boot). Plain program names
# (`drvtest`, `mousetest`) are not treated as checks unless written as
# Check `name` or `name: PASS`.
CHECK_NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9.]+)+$")
GLOB_RE = re.compile(r"^(?:[A-Za-z][A-Za-z0-9_-]*)\*$")
# API / message constant globs in prose (`MSG_WIN*`, `SYS_WIN*`), not checks.
API_GLOB_RE = re.compile(r"^[A-Z][A-Z0-9_]*\*$")
# Abbreviated slash forms after a full name: `diskutil-fmt12` / `16` / `32`.
SHORT_SUFFIX_RE = re.compile(r"^[0-9]{1,4}$")

# check / check_all / check_all_retry / check_retry / check_none NAME ...
# Leading whitespace is allowed (flavour-split bodies indent the call).
CHECK_DEF_RE = re.compile(
    r"^\s*(?:check|check_all|check_all_retry|check_retry|check_none)\s+(\S+)\b",
    re.MULTILINE,
)


def repo_rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def load_allowlist(path: Path) -> set[tuple[str, str, str]]:
    """Return set of (rule, doc, check) triples. Empty file / missing = none.

    Allowlist line format (whitespace-separated):
      <rule> <doc> <check>
    where rule is missing-check or unexpected-check.
    Lines starting with # and blank lines are ignored.
    """
    out: set[tuple[str, str, str]] = set()
    if not path.is_file():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 2)
        if len(parts) != 3:
            raise SystemExit(
                f"docs_lint: bad allowlist line in {path}: {raw!r}"
            )
        rule, doc, check = parts
        if rule not in ("missing-check", "unexpected-check"):
            raise SystemExit(
                f"docs_lint: unknown allowlist rule {rule!r} in {path}"
            )
        out.add((rule, doc, check))
    return out


def expand_slash_abbrevs(tokens: list[str]) -> list[str]:
    """Expand `diskutil-fmt12` / `16` / `32` style abbreviation lists."""
    if not tokens:
        return tokens
    out: list[str] = []
    prefix: str | None = None
    for tok in tokens:
        t = tok.strip().rstrip(".,;)")
        if not t:
            continue
        if SHORT_SUFFIX_RE.match(t) and prefix is not None:
            # Replace the trailing run of digits on the last full name.
            m = re.match(r"^(.*?)(\d+)$", prefix)
            if m:
                out.append(m.group(1) + t)
                continue
        out.append(t)
        if re.search(r"\d+$", t) and not GLOB_RE.match(t):
            prefix = t
        elif not SHORT_SUFFIX_RE.match(t):
            prefix = None
    return out


def is_check_token(token: str) -> bool:
    """True when a backtick token is shaped like a regress check name."""
    t = token.strip().rstrip(".,;)")
    if not t:
        return False
    if PASS_TICK_RE.match(t):
        return True
    if API_GLOB_RE.match(t):
        return False
    if GLOB_RE.match(t):
        return True
    if CHECK_NAME_RE.match(t):
        return True
    return False


def extract_named_checks(body: str) -> list[str]:
    """Return unique check names named by a checkbox body, in order."""
    found: list[str] = []
    seen: set[str] = set()

    def add(name: str) -> None:
        name = name.strip().rstrip(".,;)")
        if not name or name in seen:
            return
        # `foo: PASS` → check name `foo`.
        pm = PASS_TICK_RE.match(name)
        if pm:
            name = pm.group(1)
        if not name or name in seen:
            return
        seen.add(name)
        found.append(name)

    # Explicit "Check(s) `…`" — also gather neighbouring backtick tokens in
    # the same Checks clause (comma / slash lists).
    for m in EXPLICIT_CHECK_RE.finditer(body):
        start = m.start()
        # Take from this match through the next sentence break or end.
        tail = body[start:]
        # Stop at a second sentence (". " after the clause) or arrow prose
        # that is not part of the list; keep `/` and `,` separated ticks.
        clause = re.split(r"(?:\.\s|\n)", tail, maxsplit=1)[0]
        # Drop trailing "→ `foo: PASS`" companion — handled via PASS ticks.
        clause = re.split(r"\s+→\s+", clause, maxsplit=1)[0]
        ticks = BACKTICK_RE.findall(clause)
        # First tick is the one EXPLICIT_CHECK_RE already captured; expand
        # slash abbrevs across the list.
        expanded = expand_slash_abbrevs(ticks)
        for tok in expanded:
            # Skip host-tool phrases ("fatimg.py check") and bold box refs.
            if "/" in tok or " " in tok or tok.endswith(".py"):
                continue
            if tok.startswith("TODO.md") or tok.startswith("ROADMAP"):
                continue
            if is_check_token(tok) or SHORT_SUFFIX_RE.match(
                tok.strip().rstrip(".,;)")
            ):
                # Short suffixes already expanded; skip raw leftovers.
                if SHORT_SUFFIX_RE.match(tok.strip().rstrip(".,;)")):
                    continue
                add(tok)
            elif re.match(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$", tok):
                # Explicit Checks lists sometimes name plain tokens
                # (waitcycle, stackover) that are not kebab-case.
                add(tok)

    # `name: PASS` ticks anywhere on the box line.
    for tok in BACKTICK_RE.findall(body):
        if PASS_TICK_RE.match(tok.strip().rstrip(".,;)")):
            add(tok)

    # Harness-shaped bare ticks (kebab / *test / glob) that are not paths.
    for tok in BACKTICK_RE.findall(body):
        t = tok.strip().rstrip(".,;)")
        if PASS_TICK_RE.match(t):
            continue
        if is_check_token(t):
            add(t)

    return found


def parse_boxes(doc: Path) -> list[dict]:
    boxes: list[dict] = []
    text = doc.read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), 1):
        m = BOX_RE.match(line)
        if not m:
            continue
        checked = m.group(2).lower() == "x"
        body = m.group(3)
        checks = extract_named_checks(body)
        if not checks:
            continue
        boxes.append(
            {
                "doc": repo_rel(doc),
                "lineno": lineno,
                "checked": checked,
                "body": body,
                "checks": checks,
            }
        )
    return boxes


def collect_harness(root: Path) -> dict[str, set[str] | dict[str, str]]:
    """Parse check / check_all / check_none names (and expected strings)."""
    regress = root / "tools" / "regress.sh"
    names: set[str] = set()
    expected: dict[str, str] = {}
    if not regress.is_file():
        return {"names": names, "expected": expected}

    text = regress.read_text(encoding="utf-8", errors="replace")
    for m in CHECK_DEF_RE.finditer(text):
        names.add(m.group(1))

    # Optional: map name → first expected string for PASS-prefix matching.
    exp_re = re.compile(
        r"^\s*(?:check|check_all|check_all_retry|check_retry|check_none)\s+(\S+)\s+'([^']*)'",
        re.MULTILINE,
    )
    for m in exp_re.finditer(text):
        names.add(m.group(1))
        expected.setdefault(m.group(1), m.group(2))

    return {"names": names, "expected": expected}


def glob_matches(pattern: str, names: set[str]) -> list[str]:
    """Match a simple prefix glob (`fat12-*`) against harness names."""
    if not pattern.endswith("*"):
        return [pattern] if pattern in names else []
    prefix = pattern[:-1]
    return sorted(n for n in names if n.startswith(prefix))


def check_exists(name: str, harness: dict) -> bool:
    names: set[str] = harness["names"]  # type: ignore[assignment]
    expected: dict[str, str] = harness["expected"]  # type: ignore[assignment]
    n = name.strip().rstrip(".,;)")
    if not n:
        return False
    if GLOB_RE.match(n):
        return bool(glob_matches(n, names))
    if n in names:
        return True
    # Docs often write the PASS string (`bevel: PASS`) while the check is
    # named differently (`bevtest`). Count as present when any check's
    # expected text contains "`n`: PASS" or "`n`: PASS" without ticks.
    needle = f"{n}: PASS"
    if any(needle in exp for exp in expected.values()):
        return True
    return False


def lint(
    root: Path,
    allowlist: set[tuple[str, str, str]],
) -> tuple[list[str], list[str]]:
    """Return (errors, notes). errors non-empty => failure."""
    harness = collect_harness(root)
    errors: list[str] = []
    notes: list[str] = []
    boxes: list[dict] = []
    for name in DOC_NAMES:
        doc = root / name
        if doc.is_file():
            boxes.extend(parse_boxes(doc))

    used_allow: set[tuple[str, str, str]] = set()

    for box in boxes:
        for check in box["checks"]:
            exists = check_exists(check, harness)
            if box["checked"]:
                if exists:
                    continue
                key = ("missing-check", box["doc"], check)
                if key in allowlist:
                    used_allow.add(key)
                    notes.append(
                        f"allowlist missing-check {box['doc']}:{box['lineno']}"
                        f" `{check}`"
                    )
                    continue
                errors.append(
                    f"{box['doc']}:{box['lineno']}: checked box names `{check}` "
                    f"but that check is not in tools/regress.sh"
                )
            else:
                if not exists:
                    continue
                key = ("unexpected-check", box["doc"], check)
                if key in allowlist:
                    used_allow.add(key)
                    notes.append(
                        f"allowlist unexpected-check {box['doc']}:{box['lineno']}"
                        f" `{check}`"
                    )
                    continue
                errors.append(
                    f"{box['doc']}:{box['lineno']}: open box names `{check}` "
                    f"but that check already exists in tools/regress.sh"
                )

    unused = allowlist - used_allow
    for rule, doc, check in sorted(unused):
        notes.append(f"unused allowlist entry: {rule} {doc} {check}")

    return errors, notes


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--root",
        type=Path,
        default=ROOT,
        help="repository root (default: parent of tools/)",
    )
    ap.add_argument(
        "--allowlist",
        type=Path,
        default=None,
        help="allowlist file (default: tools/docs_lint_allowlist.txt)",
    )
    ap.add_argument(
        "--list-checks",
        action="store_true",
        help="print named checks from docs and exit 0",
    )
    args = ap.parse_args(argv)
    root = args.root.resolve()
    allow_path = args.allowlist or (root / "tools" / "docs_lint_allowlist.txt")
    allowlist = load_allowlist(allow_path)

    if args.list_checks:
        for name in DOC_NAMES:
            doc = root / name
            if not doc.is_file():
                continue
            for box in parse_boxes(doc):
                state = "x" if box["checked"] else " "
                checks = ", ".join(f"`{c}`" for c in box["checks"])
                print(f"{box['doc']}:{box['lineno']}: [{state}] {checks}")
        return 0

    errors, notes = lint(root, allowlist)
    for n in notes:
        print(f"note: {n}", file=sys.stderr)
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        print(
            f"docs_lint: {len(errors)} honesty issue(s)",
            file=sys.stderr,
        )
        return 1

    nboxes = sum(
        1
        for name in DOC_NAMES
        if (root / name).is_file()
        for _ in parse_boxes(root / name)
    )
    nchecks = len(collect_harness(root)["names"])
    print(
        f"docs_lint: ok ({nboxes} box(es) naming checks; "
        f"{nchecks} regress check names)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
