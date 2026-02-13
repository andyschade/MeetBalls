# Existing Patterns — MeetBalls Codebase Research

## Project State (updated 2026-02-12)

**Partially implemented** — scaffolding, common utilities, and CLI dispatcher are complete. Five command modules remain.

```
MeetBalls/
├── .gitignore                        # Contains: tests/libs/
├── bin/
│   └── meetballs                     # CLI dispatcher (70 lines, complete)
├── lib/
│   └── common.sh                    # Shared utilities (114 lines, complete)
├── tests/
│   ├── test_helper.bash             # Shared test setup (41 lines)
│   ├── test_scaffolding.bats        # 7 tests — all passing
│   ├── test_common.bats             # 29 tests — all passing
│   ├── test_meetballs.bats          # 8 tests — all passing
│   └── libs/                        # bats-core, bats-support, bats-assert (gitignored)
├── install.sh                       # Installs bats-core test framework (29 lines)
├── PROMPT.md                        # Original specification
├── ralph.yml                        # Orchestrator config
└── specs/meetballs-cli/             # Design docs, tasks, research
```

**Test status:** 44/44 tests passing (7 scaffolding + 29 common + 8 dispatcher)

## Established Coding Conventions (from implemented code)

### Script Headers
All scripts start with:
```bash
#!/usr/bin/env bash
set -euo pipefail
```
Source: `bin/meetballs:1-2`, `lib/common.sh:1-2`

### Function Naming
- `mb_` prefix for all common.sh utility functions
- `cmd_<command>` for module entry functions (e.g., `cmd_record`, `cmd_doctor`)
- `show_help()` for local help functions within modules

Source: `lib/common.sh:25-113`, `bin/meetballs:13-30`

### Constants
- UPPER_SNAKE_CASE for constants
- Defined at top of `lib/common.sh`
- Environment variable overrides: `MEETBALLS_DIR="${MEETBALLS_DIR:-$HOME/.meetballs}"`

Source: `lib/common.sh:5-9`

### Terminal Colors
- Colors set at source time, disabled when stdout is not a terminal (`[[ -t 1 ]]`)
- Private variables: `_CLR_GREEN`, `_CLR_YELLOW`, `_CLR_RED`, `_CLR_RESET`

Source: `lib/common.sh:12-22`

### Output Conventions
- `mb_info` → stdout, no color
- `mb_success` → stdout, green
- `mb_warn` → stderr, yellow
- `mb_error` → stderr, red
- `mb_die` → stderr (red) + exit 1

Source: `lib/common.sh:30-49`

### CLI Dispatcher Pattern
- `case` statement in `bin/meetballs`
- `"${1:-}"` for safe argument access
- Lazy `source` of module files (only sourced when command matches)
- `shift` before passing `"$@"` to command function

Source: `bin/meetballs:32-69`

### Path Resolution
- `readlink -f` to resolve symlinks
- `LIB_DIR` computed relative to script's real path

Source: `bin/meetballs:7-8`

## Testing Patterns

### Test File Naming
- `tests/test_<module>.bats` — one file per module

### Test Setup/Teardown
- `setup()`: creates temp `MEETBALLS_DIR` and `MOCK_BIN`, prepends `MOCK_BIN` to PATH
- `teardown()`: removes temp directories
- Tests that need `common.sh` source it in their own `setup()`

Source: `tests/test_helper.bash:14-28`, `tests/test_common.bats:6-18`

### Mock Pattern
- `create_mock_command "name" "body"` creates executable script in `$MOCK_BIN`
- PATH manipulation ensures mocks are found before real commands
- Default mock body is `exit 0`

Source: `tests/test_helper.bash:32-40`

### Test Style
- `@test "description" { ... }` with descriptive names
- `run` to capture output, then `assert_success`, `assert_output --partial`, etc.
- Section headers as comments: `# --- Section ---`
- Both positive and negative test cases

Source: `tests/test_common.bats`, `tests/test_meetballs.bats`

### Test Helper Loading
- `load test_helper` at top of each test file
- Helper provides `TEST_DIR`, `PROJECT_ROOT`, `LIB_DIR`, `BIN_DIR`
- Loads bats-support and bats-assert

Source: `tests/test_helper.bash:5-11`

### Note on test_common.bats setup
- `test_common.bats` defines its own `setup()` and `teardown()` rather than relying on `test_helper.bash`'s `setup()` because it needs to `source "$LIB_DIR/common.sh"` inside setup
- Other test files (test_meetballs.bats, test_scaffolding.bats) rely on test_helper's setup/teardown

Source: `tests/test_common.bats:6-18`
