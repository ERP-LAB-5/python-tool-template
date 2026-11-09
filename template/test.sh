#!/usr/bin/env bash
# Run the test suite, with a workstation's ROS 2 environment kept out of it.
# ROS puts /opt/ros on PYTHONPATH and registers pytest plugins there that fail
# to import without ROS's own dependencies; neither belongs in this project.
#
#   ./test.sh                     everything under tests/
#   ./test.sh tests/test_core.py -k skill
#
# Core-owned (D-LAB-5 tool template): `copier update` rewrites this file.
set -euo pipefail
cd "$(dirname "$0")"
unset PYTHONPATH
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1

# A venv keeps its interpreter in bin/ on Linux and macOS, and in Scripts/ on
# Windows, where Git Bash runs this script too. Windows has no python3.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) VPY=.venv/Scripts/python.exe; BOOT=python ;;
  *)                    VPY=.venv/bin/python;         BOOT=python3 ;;
esac
if [ ! -x "$VPY" ]; then
  echo "  creating .venv ..."
  "$BOOT" -m venv .venv
  "$VPY" -m pip install --quiet --upgrade pip
fi
# `python -m pip`, not `.venv/bin/pip`: that wrapper is a generated script with
# an absolute shebang, so a venv copied in from another directory has one that
# points nowhere. The module always belongs to the interpreter running it.
cat requirements.txt requirements-dev.txt > .venv/.test-requirements.new
if ! cmp -s .venv/.test-requirements.new .venv/.test-requirements.txt; then
  echo "  installing requirements ..."
  "$VPY" -m pip install --quiet -r requirements.txt -r requirements-dev.txt
  mv .venv/.test-requirements.new .venv/.test-requirements.txt
  # run.sh keeps its own stamp; the runtime set is now installed too
  cp requirements.txt .venv/.requirements.txt
else
  rm -f .venv/.test-requirements.new
fi
exec "$VPY" -m pytest "${@:-tests/}"
