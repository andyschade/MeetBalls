# Contributing to MeetBalls

Thanks for your interest in contributing! MeetBalls is a small, focused project and we'd love your help.

## Getting Started

```bash
git clone https://github.com/andyschade/MeetBalls.git
cd MeetBalls
./install.sh
```

## Running Tests

MeetBalls uses [bats-core](https://github.com/bats-core/bats-core) for testing. The test framework is installed automatically by `install.sh`.

```bash
# Run all tests
tests/libs/bats/bin/bats tests/

# Run a specific test file
tests/libs/bats/bin/bats tests/test_live.bats

# Run a specific test by name
tests/libs/bats/bin/bats tests/test_live.bats --filter "live --help"
```

All tests must pass before submitting a PR.

## Project Structure

```
bin/meetballs          CLI dispatcher — routes commands to lib/ modules
lib/common.sh          Shared utilities sourced by all modules
lib/<command>.sh       One file per command (live, record, transcribe, ask, list, update, doctor)
tests/test_<name>.bats One test file per module
install.sh             Installation and build script
```

**Conventions:**
- Every command module exports a `cmd_<name>()` function
- Every command supports `--help`
- Shared functions are prefixed with `mb_`
- All scripts use `set -euo pipefail`

## Writing Tests

Follow the existing patterns in `tests/`:

- Use `common_setup` / `common_teardown` from `test_helper.bash`
- Use `create_mock_command` to stub external tools
- Use `isolate_path` when you need strict command isolation
- Test both success and failure paths
- Mock external dependencies — tests should never touch real audio hardware, network, or user data

## Submitting Changes

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Add or update tests for any new behavior
4. Run the full test suite and confirm all tests pass
5. Open a pull request with a clear description of what changed and why

## Code Style

- Bash 4.0+ — no bashisms that require 5.x
- `set -euo pipefail` in all entry points
- Prefer clarity over cleverness
- Error messages should be actionable ("X not found. Install: `sudo apt install x`")
- No emojis in code output (the banner is the exception)

## Reporting Issues

Open an issue on GitHub. Include:
- What you ran
- What you expected
- What actually happened
- Output of `meetballs doctor`
