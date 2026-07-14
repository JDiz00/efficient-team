#!/usr/bin/env bash
# efficient-codex test suite.
#   (default)  static checks + deterministic tier-flag matrix on the owned bin/codex-route
#   --live     adds real Codex probes: main-thread rollout proves --luna and --terra route
# Exit non-zero if any check fails.
set -uo pipefail

LIVE=0; [ "${1:-}" = "--live" ] && LIVE=1
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SRC="$(cd "$(dirname "$0")/.." && pwd)"
ROUTE="$SRC/bin/codex-route"
STUB="$(mktemp -d /tmp/eff-codex-stub-XXXXXX)" || { echo "FATAL: mktemp failed"; exit 1; }
[ -n "$STUB" ] && [ -d "$STUB" ] || { echo "FATAL: no temp dir"; exit 1; }
trap 'rm -rf "$STUB"' EXIT

# --- 1. SKILL.md descriptions within Codex's 1024-char hard limit ---
for f in "$SRC"/skills/*/SKILL.md; do
  len=$(python3 - "$f" <<'EOF'
import re,sys
m=re.search(r'^description:\s*(.*?)$', open(sys.argv[1]).read(), re.M)
print(len(m.group(1)) if m else 9999)
EOF
)
  if [ "$len" -le 1024 ]; then ok "description <=1024 ($len): $(basename "$(dirname "$f")")"; else bad "description too long ($len): $f"; fi
done

# --- 2. Example agent TOMLs parse and pin the expected models (forward-compat docs) ---
if python3 - "$SRC" <<'EOF'
import tomllib, sys, pathlib
src = pathlib.Path(sys.argv[1]) / "examples" / "agents"
want = {"sol-lead": "gpt-5.6-sol", "terra-builder": "gpt-5.6-terra", "luna-worker": "gpt-5.6-luna"}
for name, model in want.items():
    d = tomllib.load(open(src / f"{name}.toml", "rb"))
    assert d["name"] == name and d["model"] == model, (name, d.get("model"))
    assert d["model_reasoning_effort"] in ("low", "medium", "high"), name
    assert d["developer_instructions"].strip(), name
EOF
then ok "example TOMLs parse and pin models"; else bad "example TOML check"; fi

# --- 3. codex-route tier matrix (deterministic; a stub `codex` records the argv) ---
cat > "$STUB/codex" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${CODEX_STUB_OUT:?}"
exit 0
EOS
chmod +x "$STUB/codex"

route_argv() { CODEX_STUB_OUT="$STUB/a.txt" PATH="$STUB:$PATH" "$ROUTE" "$@" >/dev/null 2>&1; cat "$STUB/a.txt" 2>/dev/null; }
has() { grep -qx "$1" "$STUB/a.txt"; }
after() { # value that follows arg $1 in the recorded argv
  awk -v k="$1" 'prev==k{print;exit} {prev=$0}' "$STUB/a.txt"
}

check_tier() { # <flag> <want-model> <want-effort>
  route_argv "$1" "probe" -C /tmp >/dev/null
  local m e; m="$(after -m)"; e="$(after -c)"
  if [ "$m" = "$2" ] && printf '%s' "$e" | grep -q "\"$3\""; then
    ok "$1 -> $2 / $3"
  else bad "$1 gave model=$m effort_arg=$e (want $2 / $3)"; fi
}
check_tier --luna  gpt-5.6-luna  low
check_tier --terra gpt-5.6-terra medium
check_tier --sol   gpt-5.6-sol   high

# effort override keeps the tier model
route_argv --luna "probe" -C /tmp --xhigh >/dev/null
if [ "$(after -m)" = "gpt-5.6-luna" ] && after -c | grep -q '"xhigh"'; then ok "--luna --xhigh -> luna / xhigh (override)"; else bad "--luna --xhigh override wrong"; fi
# order independence
route_argv --xhigh "probe" -C /tmp --luna >/dev/null
if [ "$(after -m)" = "gpt-5.6-luna" ] && after -c | grep -q '"xhigh"'; then ok "order-independent effort override"; else bad "order-dependent override"; fi

# conflicting tiers exit 2
CODEX_STUB_OUT="$STUB/a.txt" PATH="$STUB:$PATH" "$ROUTE" --luna --sol "probe" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "conflicting tier flags exit 2" || bad "conflicting tier flags did not exit 2"
# missing tier exits 2 (prompt present, no tier flag)
CODEX_STUB_OUT="$STUB/a.txt" PATH="$STUB:$PATH" "$ROUTE" "probe" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "no tier flag exits 2" || bad "missing tier did not exit 2"
# missing prompt exits 2
CODEX_STUB_OUT="$STUB/a.txt" PATH="$STUB:$PATH" "$ROUTE" --luna >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "no prompt exits 2" || bad "missing prompt did not exit 2"
# --- parser boundaries (Codex sign-off finding) ---
# prompt starting with a dash needs -- ; before that it must be rejected, after it accepted
CODEX_STUB_OUT="$STUB/a.txt" PATH="$STUB:$PATH" "$ROUTE" --luna "-looks-like-flag" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "dash-prompt without -- is rejected" || bad "dash-prompt without -- not rejected"
route_argv --luna -- "-looks-like-flag" >/dev/null
# The forwarded codex argv must place `--` immediately before the dash-prompt, or codex exec
# reinterprets it as an option (the round-2 sign-off bug). Assert the separator is adjacent.
if grep -qx -- '-looks-like-flag' "$STUB/a.txt" && [ "$(after --)" = "-looks-like-flag" ]; then
  ok "-- forwarded adjacent to dash-prompt"
else bad "-- not forwarded adjacent to dash-prompt (codex exec would misparse it)"; fi
# -C sets dir; extra positional after prompt is rejected (no silent dir clobber)
route_argv --luna "probe" -C /var/tmp >/dev/null
if [ "$(after -C)" = "/var/tmp" ]; then ok "-C sets working dir" ; else bad "-C did not set dir (got $(after -C))"; fi
CODEX_STUB_OUT="$STUB/a.txt" PATH="$STUB:$PATH" "$ROUTE" --luna "probe" "extra-positional" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "excess positional rejected" || bad "excess positional silently accepted"

# --- 4. Installed skill copies match source (only meaningful after install.sh) ---
for pair in \
  "$SRC/skills/efficient-codex/SKILL.md:$HOME/.codex/skills/efficient-codex/SKILL.md" \
  "$SRC/skills/efficient-opus/SKILL.md:$HOME/.claude/skills/efficient-opus/SKILL.md" \
  "$SRC/skills/efficient-team/SKILL.md:$HOME/.claude/skills/efficient-team/SKILL.md"; do
  s="${pair%%:*}"; d="${pair##*:}"
  if [ ! -e "$d" ]; then echo "SKIP (not installed): $d"
  elif cmp -s "$s" "$d"; then ok "installed copy current: $(basename "$(dirname "$d")")"
  else bad "installed copy differs from source: $d"; fi
done

# --- 6. LIVE: real Codex calls, prove the tier reached the main thread via rollout log ---
if [ "$LIVE" -eq 1 ]; then
  command -v codex >/dev/null 2>&1 || { echo "SKIP live: codex CLI not installed"; echo "--- $PASS passed, $FAIL failed ---"; exit $((FAIL>0)); }
  live_tier() { # <tier-flag> <expected-model>
    local M; M="$(mktemp /tmp/eff-codex-marker-XXXXXX)"; sleep 1
    "$ROUTE" "$1" "Reply with exactly: ROUTED" -C /tmp </dev/null >/dev/null 2>&1 || { bad "live $1: codex-route exited non-zero"; rm -f "$M"; return; }
    if python3 - "$M" "$HOME/.codex/sessions" "$2" <<'EOF'
import sys, os, json, pathlib
marker=os.path.getmtime(sys.argv[1]); root=pathlib.Path(sys.argv[2]); want=sys.argv[3]
fresh=[p for p in root.rglob("rollout-*.jsonl") if p.stat().st_mtime>=marker]
if not fresh: print("no fresh rollout (fail-closed)"); sys.exit(1)
for p in fresh:
    for line in p.read_text(errors="replace").splitlines():
        try: o=json.loads(line)
        except Exception: continue
        if o.get("type")=="turn_context":
            m=o.get("payload",{}).get("model")
            if m==want: print(f"{want} confirmed in {p.name}"); sys.exit(0)
print(f"no fresh main-thread ran on {want} (fail-closed)"); sys.exit(1)
EOF
    then ok "live: $1 routed main thread to $2"; else bad "live: $1 did not route to $2 (fail-closed)"; fi
    rm -f "$M"
  }
  echo "--- live tier routing (a few cents) ---"
  live_tier --luna  gpt-5.6-luna
  live_tier --terra gpt-5.6-terra
fi

echo "--- $PASS passed, $FAIL failed ---"
exit $((FAIL>0))
