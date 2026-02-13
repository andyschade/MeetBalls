---
status: completed
created: 2026-02-12
started: 2026-02-12
completed: 2026-02-12
---
# Task: Project Scaffolding

## Description
Set up the project directory structure, initialize git, create the shell script skeletons, and install the bats-core test framework. This is the foundation that all subsequent tasks build on.

## Background
MeetBalls is a greenfield bash CLI project. The project directory exists with specs only — no code, no git repo, no test framework. This task creates the skeleton so that subsequent TDD tasks have a working test runner and directory layout.

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md

**Additional References:**
- specs/meetballs-cli/context.md (codebase patterns)
- specs/meetballs-cli/plan.md (overall strategy)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Run `git init` to initialize the repository
2. Create `bin/meetballs` as an executable bash script with a minimal placeholder (shebang + `set -euo pipefail`)
3. Create `lib/common.sh` as a sourceable bash script with a minimal placeholder
4. Create `tests/test_helper.bash` with shared test setup (MEETBALLS_DIR temp dir, LIB_DIR, mock helpers, teardown)
5. Create `install.sh` that clones bats-core, bats-support, and bats-assert into `tests/libs/` via `git clone --depth 1`
6. Create a `.gitignore` with `tests/libs/` (vendored test deps)
7. All scripts must have executable permissions where appropriate

## Dependencies
- None — this is the first task

## Implementation Approach
1. Create the directory structure: `bin/`, `lib/`, `tests/`
2. Write `install.sh` with bats-core installation logic
3. Write minimal `bin/meetballs` placeholder (shebang, set -euo pipefail, echo "meetballs: not yet implemented")
4. Write minimal `lib/common.sh` placeholder (shebang, set -euo pipefail)
5. Write `tests/test_helper.bash` with:
   - `MEETBALLS_DIR=$(mktemp -d)` isolation
   - `LIB_DIR` pointing to `lib/`
   - `MOCK_BIN=$(mktemp -d)` for command mocking
   - `create_mock_command` helper function
   - PATH manipulation to prepend `$MOCK_BIN`
   - `teardown` that cleans up temp dirs
   - Load bats-support and bats-assert
6. Run `git init` and `./install.sh`
7. Verify `tests/libs/bats/bin/bats` exists and is executable

## Acceptance Criteria

1. **Git repository initialized**
   - Given the project directory
   - When `git init` is run
   - Then `.git/` directory exists

2. **Directory structure exists**
   - Given a fresh clone
   - When listing the project
   - Then `bin/`, `lib/`, `tests/` directories exist

3. **install.sh installs bats-core**
   - Given bats-core is not yet installed
   - When running `./install.sh`
   - Then `tests/libs/bats/bin/bats`, `tests/libs/bats-support/`, and `tests/libs/bats-assert/` exist

4. **test_helper.bash provides isolation**
   - Given a test sources `test_helper.bash`
   - When `setup` runs
   - Then `$MEETBALLS_DIR` is a unique temp directory and `$MOCK_BIN` is on PATH

5. **bin/meetballs is executable**
   - Given the scaffolding is complete
   - When running `bin/meetballs`
   - Then it executes without permission errors

## Metadata
- **Complexity**: Low
- **Labels**: scaffolding, setup, testing
- **Required Skills**: Bash, Git
