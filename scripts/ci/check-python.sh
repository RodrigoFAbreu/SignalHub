#!/usr/bin/env bash
# Repository checks run by the shared Python workflow.
set -euo pipefail

ruff check .
ruff format --check .
python -m unittest discover --start-directory scripts/release --verbose
python -m unittest discover --start-directory scripts/device-review --verbose

# Installing the SDK checks its build and console entry point.
python -m pip install ./sdk/python
signalhub send --help
python -m unittest discover --start-directory sdk/python/tests --top-level-directory sdk/python --verbose
python scripts/release/sdk_files.py 0.0.0+ci "$RUNNER_TEMP/sdk"

# Exercise the oldest supported SDK interpreter as well as the default.
python3.10 -m pip install ./sdk/python
python3.10 -m unittest discover --start-directory sdk/python/tests --top-level-directory sdk/python
python -m unittest discover --start-directory scripts/ci --verbose
python -m unittest discover --start-directory container-tests --pattern 'test_helpers.py' --verbose
shellcheck examples/*/*.sh scripts/release/*.sh scripts/ci/*.sh
python -m unittest discover --start-directory examples/tests --verbose
