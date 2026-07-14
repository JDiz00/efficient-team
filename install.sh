#!/usr/bin/env bash
# efficient-team installer — installs all three skills and the codex-route wrapper.
# Usage: ./install.sh [--force] [--agents-compat]
#   --force          overwrite existing installed files
#   --agents-compat  also mirror the Codex skill to ~/.agents/skills/ (official docs
#                    location; some setups block or ignore it — default off)
#
# Installs:
#   efficient-codex  -> ~/.codex/skills/    (Codex-side tier routing)
#   efficient-opus   -> ~/.claude/skills/   (Claude-side subagent routing)
#   efficient-team   -> ~/.claude/skills/   (one-switch combiner; needs the two above)
#   codex-route      -> ~/.local/bin/       (portable tier-routing wrapper)
#
# NOTE: the example agent TOMLs in examples/agents/ are NOT installed — on Codex 0.144.4
# per-agent model pins do not take effect, and dropping them in the live ~/.codex/agents/
# namespace would be inert-but-global. They are forward-compat documentation only.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
FORCE=0; COMPAT=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --agents-compat) COMPAT=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

copy() { # copy <src> <dst> [mode] — no-clobber unless --force, symlink-safe.
  # Returns 0 and sets COPIED=1 when it writes; sets COPIED=0 on skip.
  local s="$1" d="$2" mode="${3:-}"
  COPIED=0
  if [ -e "$d" ] || [ -L "$d" ]; then
    if [ "$FORCE" -ne 1 ]; then
      echo "SKIP (exists, use --force): $d"
      return 0
    fi
    rm -f "$d"   # never write through an existing symlink
  fi
  mkdir -p "$(dirname "$d")"
  cp "$s" "$d"
  [ -n "$mode" ] && chmod "$mode" "$d"   # only when we actually wrote (no-clobber safe)
  COPIED=1
  echo "WROTE: $d"
}

copy "$SRC/skills/efficient-codex/SKILL.md" "$HOME/.codex/skills/efficient-codex/SKILL.md"
copy "$SRC/skills/efficient-opus/SKILL.md"  "$HOME/.claude/skills/efficient-opus/SKILL.md"
copy "$SRC/skills/efficient-team/SKILL.md"  "$HOME/.claude/skills/efficient-team/SKILL.md"
copy "$SRC/bin/codex-route"                 "$HOME/.local/bin/codex-route" 0755
if [ "$COMPAT" -eq 1 ]; then
  copy "$SRC/skills/efficient-codex/SKILL.md" "$HOME/.agents/skills/efficient-codex/SKILL.md"
fi

# Warn if ~/.local/bin isn't on PATH — codex-route won't be found otherwise.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *) echo
     echo "NOTE: \$HOME/.local/bin is not on your PATH, so 'codex-route' won't be found yet."
     echo "      Add this to your shell profile (~/.bashrc or ~/.zshrc):"
     echo "        export PATH=\"\$HOME/.local/bin:\$PATH\""
     echo "      Then open a new shell (or 'source' the profile)." ;;
esac

echo
echo "Installed. Next steps:"
echo "  - Codex: '\$efficient-codex' in any prompt, or let the description trigger it."
echo "  - Route a call to a tier:  codex-route --luna|--terra|--sol \"task\" [-C dir]"
echo "  - Claude Code: '/efficient-team' to enable both halves at once."
