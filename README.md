# python-tool-template

**The D-LAB-5 small full-stack Python tool, as a template, plus the agent kit to
build with it.**

> New to this? Start with **[the tool template, for the curious](docs/for-the-curious.md)**:
> the problems it solves and the ideas behind it, without the jargon.

[metro-map-tool](https://github.com/ERP-LAB-5/metro-map-tool) and
[sap-di-tools](https://github.com/ERP-LAB-5/sap-di-tools) were built the same
way. This repository is that way, taken out of both so the next tool starts
from it and the existing ones stay in step with it:

- a **stdlib engine with a command line**;
- a **Flask page on loopback** with a shared header (theme, About with version
  check and self-update, Restart, Stop);
- an optional **MCP server** that drives the same web server a person has open;
- an **agent skill** that ships in the package, in `.claude/skills`, and as a
  **Claude Code plugin**;
- `run.sh` / `run.cmd` / `run.ps1` launchers, a ROS-proof `test.sh`, and a
  **release script** that keeps VERSION, the README pins, the plugin and the
  GitHub releases in step.

It is a [Copier](https://copier.readthedocs.io) template. `copier copy` makes a
tool. Later, `copier update` inside that tool merges this template's fixes as
a reviewable diff.

## Start a tool

With the agent kit (below), ask for one or run `/pytool-kit:new-tool`. By hand:

```bash
pipx install copier            # or: python3 -m venv ~/.local/share/dlab5-tools/copier && …/bin/pip install copier
copier copy gh:ERP-LAB-5/python-tool-template ~/ERP-LAB-5/my-tool
cd ~/ERP-LAB-5/my-tool
git init -b main && git add -A && git commit -m "Start my-tool from the D-LAB-5 tool template"
./test.sh && ./run.sh
```

The questions: the tool's name, title, description, repository, port, CLI
command and engine module, an optional disclaimer, and five options:

| option | what it adds |
|---|---|
| `with_mcp` | `mcp_server.py` on `core/mcp_bridge.py` (autostarts the web server), `.mcp.json` |
| `with_windows` | `run.cmd` and `run.ps1`, same behaviour as `run.sh` |
| `with_workspace` | `core/workspace.py`: a git-ignored user folder that follows the working directory, samples in the package, atomic saves with version-conflict detection |
| `with_release` | `scripts/release.py X.Y.Z [--push]` |
| `with_plugin` | `plugin/`, so the tool installs into Claude Code: the skill, plus the MCP server when `with_mcp` |

What you get is a working "notes" sample through every layer (engine, routes,
page, MCP tools, skill, tests). Replace it slice by slice.

## Core and tool files

The split is what keeps updates quiet:

- **Core-owned:** `<package>/core/**`, the launchers, `test.sh`,
  `tests/test_core.py`, `scripts/release.py`, `plugin/bin/launch_mcp.py`. They
  are rendered from the answers alone, and `copier update` rewrites them. Every
  module in `core/` reads the tool's names from the generated
  `core/identity.py`, so they are otherwise identical in every tool.
- **Tool-owned:** listed under `_skip_if_exists` in [copier.yml](copier.yml).
  Generated once, never touched by an update.

To change the core, change it here, run `./test.sh`, tag a release, then run
`copier update` in each tool.

## The agent kit: plugins

`pytool-kit` is listed in the **`erp-lab-5` marketplace**, which lives in
[ERP-LAB-5/darkfactory](https://github.com/ERP-LAB-5/darkfactory):

```
/plugin marketplace add ERP-LAB-5/darkfactory
/plugin install pytool-kit@erp-lab-5             # for building tools
/plugin install di-replication-sync@erp-lab-5    # a tool, as a plugin
```

**`pytool-kit`** ([plugin/](plugin/)) gives an agent:

| skill | |
|---|---|
| `python-tool-template` | model-invoked knowledge: which files are core-owned, how to add a feature through every layer, and the constraints that bite (ROS `PYTHONPATH`, stdout as the MCP transport, symlinked skills on Windows, loopback-only lifecycle, `execv` and inherited sockets, package-data) |
| `/pytool-kit:new-tool` | settle the answers, check the port is free, generate, and prove it works |
| `/pytool-kit:update-core` | `copier update` with conflict handling; adopting the template in a hand-written tool |
| `/pytool-kit:release` | `scripts/release.py`: dry run, notes, tag, push, GitHub release |

**Each tool's plugin** is its repository's `plugin/` directory, listed in
darkfactory's [catalogue](https://github.com/ERP-LAB-5/darkfactory/blob/main/.claude-plugin/marketplace.json)
as a `git-subdir` source. Its MCP entry runs `plugin/bin/launch_mcp.py`. On first use
that script creates a venv for the pinned version under
`~/.local/share/dlab5-tools/<tool>/<version>/` and installs
`git+<repo>@v<version>` into it. Later starts go straight to the server.
It needs `python3` on PATH. A new tool joins the marketplace with one entry here
once its first release is tagged.

## Testing the template

```bash
./test.sh           # both option sets, end to end, plus a copier update round trip
./test.sh --quick   # render + each tool's own tests
KEEP=1 ./test.sh    # keep the rendered tools to look at
```

For every set in `tests/answers-*.yml`:
1. render it;
2. run its own suite;
3. `pip install` it into a fresh venv and check the data files shipped;
4. start it with `run.sh`, hit the endpoints, restart, stop;
5. with MCP, drive it through the plugin launcher from an agent working
   directory;
6. `claude plugin validate` the result.

CI runs the same on Linux, and the Windows launchers on Windows.

## Licence

GPL-3.0-or-later. © 2026 D-LAB-5 — *Twin. Experiment. Automate.*
Generated tools carry the same licence file.
