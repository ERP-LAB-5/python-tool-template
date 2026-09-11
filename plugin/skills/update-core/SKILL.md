---
name: update-core
description: Bring template fixes into an existing D-LAB-5 Python tool with `copier update`, or adopt the template in a tool that was written by hand before it existed (as sap-di-tools was). Covers previewing the change, the clean-tree requirement, resolving conflicts and .rej files, keeping tool-owned files untouched, and moving a hand-rolled About/shutdown/skill installer onto core/. Use when asked to "update the core", "take the template changes", "sync with python-tool-template", "copier update", "adopt the template", or "move <tool> onto the template".
argument-hint: "[tool directory]"
---

# Update a tool's core, or adopt the template

Target: $ARGUMENTS (default: the current repository)

```bash
COPIER=~/.local/share/dlab5-tools/copier/bin/copier   # see the new-tool skill if missing
```

## A. The tool already has `.copier-answers.yml`: update

1. **Clean tree.** Copier refuses otherwise, and a clean tree is what makes the
   result reviewable: `git status --porcelain` must be empty.
2. **See what is coming:**
   ```bash
   "$COPIER" update --trust --defaults --pretend
   git -C <template checkout> log --oneline <_commit from answers>..<new tag>   # if you have one
   ```
3. **Apply:** `"$COPIER" update --trust --defaults`. To answer a *new* question
   the template added, pass `--data name=value`. To change an old answer, e.g. to
   enable MCP later, pass `--data with_mcp=true`. The new files arrive; the
   tool-owned ones, like `mcp_server.py`, are only created if they don't exist.
4. **Conflicts.** Copier writes inline conflict markers, or `*.rej` files for
   hunks it couldn't place. Search for both:
   ```bash
   git diff --name-only; find . -name "*.rej" -not -path "./.venv/*"
   grep -rn "^<<<<<<< " --include="*.py" --include="*.js" --include="*.css" --include="*.html" --include="*.sh" .
   ```
   A conflict in a **core-owned** file means someone edited it locally. Take the
   template side, and if the local edit mattered, move it into the tool-owned
   layer (a route in `app.py`, a rule in `static/style.css`, an
   `about_extras` provider) or propose it to the template. Delete `.rej` files
   once handled.
5. **Verify:** `./test.sh`. `test_core.py` is new code from the template and may
   check things the tool never did (package-data, skill copies, version sync).
   Fix the tool-owned side. Then `./run.sh` and open the page: header, About,
   Restart, Stop.
6. **Commit:** "Take template vX.Y.Z", with a body that lists what changed for
   this tool and how it was verified.

## B. The tool was written by hand: adopt

This is what was done for sap-di-tools. Work on a branch.

1. **Map the tool onto the answers.** Read `pyproject.toml`, `run.sh`, `app.py`:
   package name, CLI command (`[project.scripts]`), CLI module (the one with
   `main()` and subcommands), port (`run.sh`), repository name, and whether it
   has MCP, a user folder, or Windows launchers. Keep command names as they are.
   Renaming a published command breaks installs.
2. **Try it on a scratch clone first**, then render over the real checkout.
   Put the answers in a YAML file, so the same answers go to both runs:
   ```bash
   git switch -c adopt-template
   "$COPIER" copy --trust --defaults --overwrite --data-file answers.yml \
     gh:ERP-LAB-5/python-tool-template . < /dev/null
   ```
   How the flags interact, as verified on sap-di-tools:
   - Tool-owned files that already exist (`_skip_if_exists`) are **skipped**.
   - Core-owned files that already exist (`run.sh`, `test.sh`, `LICENSE`) are
     **overwritten** by `--overwrite`. Without that flag Copier stops at the
     first conflict and asks, which fails with no terminal.
   - Tool-owned files the tool *didn't* have are **created from the sample**.

   Afterwards, review `git status` and `git diff`:
   - **Delete sample files that don't apply:** `tests/test_<package>.py` (the
     notes tests), and an empty `.claude/settings.json`.
   - **Replace the plugin's skill copy.** `plugin/skills/<tool>/SKILL.md` was
     generated from the *sample* skill, so run `<cli>-skill --sync` to replace
     it with the tool's real one.
   - **Carry over anything tool-specific** that `run.sh` or `test.sh` handled
     by hand, e.g. a `--dir` option, which becomes an app argument that
     `run.sh` now passes through.
3. **Move the hand-rolled core pieces onto `core/`:**
   - `app = Flask(__name__)` → `app = server.create_app(__name__)`. Delete the
     local `only_local`, `/api/shutdown`, `/api/about`, error handlers and
     `make_server` main. Use `server.add_server_args(ap)` +
     `server.serve(app, args, lines=[…])`. Tool-specific About rows go through
     `server.about_extras(...)`.
   - `templates/index.html` → `{% extends "core/_base.html" %}`, with the tool's
     header buttons in `{% block toolbar %}`. Delete its About `<dialog>`, Stop
     button and theme `<select>`; the base has them.
   - `static/app.js`: delete the About, Stop and theme handlers, and call
     `core.*` where the tool needs to. Keep the tool's own `api()` only if its
     signature differs.
   - `static/style.css`: keep the tool's own tokens and rules. Delete header,
     button, dialog and theme rules that duplicate `core.css`.
   - `skill_install.py` → delete it, and point the `<cli>-skill` console script at
     `<package>.core.skill_install:main`. Drop skill-copy and frontmatter tests
     that `test_core.py` now covers. Keep domain assertions.
   - `__init__.py`: `__version__` comes from `.core.version`.
   - `pyproject.toml`: add `"<package>.core"` to packages and its package-data
     (`static/*`, `templates/core/*.html`).
4. **Add** `plugin/` (the render created it), run `<cli>-skill --sync`, and set
   `plugin.json` / `plugin/bin/VERSION` to the current `VERSION`.
5. **Verify** as in A.5, plus the tool's own flows in the browser. Then commit
   and open a PR, and release with `scripts/release.py` once merged.
6. Replace `_src_path` in `.copier-answers.yml` with
   `gh:ERP-LAB-5/python-tool-template` if you rendered from a local path, so
   future updates come from the published template.
