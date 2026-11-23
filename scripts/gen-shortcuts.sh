#!/usr/bin/env bash
# Generate the shipped shortcut cheat sheet from the real Hyprland config.
#
#   scripts/gen-shortcuts.sh                      # write learning/shortcuts.md
#   scripts/gen-shortcuts.sh --check              # fail if the file is stale
#   scripts/gen-shortcuts.sh --config F --text T --out O
#
# The bindings are read from `hl.bind(...)` calls in configs/hypr/hyprland.lua --
# the file Hyprland 0.57 actually loads -- so a key that is added, changed or
# removed in the compositor config cannot survive in the documentation: every
# bind must have a line in configs/hypr/shortcuts.tsv and every line in that
# file must match a bind. The static sections (live-only keys, escape hatches)
# are appended from configs/hypr/shortcuts-extra.md.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$PROJECT_ROOT/configs/hypr/hyprland.lua"
TEXT="$PROJECT_ROOT/configs/hypr/shortcuts.tsv"
EXTRA="$PROJECT_ROOT/configs/hypr/shortcuts-extra.md"
OUT="$PROJECT_ROOT/learning/shortcuts.md"
check=0

while (( $# )); do
  case "$1" in
    --check) check=1 ;;
    --config) CONFIG="$2"; shift ;;
    --text)   TEXT="$2"; shift ;;
    --extra)  EXTRA="$2"; shift ;;
    --out)    OUT="$2"; shift ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

for f in "$CONFIG" "$TEXT" "$EXTRA"; do
  [[ -f "$f" ]] || { echo "missing $f" >&2; exit 2; }
done

# The bind keys of the config, in file order, normalised to "SUPER + Q" form.
#
#   hl.bind(mod .. " + Q",  ...)            -> SUPER + Q
#   hl.bind(mod .. " + SHIFT + Q", ...)     -> SUPER + SHIFT + Q
#   hl.bind("XF86AudioMute", ...)           -> XF86AudioMute
#   hl.bind(mod .. " + " .. key, ...)       -> SUPER + 1..0 (<dispatcher>)
mapfile -t binds < <(
  grep -E '^[[:space:]]*hl\.bind\(' "$CONFIG" | while IFS= read -r line; do
    dispatch="$(sed -E 's/.*hl\.dsp\.([A-Za-z_.]+).*/\1/' <<<"$line")"
    arg="${line#hl.bind(}"
    # The columns are aligned with runs of spaces, so the first argument ends at
    # the first ",<spaces>hl.dsp." on the line.
    arg="${arg%%, *hl.dsp.*}"
    key="$(sed -E \
      -e 's/mod \.\. /SUPER /g' \
      -e 's/ \+ " \.\. key/ + @LOOP@/g' \
      -e 's/"//g' \
      -e 's/[[:space:]]+/ /g' \
      -e 's/^ //; s/ $//' <<<"$arg")"
    # The workspace loop generates one bind per number; it is documented once.
    if [[ "$key" == *@LOOP@* ]]; then
      key="SUPER + <loop> ($dispatch)"
    fi
    printf '%s\t%s\n' "$key" "$dispatch"
  done
)

(( ${#binds[@]} )) || { echo "no hl.bind() lines found in $CONFIG" >&2; exit 1; }

declare -A action=() section=() used=() section_seen=()
sections=()
while IFS=$'\t' read -r sec key desc; do
  [[ -z "${sec:-}" || "${sec:0:1}" == "#" ]] && continue
  if [[ -n "${action[$key]:-}" ]]; then
    echo "duplicate shortcut in $TEXT: $key" >&2
    exit 1
  fi
  action["$key"]="$desc"
  section["$key"]="$sec"
  if [[ -z "${section_seen[$sec]:-}" ]]; then
    section_seen["$sec"]=1
    sections+=("$sec")
  fi
done < "$TEXT"

# Every bind must be documented, and every documented key must exist.
missing=0
for entry in "${binds[@]}"; do
  key="${entry%%$'\t'*}"
  used["$key"]=1
  if [[ -z "${action[$key]:-}" ]]; then
    echo "UNDOCUMENTED bind in $CONFIG: $key" >&2
    missing=1
  fi
done
for key in "${!action[@]}"; do
  if [[ -z "${used[$key]:-}" ]]; then
    echo "STALE line in $TEXT: $key is not a bind in $CONFIG" >&2
    missing=1
  fi
done
(( missing == 0 )) || { echo "the shortcut sheet would drift from the config; fix the two files above" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

{
  cat <<'EOF'
# MahaDevan's OS — keyboard shortcuts

**Super is the Windows key.** It is the modifier every MahaDevan's OS shortcut
starts with, so `Super + Q` means "hold the Windows key and press Q".

This sheet is generated from the real compositor configuration
(`/etc/xdg/hypr/hyprland.lua`, source `configs/hypr/hyprland.lua`), so it cannot
drift from what the desktop actually does. Do not edit it by hand:
`mhelp keys` shows this file, `scripts/gen-shortcuts.sh` regenerates it.

EOF

  for sec in "${sections[@]}"; do
    printf '## %s\n\n| Shortcut | Action |\n|---|---|\n' "$sec"
    while IFS=$'\t' read -r s key desc; do
      [[ "${s:0:1}" == "#" || -z "${s:-}" ]] && continue
      [[ "$s" == "$sec" ]] || continue
      display="${key//+/+}"
      case "$display" in
        *mouse_down*) display="SUPER + scroll down" ;;
        *mouse_up*)   display="SUPER + scroll up" ;;
        *mouse:272*)  display="SUPER + left drag" ;;
        *mouse:273*)  display="SUPER + right drag" ;;
      esac
      printf '| `%s` | %s |\n' "$display" "$desc"
    done < "$TEXT"
    printf '\n'
  done

  cat "$EXTRA"
} >"$tmp"

if (( check )); then
  if [[ ! -f "$OUT" ]]; then
    echo "$OUT does not exist; run scripts/gen-shortcuts.sh" >&2
    exit 1
  fi
  if ! diff -u "$OUT" "$tmp" >/dev/null; then
    echo "$OUT is stale: the config and the sheet disagree" >&2
    diff -u "$OUT" "$tmp" | head -40 >&2 || true
    exit 1
  fi
  echo "ok: $OUT matches $CONFIG (${#binds[@]} binds)"
  exit 0
fi

mkdir -p "$(dirname "$OUT")"
cat "$tmp" >"$OUT"
echo "wrote $OUT (${#binds[@]} binds, ${#sections[@]} sections)"
