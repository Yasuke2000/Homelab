#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ROM Deduplication — 1G1R (One Game, One ROM)
# Priority: Europe > USA > World > Japan > Other
# Keeps highest revision per region. Dry-run by default.
# Usage: bash dedup-roms.sh /path/to/roms [--apply]
# ---------------------------------------------------------------------------
set -euo pipefail

ROM_ROOT="${1:?Usage: dedup-roms.sh /path/to/roms [--apply]}"
APPLY="${2:-}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TOTAL_REMOVED=0
TOTAL_KEPT=0
TOTAL_BYTES=0

# Score a file: region priority (lower=better), revision (higher=better)
score_file() {
    local f="$1"
    local rp=7 rv=0
    case "$f" in
        *"(Europe)"*|*"(En,Fr"*|*"(Europe,"*) rp=1 ;;
        *"(USA, Europe)"*|*"(USA,Europe)"*) rp=2 ;;
        *"(USA)"*) rp=3 ;;
        *"(World)"*) rp=4 ;;
        *"(Japan, USA)"*|*"(Japan,USA)"*) rp=5 ;;
        *"(Japan)"*) rp=6 ;;
    esac
    if [[ "$f" =~ \(Rev\ ([0-9]+)\) ]]; then
        rv="${BASH_REMATCH[1]}"
    fi
    # Combined score: lower region * 100, then subtract revision so higher rev wins
    echo $(( rp * 100 - rv ))
}

# Normalize: strip everything in parentheses, trim
normalize() {
    local n
    n=$(basename "$1")
    n="${n%.*}"
    # KEEP disc numbers in the normalized name so multi-disc games are NOT grouped
    # Extract disc info before stripping parentheses
    local disc=""
    if [[ "$n" =~ (Disc\ [0-9]+) ]]; then
        disc=" ${BASH_REMATCH[1]}"
    fi
    n=$(echo "$n" | sed -E 's/ *\([^)]*\)//g; s/^ *//; s/ *$//')
    echo "${n}${disc}"
}

echo "==========================================="
echo "ROM Deduplication — 1G1R"
echo "Priority: Europe > USA > World > Japan"
if [[ "$APPLY" == "--apply" ]]; then
    echo "MODE: *** APPLY — files WILL be deleted ***"
else
    echo "MODE: DRY-RUN"
fi
echo "==========================================="
echo

for platform_dir in "$ROM_ROOT"/*/; do
    [[ -d "$platform_dir" ]] || continue
    platform=$(basename "$platform_dir")
    platform_del=0

    # Build index: normalized_name \t score \t filepath
    > "$TMPDIR/index.tsv"
    find "$platform_dir" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' f; do
        norm=$(normalize "$f")
        sc=$(score_file "$(basename "$f")")
        printf '%s\t%s\t%s\n' "$norm" "$sc" "$f"
    done > "$TMPDIR/index.tsv"

    # Find games with multiple versions
    cut -f1 "$TMPDIR/index.tsv" | sort | uniq -d > "$TMPDIR/dupes.txt"

    while IFS= read -r game; do
        [[ -z "$game" ]] && continue

        # Get all versions, sort by score (lowest = best)
        grep -P "^\Q${game}\E\t" "$TMPDIR/index.tsv" 2>/dev/null | sort -t$'\t' -k2 -n > "$TMPDIR/versions.tsv" || \
        grep -F "${game}	" "$TMPDIR/index.tsv" | sort -t$'\t' -k2 -n > "$TMPDIR/versions.tsv"

        best=$(head -1 "$TMPDIR/versions.tsv" | cut -f3)

        while IFS=$'\t' read -r _norm _score filepath; do
            if [[ "$filepath" == "$best" ]]; then
                echo "  KEEP: $(basename "$filepath")"
                TOTAL_KEPT=$((TOTAL_KEPT + 1))
            else
                size=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
                TOTAL_BYTES=$((TOTAL_BYTES + size))
                TOTAL_REMOVED=$((TOTAL_REMOVED + 1))
                platform_del=$((platform_del + 1))
                if [[ "$APPLY" == "--apply" ]]; then
                    rm -f "$filepath"
                fi
                echo "  DEL:  $(basename "$filepath")"
            fi
        done < "$TMPDIR/versions.tsv"
    done < "$TMPDIR/dupes.txt"

    if (( platform_del > 0 )); then
        echo "  [$platform] $platform_del duplicates"
        echo
    fi
done

echo "==========================================="
echo "KEPT:    $TOTAL_KEPT (best version per game)"
echo "REMOVED: $TOTAL_REMOVED duplicates"
echo "SAVED:   ~$((TOTAL_BYTES / 1024 / 1024)) MiB"
if [[ "$APPLY" != "--apply" ]]; then
    echo ">>> DRY RUN — run with --apply to delete <<<"
fi
echo "==========================================="
