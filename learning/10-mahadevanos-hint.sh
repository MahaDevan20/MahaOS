# One-line hint for interactive shells, once per terminal session.
#
# Installed as /etc/profile.d/10-mahadevanos-hint.sh, which every login shell
# sources -- including the shells kitty starts -- and in the live session too.
# MAHADEVANOS_HINT_SHOWN is exported, so a shell started from an already hinted
# shell stays quiet: one line per terminal session, not one per command.

case $- in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

[ -n "${MAHADEVANOS_HINT_SHOWN:-}" ] && return 0

MAHADEVANOS_HINT_SHOWN=1
export MAHADEVANOS_HINT_SHOWN

printf 'Type mhelp for commands, shortcuts and network help.\n'
