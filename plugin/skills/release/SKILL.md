---
name: release
description: Release a version of a D-LAB-5 Python tool built from the template with scripts/release.py. It bumps VERSION, the plugin manifest and the MCP launcher pin, rewrites the README install pins, syncs the skill copies, commits "Release X.Y.Z", tags, pushes and creates the GitHub release. Use when asked to "release", "cut a version", "publish X.Y.Z", "tag a release", or when GitHub releases lag behind tags.
argument-hint: "X.Y.Z"
---

# Release a tool

Version asked for: $ARGUMENTS

A release is outward-facing: it pushes a tag, publishes a GitHub release, and
changes what the About box offers every installed copy (it reads `VERSION` on
the default branch). **Confirm the version and the push with the user before
`--push`.**

## 1. Pick the number

```bash
cat <package>/VERSION; git tag --sort=-v:refname | head -3
git log --oneline v$(cat <package>/VERSION)..HEAD
```

Patch for fixes and docs, minor for new features or skill capabilities, major
for anything that breaks a command, an endpoint, a spec format or a stored file.
If tags are ahead of GitHub releases (`gh release list`), mention it. The script
creates releases from now on; past ones can be created with
`gh release create vX.Y.Z --generate-notes`.

## 2. Write the notes

Write `notes.txt` in the scratchpad, in ERP-LAB-5 commit style: prose
paragraphs on what changed for someone using the tool, then a `Verified:` block,
then the trailers the git-commit skill prescribes (Designed-by, Co-Authored-By).
The script uses the file as the commit body and, without the trailers, as the
release notes. So when pushing, pass a copy without the trailers to
`gh release edit --notes-file` afterwards if they matter.

## 3. Dry run, then release

```bash
python3 scripts/release.py X.Y.Z --dry-run            # lists every file it will touch
python3 scripts/release.py X.Y.Z -F notes.txt         # tests, edits, commit, tag: all local
git show --stat HEAD                                  # review, then with the user's go-ahead:
git push origin main vX.Y.Z && gh release create vX.Y.Z --title vX.Y.Z --notes-file notes.txt
```

Or, once the user has agreed, do it in one step: `python3 scripts/release.py X.Y.Z -F notes.txt --push`.
A local commit and tag that should not ship can still be undone before pushing:
`git tag -d vX.Y.Z && git reset --hard HEAD~1`.

The script refuses if:
- the tree is dirty;
- you're not on the default branch (`--allow-branch` overrides);
- the tag exists;
- the version isn't newer;
- `./test.sh` fails (`--skip-tests` is only for docs-only releases, and the notes say so).

It prints a `note:` for any README line that still names the old version.
Read those: a changelog line may be meant to keep the old number, but an
install command isn't.

## 4. After

- `curl -s https://raw.githubusercontent.com/<org>/<repo>/main/<package>/VERSION`
  shows the new number (the About box's source).
- With a plugin: the `erp-lab-5` marketplace picks up the new
  `plugin.json` version on `/plugin marketplace update erp-lab-5`, and the MCP
  launcher installs `@vX.Y.Z` on its next start.
- If the tool is also installed with pipx on this machine, remind the user:
  `pipx install --force git+…@vX.Y.Z`, then `<cli>-skill --install --force`.
