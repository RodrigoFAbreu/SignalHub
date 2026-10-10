# Container tests

Python tests (standard library and `unittest` only, linted with `ruff`) of what
needs a running SignalHub stack: the Compose stack and its proxy, the
operations that restart, back up and restore it, an upgrade from an earlier
release, a fresh install from the deployment files, and the end-to-end path of
an event through a fake FCM. One test per check, named for what it checks.

CI's container jobs start the stack and run them
([docs/development.md](../docs/development.md#continuous-integration)); the
same tests run by hand against a local `docker compose up`. How, and which
module needs which stack, is under *Container tests* there.

- `signalhub_stack.py`: the shared helper (requests without redirects or
  path normalization, credentials, `docker compose`, polling) and its settings.
- `test_helpers.py`: tests of the helper itself, needing no stack.
- `test_compose_*.py`, `test_operations_*.py`, `test_e2e.py`, `test_install.py`,
  `test_upgrade.py`: the stack's tests, grouped by the stack they need. Select
  them with `--pattern`; the default pattern would run them all against one stack.

A new check is a new test in the module of its stack. Create what it needs
(producers, devices, users) with the helper's `create_*` functions, which give
names no earlier run used, so a test does not depend on the order of the others.
