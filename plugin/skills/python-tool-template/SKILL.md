---
name: python-tool-template
description: How D-LAB-5 small full-stack Python tools are built — a stdlib engine with a CLI, a Flask page on loopback, an optional MCP server, an agent skill shipped three ways, and a shared core maintained by Copier from ERP-LAB-5/python-tool-template. Use when working in any repository with a .copier-answers.yml from that template, or one that shows the tells (a <package>/core/ with identity.py, server.py and skill_install.py; run.sh that unsets PYTHONPATH; a VERSION file read by pyproject; plugin/bin/launch_mcp.py), such as metro-map-tool or sap-di-tools. Also use when asked to add a feature, endpoint, MCP tool or skill section to such a tool, to explain which files are core-owned, or to plan a new tool of this kind. Carries the constraints that bite, like ROS PYTHONPATH leaking into venvs, stdout being the MCP transport, symlinked skills breaking on Windows clones, loopback-only lifecycle endpoints, file descriptors surviving execv, and package-data omissions.
---

# The D-LAB-5 Python tool template

A tool built from this template is one Python package that serves three
audiences from one set of files:

| Audience | Entry point | Built on |
|---|---|---|
| a script or a person at a shell | `<cli>` → `<package>/<cli_module>.py` | standard library only |
| a person in a browser | `<cli>-web`, `./run.sh` → `<package>/app.py` | Flask + `core/server.py` |
| an agent | `<cli>-mcp` → `<package>/mcp_server.py`, and the skill | `mcp>=2` + `core/mcp_bridge.py` |

The browser and the agent work through **one web server and one set of files**.
The MCP server is a thin HTTP client of that server, not a second implementation
of it. So a save from either side shows up in the other.

## Read `.copier-answers.yml` first

It names the package, the port, the CLI command, and which options are on
(`with_mcp`, `with_windows`, `with_workspace`, `with_release`, `with_plugin`).
`<package>/core/identity.py` is generated from it and holds the same facts as
Python constants. Every core module reads its names from there.

## Who owns which file

**Core-owned.** `copier update` rewrites these files. Don't edit them in a tool
repository. Change them in the template and update.
- `<package>/core/**`: `identity.py`, `version.py`, `server.py`, `skill_install.py`,
  `mcp_bridge.py`, `workspace.py`, `static/core.{css,js}`, `static/dlab5.png`,
  `templates/core/_base.html`
- `run.sh`, `run.cmd`, `run.ps1`, `test.sh`, `.gitattributes`
- `tests/test_core.py`, `scripts/release.py`, `plugin/bin/launch_mcp.py`, `plugin/.mcp.json`, `.mcp.json`

**Tool-owned.** Generated once as a working "notes" sample, then yours.
`copier update` never touches them again:
`README.md`, `pyproject.toml`, `requirements.txt`, `requirements-dev.txt`,
`.gitignore` (tools add their own runtime-data ignores, and an update must never
drop one), `<package>/__init__.py`,
`VERSION`, `app.py`, `<cli_module>.py`, `mcp_server.py`, `skill/SKILL.md`,
`templates/index.html`, `static/*`, the shared samples, `.claude/settings.json`,
`plugin/.claude-plugin/plugin.json`, `plugin/bin/VERSION`,
`plugin/skills/<tool>/SKILL.md`, `.claude/skills/<tool>/SKILL.md`, and
`tests/test_<package>.py`.

If a core file really must differ in one tool, fix the template instead, so the
fix reaches every tool. Keep a local patch only if the tool is about to leave
the template.

## Adding a feature: one slice through every layer

Do these in order, and don't skip a layer the tool has:

1. **Engine** (`<cli_module>.py`): pure functions on plain data. Errors are a
   list of messages a person can act on. Add a `main()` subcommand if a person
   would run it. Standard library only.
2. **Route** (`app.py`): move data between the request and the engine, nothing
   else. Use `abort(400, "message")` for bad input; the core error handler turns
   it into `{"errors": [...]}`. If the route **writes, deletes, runs a
   subprocess or touches a credential**, call `server.only_local("what")`
   first.
3. **Page** (`templates/index.html` extends `core/_base.html`; `static/app.js`):
   use `core.api(method, path, payload)`, `core.dialog`, `core.toast`, and
   `core.esc` for anything interpolated into HTML. If the page holds unsaved
   state, register `core.setLeavingGuard((verb, go) => …)` so Stop and Restart
   ask first.
4. **MCP tool** (`mcp_server.py`): call pure engine functions in-process.
   Anything touching files goes through `web.ensure_server()` then
   `web.call(...)`. Write a docstring that says when to use the tool and what it
   returns. The docstring is the agent's only documentation.
5. **Skill** (`<package>/skill/SKILL.md`): add the section, then run
   `<cli>-skill --sync` (or `python3 -m <package>.core.skill_install --sync`).
   Every `<cli> <subcommand>` line in the skill must exist; `test_core.py`
   checks.
6. **Test** (`tests/test_<package>.py`): use the Flask test client with
   `monkeypatch.setattr(version, "UPDATE_CHECK", False)`. A loopback-only route
   needs a test with `environ_base={"REMOTE_ADDR": "10.11.12.13"}` that expects 403.
