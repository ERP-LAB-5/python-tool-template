---
name: new-tool
description: Bootstrap a new D-LAB-5 Python tool from ERP-LAB-5/python-tool-template with Copier: a stdlib engine and CLI, a Flask page with About/update/restart/stop, optional MCP server, Windows launchers, workspace folders, release script, and a Claude Code plugin. Use when someone wants to start a new small full-stack Python tool, "scaffold a tool like metro-map-tool", "new tool from the template", or runs /pytool-kit:new-tool.
argument-hint: "[tool-name] [target-dir]"
---

# Start a new tool from the template

The user asked for: $ARGUMENTS

Read the `python-tool-template` skill first if it isn't already loaded. It
explains what gets generated and which files belong to whom.

If the person seems new to all this (they ask what a template, MCP or a plugin
is, or say they are "just trying an idea"), point them to
https://github.com/ERP-LAB-5/python-tool-template/blob/main/docs/for-the-curious.md.
It explains the concepts in plain language and encourages trying ideas you can
throw away.

## 1. Make sure Copier is available

Neither pipx nor uv is assumed. Copier lives in its own venv:

```bash
COPIER=~/.local/share/dlab5-tools/copier/bin/copier
if [ ! -x "$COPIER" ]; then
  (unset PYTHONPATH; python3 -m venv ~/.local/share/dlab5-tools/copier &&
   ~/.local/share/dlab5-tools/copier/bin/pip install --quiet copier)
fi
"$COPIER" --version
```

## 2. Settle the answers

Ask only for what you can't infer. Propose defaults and confirm them in one
question, not one question per field:

| Answer | Notes |
|---|---|
| `tool_name` | kebab-case; becomes the pip name, skill name and plugin name |
| `title`, `description` | the description is one line, reused in pyproject, the plugin and About |
| `repo_name` | its own repo by default; several tools may share one (sap-di-tools) |
| `port` | **must not clash.** Check with `ss -ltn` and the other tools' `.copier-answers.yml`: metro-map 8765, di-replication-sync 8766, then 8770+ |
| `cli_command`, `cli_module` | the command name; the module holding the engine (default `engine`) |
| `disclaimer` | e.g. "Unofficial. Not affiliated with, endorsed by or supported by SAP." for anything SAP-facing |
| `with_mcp` | yes if an agent should act through the tool, not just read its skill |
| `with_workspace` | yes if the tool keeps user documents (`mydocs/` + shipped samples) |
| `with_windows`, `with_release`, `with_plugin` | default yes |

Remember the existing ERP-LAB-5 tools as a reference point: metro-map-tool
(MCP + workspace), sap-di-tools/di-replication-sync (no MCP, its own `flows/`
folder).

## 3. Generate

Put the tool in `~/ERP-LAB-5/<repo_name>` unless told otherwise. Pass every
answer with `--data` and use `--defaults` for the rest, so nothing waits on a
prompt:

```bash
"$COPIER" copy --trust --defaults \
  --data tool_name=<name> --data title="<Title>" --data description="<one line>" \
  --data port=<port> [--data with_mcp=false …] \
  gh:ERP-LAB-5/python-tool-template ~/ERP-LAB-5/<repo_name>
```

Copier uses the newest tag of the template. Add `--vcs-ref <tag>` only to pin
an older one.

## 4. Prove it works before changing anything

```bash
cd ~/ERP-LAB-5/<repo_name>
git init -b main && git add -A
./test.sh                                   # the sample passes as generated
./run.sh --no-update-check &                # then open http://127.0.0.1:<port>
curl -s http://127.0.0.1:<port>/api/health  # {"ok": true, "tool": "<name>", ...}
./run.sh --stop
claude plugin validate plugin               # when with_plugin
```

Commit in ERP-LAB-5 style (a bare imperative sentence, e.g. "Start <name> from
the D-LAB-5 tool template"), with a body that records the template tag and the
options chosen.

## 5. Replace the sample

The generated tool is a working "notes" sample. Replace it one slice at a time,
following "Adding a feature" in the `python-tool-template` skill:
engine → route → page → MCP tool → skill → test. Rewrite `README.md` and the
skill's description (it still says REPLACE). Replace `static/favicon.svg` with
the tool's own mark. Leave `core/` alone.

## 6. Publish (only when the user says so)

Creating a GitHub repository is outward-facing, so confirm name and visibility
first:

```bash
gh repo create ERP-LAB-5/<repo_name> --public --source . --push
```

Then offer to add the tool to the `erp-lab-5` marketplace: an entry in
`python-tool-template/.claude-plugin/marketplace.json` with
`{"source": "git-subdir", "url": "https://github.com/ERP-LAB-5/<repo_name>.git", "path": "plugin"}`.
The plugin's MCP server installs `@v<VERSION>`, so it works once the first
release is tagged (`scripts/release.py`).
