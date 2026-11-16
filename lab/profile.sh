# Optional ISM Flight Lab / ground-station host profile (squirrel-os2#225).
# OFF by default. Source from a shell:
#   . ./lab/profile.sh
#   enable_squirrel_lab    # sets ENABLE_SQUIRREL_LAB=1
#   ./lab/build.sh
# Default tools/build.sh and tools/regress.sh never source this file.

ENABLE_SQUIRREL_LAB="${ENABLE_SQUIRREL_LAB:-0}"

enable_squirrel_lab() {
    ENABLE_SQUIRREL_LAB=1
    export ENABLE_SQUIRREL_LAB
    echo "ENABLE_SQUIRREL_LAB=1 (optional lab profile on; see lab/README.md)"
}

disable_squirrel_lab() {
    ENABLE_SQUIRREL_LAB=0
    export ENABLE_SQUIRREL_LAB
    echo "ENABLE_SQUIRREL_LAB=0 (optional lab profile off)"
}

squirrel_lab_enabled() {
    [ "${ENABLE_SQUIRREL_LAB}" = 1 ]
}