7. `./test.sh`, then `./run.sh` and try it in the browser.

For the About box, register rows with
`server.about_extras(lambda: {"Data folder": str(path)})` rather than editing
the dialog.

## Constraints that bite

- **Always use `./run.sh` and `./test.sh`, never a bare `pip` or `pytest`.**
  Ubuntu 24.04 is PEP 668-managed, so packages go in `.venv`. DLAB5 workstations
  source ROS 2, which puts `/opt/ros/.../site-packages` on `PYTHONPATH`. That
  shadows the venv and loads pytest plugins that can't import. Both scripts
  `unset PYTHONPATH`, and `test.sh` sets `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1`.
- **stdout is the MCP transport.** In `mcp_server.py`, anything it imports, and
  `launch_mcp.py`, a single `print()` to stdout breaks the handshake. Log with
  `web.log()` (stderr). Subprocesses get `stdout=DEVNULL` or `stdout=sys.stderr`.
- **mcp 2.x:** `from mcp.server.mcpserver import MCPServer`. `FastMCP` is gone,
  so pin `mcp>=2,<3`. metro-map-tool's pyproject still says `mcp>=1.2`, which is
  a bug.
- **The skill exists three times as real files:** packaged (`<package>/skill/`,
  which is the source), `.claude/skills/<tool>/`, and `plugin/skills/<tool>/`.
  Symlinks arrive on a Windows clone as a one-line text file. Edit the packaged
  copy, then `--sync`. `test_core.py` fails if the copies drift.
- **Lifecycle endpoints** (`/api/shutdown`, `/api/restart`, `/api/update`) are
  POST-only and loopback-only, so a link in another tab can't stop the server.
  Keep it that way. `--host 0.0.0.0` prints the one warning the tool gives.
- **Restart is `execv` after `os.closerange(3, 1024)`.** Werkzeug's listening
  socket survives exec otherwise, and the new process can't bind its own port.
- **Startup lines are flushed.** A launcher may redirect stdout to a log, where
  it is block-buffered.
- **Werkzeug's "development server" banner is suppressed on purpose.** This is
  a loopback single-user tool. Don't reintroduce `app.run()` outside `--debug`.
- **The update check reads raw `VERSION` on the default branch, not the GitHub
  API** (60 calls/hour unauthenticated). So `VERSION` on main *is* the release
  pointer: don't bump it on main without tagging.
- **pip can't update a checkout.** `/api/update` returns 400 and says `git pull`.
- **package-data** must list `VERSION`, `templates/*.html`, `static/*`,
  `skill/*.md`, the shared samples, and for `<package>.core`, `static/*` and
  `templates/core/*.html`. A missing entry passes every checkout test and breaks
  only a pip install. `test_core.py` checks the list, but verify with a real
  `pip install` into a fresh venv when you add a folder.
- **Console-script entry points aren't visible from a checkout.** Launchers and
  `.mcp.json` use `python -m <package>.<module>`, and each command has that twin.
- **The user folder follows the working directory; shared samples live in the
  package.** The MCP server starts the web server in *its own* working directory
  (the agent's project). Never resolve user data relative to `__file__`.
- **Saves carry `base_version`** (a content hash, not mtime). A 409 means
  someone else saved; offer *Load theirs / Keep mine*, and never overwrite
  silently.
- **Runtime data never goes in git.** Exports, flows and user documents may hold
  system ids or credentials. Git-ignore the folder and ship only a README or
  samples.
- **The plugin's MCP launcher** installs `git+<repo>@v<plugin/bin/VERSION>`
  into `~/.local/share/dlab5-tools/<tool>/<version>/`. So the plugin only works
  for versions that are **tagged and pushed**. Test before tagging with
  `DLAB5_TOOL_SOURCE=/path/to/checkout`.

## Versions and releases

`<package>/VERSION` is the only version. `pyproject.toml` reads it,
`/api/version` reports it, and `plugin/.claude-plugin/plugin.json` and
`plugin/bin/VERSION` must equal it (`test_core.py`). Release with
`python3 scripts/release.py X.Y.Z -F notes.txt --push`. It updates all of them
plus the README pins, syncs the skill copies, commits `Release X.Y.Z`, tags, and
creates the GitHub release. The `release` skill in this plugin walks through it.

## Taking core fixes

`copier update` (the `update-core` skill). It needs a clean tree. It rewrites
core-owned files and leaves tool-owned ones alone. Resolve any `.rej` or conflict
markers, run `./test.sh`, commit as "Take template vX.Y.Z".

## Useful commands

```bash
./run.sh [--port N] [--stop] [app options…]    # start/replace/stop the page
./test.sh [pytest args]                        # the suite, ROS-proof
<cli>-skill --check | --sync | --install       # skill copies
python3 scripts/release.py X.Y.Z --dry-run     # see a release before making it
claude plugin validate plugin                  # the tool's plugin manifest
~/.local/share/dlab5-tools/copier/bin/copier update --pretend   # preview core changes
```
