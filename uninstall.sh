#!/usr/bin/env bash
# efficient-codex uninstaller — removes installed copies and the enable flag.
# Safety: only removes a file if it matches this package's source (never deletes
# a pre-existing or user-modified file); otherwise leaves it and says so.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"

remove() { # remove <installed> <package-source>
  local d="$1" s="$2"
  if [ ! -e "$d" ] && [ ! -L "$d" ]; then echo "absent: $d"; return 0; fi
  if ! cmp -s "$d" "$s"; then
    echo "LEFT IN PLACE (differs from package source, not ours to delete): $d"
    return 0
  fi
  rm "$d" && echo "REMOVED: $d"
}

remove "$HOME/.codex/skills/efficient-codex/SKILL.md" "$SRC/skills/efficient-codex/SKILL.md"
rmdir "$HOME/.codex/skills/efficient-codex" 2>/dev/null || true
remove "$HOME/.claude/skills/efficient-opus/SKILL.md" "$SRC/skills/efficient-opus/SKILL.md"
rmdir "$HOME/.claude/skills/efficient-opus" 2>/dev/null || true
remove "$HOME/.claude/skills/efficient-team/SKILL.md" "$SRC/skills/efficient-team/SKILL.md"
rmdir "$HOME/.claude/skills/efficient-team" 2>/dev/null || true
remove "$HOME/.local/bin/codex-route" "$SRC/bin/codex-route"
remove "$HOME/.agents/skills/efficient-codex/SKILL.md" "$SRC/skills/efficient-codex/SKILL.md"
rmdir "$HOME/.agents/skills/efficient-codex" 2>/dev/null || true

# The flag is ours by definition.
if [ -f "$HOME/.codex/efficient-codex.on" ]; then
  rm "$HOME/.codex/efficient-codex.on" && echo "REMOVED: $HOME/.codex/efficient-codex.on"
else
  echo "absent: $HOME/.codex/efficient-codex.on"
fi
echo "Done."
