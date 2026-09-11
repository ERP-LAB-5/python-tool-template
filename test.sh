#!/usr/bin/env bash
# Test the template by using it: render every option set, and prove each result
# works the way a person and an agent would use it.
#
#   ./test.sh                 everything below
#   ./test.sh --quick         render + each tool's own ./test.sh only
#   KEEP=1 ./test.sh          leave the rendered tools behind to inspect
#
# For each answer set in tests/answers-*.yml:
#   1. copier copy it into a scratch directory
#   2. its own ./test.sh passes (its tests include tests/test_core.py)
#   3. pip install it into a fresh venv: templates, static, VERSION, skill ship
#   4. ./run.sh starts it; health, page, core assets answer; restart comes
#      back; ./run.sh --stop frees the port
#   5. with MCP: the plugin launcher installs it and the MCP server saves and
#      reads a note through the web server it autostarts
#   6. claude plugin validate, when the claude CLI is on PATH
# Then a copier update round trip: a core change arrives, tool-owned files stay.
set -euo pipefail
cd "$(dirname "$0")"
unset PYTHONPATH
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

COPIER=${COPIER:-$(command -v copier || echo "$HOME/.local/share/dlab5-tools/copier/bin/copier")}
if [ ! -x "$COPIER" ]; then
  echo "  installing copier into ~/.local/share/dlab5-tools/copier ..."
  python3 -m venv "$HOME/.local/share/dlab5-tools/copier"
  "$HOME/.local/share/dlab5-tools/copier/bin/pip" install --quiet copier
  COPIER="$HOME/.local/share/dlab5-tools/copier/bin/copier"
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pytool-template-test.XXXXXX")
cleanup() {
  # never leave a test server holding a port
  for port in 18780 18781 18782; do
    curl -fsS -X POST "http://127.0.0.1:$port/api/shutdown" >/dev/null 2>&1 || true
  done
  if [ "${KEEP:-0}" = 1 ]; then echo "  kept $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
fail() { echo "  ! $*" >&2; exit 1; }

wait_for() {  # url
  for _ in $(seq 1 50); do curl -fsS "$1" >/dev/null 2>&1 && return 0; sleep 0.2; done
  fail "nothing answered at $1"
}

# The template is rendered from a copy with the working tree committed, so
# uncommitted template edits are what gets tested, and copier sees a clean repo.
SRC="$WORK/template"
mkdir -p "$SRC"
tar --exclude=.git --exclude=.venv -cf - . | tar -xf - -C "$SRC"
git -C "$SRC" init -q -b main
git -C "$SRC" add -A
git -C "$SRC" -c user.name=test -c user.email=test@localhost commit -qm "test snapshot"
git -C "$SRC" tag v0.0.1

port=18780
for answers in tests/answers-*.yml; do
  set_name=$(basename "$answers" .yml)
  dst="$WORK/$set_name"
  say "$set_name → $dst"

  "$COPIER" copy --quiet --trust --defaults --vcs-ref v0.0.1 \
    --data-file "$answers" --data port=$port "$SRC" "$dst"
  pkg=$(sed -n 's/^package_name: //p' "$dst/.copier-answers.yml")
  tool=$(sed -n 's/^tool_name: //p' "$dst/.copier-answers.yml")
  with_mcp=$(sed -n 's/^with_mcp: //p' "$dst/.copier-answers.yml")
  with_plugin=$(sed -n 's/^with_plugin: //p' "$dst/.copier-answers.yml")

  echo "  -- its own test suite"
  (cd "$dst" && ./test.sh -q)

  [ "$QUICK" = 1 ] && { port=$((port + 1)); continue; }

  echo "  -- pip install into a fresh venv"
  python3 -m venv "$WORK/venv-$set_name"
  "$WORK/venv-$set_name/bin/pip" install --quiet "$dst"
  site=$("$WORK/venv-$set_name/bin/python" -c "import $pkg, os; print(os.path.dirname($pkg.__file__))")
  for f in VERSION templates/index.html static/app.js skill/SKILL.md \
           core/static/core.js core/static/core.css core/static/dlab5.png \
           core/templates/core/_base.html; do
    [ -f "$site/$f" ] || fail "pip install did not ship $f"
  done
  echo "  package data complete"

  echo "  -- run.sh, endpoints, restart, stop"
  (cd "$dst" && ./run.sh --no-update-check --port $port > "$WORK/$set_name-run.log" 2>&1 &)
  wait_for "http://127.0.0.1:$port/api/health"
  curl -fsS "http://127.0.0.1:$port/api/health" | grep -q "\"tool\":\"$tool\"" || fail "health names another tool"
  for path in / /core-static/core.js /core-static/core.css /api/version /static/app.js; do
    curl -fsS -o /dev/null "http://127.0.0.1:$port$path" || fail "GET $path failed"
  done
  [ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$port/api/restart")" = 200 ] \
    || fail "restart refused a local caller"
  sleep 1.2
  wait_for "http://127.0.0.1:$port/api/health"
  (cd "$dst" && ./run.sh --port $port --stop >/dev/null)
  if ss -ltn 2>/dev/null | grep -q ":$port "; then fail "port $port still held after --stop"; fi
  echo "  started, answered, restarted, stopped"

  if [ "$with_mcp" = true ] && [ "$with_plugin" = true ]; then
    echo "  -- plugin MCP launcher (installs into a scratch XDG_DATA_HOME)"
    mkdir -p "$WORK/$set_name-agent-cwd"
    XDG_DATA_HOME="$WORK/xdg" DLAB5_TOOL_SOURCE="$dst" PYTHONPATH=/opt/not/here \
      timeout 300 "$dst/.venv/bin/python" tests/mcp_probe.py "$WORK/$set_name-agent-cwd" \
      python3 "$dst/plugin/bin/launch_mcp.py" --port $port 2> "$WORK/$set_name-mcp.log" \
      || { cat "$WORK/$set_name-mcp.log"; fail "MCP through the plugin launcher"; }
    [ -f "$WORK/$set_name-agent-cwd/"*/from-agent.json ] || fail "the agent's note did not land in the agent's working directory"
  fi

  if [ -d "$dst/plugin" ] && command -v claude >/dev/null; then
    claude plugin validate "$dst/plugin" >/dev/null || fail "claude plugin validate $dst/plugin"
    echo "  plugin manifest valid"
  fi
  port=$((port + 1))
done

[ "$QUICK" = 1 ] && { say "quick run passed"; exit 0; }

say "copier update: a core fix arrives, tool-owned edits survive"
dst="$WORK/answers-all-on"
(cd "$dst" && git init -q -b main && git add -A &&
 git -c user.name=test -c user.email=test@localhost commit -qm start)
# the tool changes a file it owns...
echo "/* the tool's own rule */" >> "$dst/$(sed -n 's/^package_name: //p' "$dst/.copier-answers.yml")/static/style.css"
(cd "$dst" && git -c user.name=test -c user.email=test@localhost commit -qam "tool edit")
# ...and the template ships a core fix
echo "/* core fix from the template */" >> "$SRC/template/{{package_name}}/core/static/core.css"
echo "# template-side change to a tool-owned file" >> "$SRC/template/{{package_name}}/static/style.css"
git -C "$SRC" -c user.name=test -c user.email=test@localhost commit -qam "core fix"
git -C "$SRC" tag v0.0.2
(cd "$dst" && "$COPIER" update --quiet --trust --defaults --vcs-ref v0.0.2 >/dev/null)
pkg=$(sed -n 's/^package_name: //p' "$dst/.copier-answers.yml")
changed=$(cd "$dst" && git status --porcelain | awk '{print $2}' | LC_ALL=C sort | tr '\n' ' ')
expected=$(printf '%s\n' .copier-answers.yml "$pkg/core/static/core.css" | LC_ALL=C sort | tr '\n' ' ')
[ "$changed" = "$expected" ] || fail "update changed [$changed], expected [$expected]"
grep -q "core fix from the template" "$dst/$pkg/core/static/core.css" || fail "core fix missing"
grep -q "the tool's own rule" "$dst/$pkg/static/style.css" || fail "tool edit lost"
grep -q "template-side change" "$dst/$pkg/static/style.css" && fail "update touched a tool-owned file"
echo "  core.css updated, style.css untouched"

say "all passed"
