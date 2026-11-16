#!/bin/sh
# Optional lab / ground-station profile build (squirrel-os2#225).
# OFF unless ENABLE_SQUIRREL_LAB=1. Does not call tools/build.sh or
# tools/regress.sh and does not alter default images under build/.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
[ -f "$root/lab/profile.sh" ] && . "$root/lab/profile.sh"

if [ "${ENABLE_SQUIRREL_LAB:-0}" != 1 ]; then
    echo "lab profile off (set ENABLE_SQUIRREL_LAB=1 to enable); see lab/README.md"
    exit 0
fi

# Scaffold only — no serial/HIL/packaging yet.
echo "lab profile enabled (scaffold): no packaging/serial/HIL steps yet"
echo "see lab/README.md and https://github.com/squirelworks/squirrel-os2/issues/225"
exit 0
