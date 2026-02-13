---
status: completed
created: 2026-02-12
started: 2026-02-12
completed: 2026-02-12
---
# Task: CLI Dispatcher + Global Help

## Description
Implement the `bin/meetballs` CLI dispatcher that routes commands to their respective modules, handles `--help` and `--version` flags, and prints errors for unknown commands. This makes all subsequent commands immediately runnable via the single entry point.

## Background
The dispatcher is the user's entry point. It resolves its own location (following symlinks), sources `lib/common.sh`, and uses a `case` statement to dispatch to the correct subcommand module. Each subcommand module exposes a `cmd_<name>` entry function.

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md (Section 3.1 — CLI Dispatcher)

**Additional References:**
- specs/meetballs-cli/context.md (codebase patterns)
- specs/meetballs-cli/plan.md (Step 2)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Resolve `LIB_DIR` relative to the script's real path using `readlink -f` (to handle symlinks from install)
2. Source `lib/common.sh`
3. Dispatch via `case` statement: `record`, `transcribe`, `ask`, `list`, `doctor`
4. Each case sources the appropriate `lib/*.sh` and calls `cmd_<name> "$@"`
5. `--help` or no arguments: print global help listing all commands with brief descriptions
6. `--version`: print version string (e.g., `meetballs 0.1.0`)
7. Unknown command: print error to stderr with suggestion to run `--help`, exit 1
8. Script starts with `#!/usr/bin/env bash` and `set -euo pipefail`

## Dependencies
- Task 00 (project scaffolding)
- Task 01 (common.sh must exist and be sourceable)

## Implementation Approach
1. **RED**: Write `tests/test_meetballs.bats` with tests for `--help`, `--version`, and unknown commands
2. **GREEN**: Implement the dispatcher in `bin/meetballs`
3. **REFACTOR**: Ensure help output is clear and well-formatted

### Test cases:
- `meetballs --help` prints usage with all 5 command names, exit 0
- `meetballs --version` prints version string, exit 0
- `meetballs` (no args) prints help, exit 0
- `meetballs bogus` prints error to stderr, exit 1

## Acceptance Criteria

1. **Global help lists all commands**
   - Given the user runs `meetballs --help`
   - When output is examined
   - Then it contains "record", "transcribe", "ask", "list", "doctor" and exits 0

2. **No arguments shows help**
   - Given the user runs `meetballs` with no arguments
   - When output is examined
   - Then it shows the same help text as `--help`

3. **Version flag works**
   - Given the user runs `meetballs --version`
   - When output is examined
   - Then it prints a version string and exits 0

4. **Unknown command errors**
   - Given the user runs `meetballs bogus`
   - When stderr is examined
   - Then it contains an error message and exits 1

5. **Symlink resolution works**
   - Given `bin/meetballs` is invoked via a symlink
   - When it resolves `LIB_DIR`
   - Then it correctly finds and sources `lib/common.sh`

6. **Tests pass**
   - Given the implementation is complete
   - When running `./tests/libs/bats/bin/bats tests/test_meetballs.bats`
   - Then all tests pass

## Metadata
- **Complexity**: Low
- **Labels**: CLI, dispatcher, UX
- **Required Skills**: Bash
