---
status: completed
created: 2026-02-12
started: 2026-02-13
completed: 2026-02-13
---
# Task: Install Script Finalize + Full Test Suite

## Description
Finalize `install.sh` to handle the complete setup experience: check bash version, install bats-core test dependencies (if not present), create a symlink in `~/.local/bin/`, ensure PATH includes `~/.local/bin`, and run `meetballs doctor` as a final check. Verify the entire test suite passes.

## Background
The install script is the user's first touch point — it should take them from a fresh clone to a working tool. It was initially created in Task 00 with just bats-core installation; now it needs the full user-facing setup flow. This task also serves as the final integration checkpoint — all tests across all modules must pass.

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md (Section 7 — install.sh)

**Additional References:**
- specs/meetballs-cli/context.md (install.sh does NOT install system deps)
- specs/meetballs-cli/plan.md (Step 8)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Check for bash >= 4.0 — die with message if too old
2. Install bats-core, bats-support, bats-assert to `tests/libs/` via `git clone --depth 1` (skip if already present)
3. Create symlink: `~/.local/bin/meetballs` → `$(pwd)/bin/meetballs`
   - Create `~/.local/bin/` if it doesn't exist
   - If symlink already exists, update it
4. Check if `~/.local/bin` is in `$PATH` — if not, print instructions for adding it
5. Run `meetballs doctor` to report dependency status (informational, don't fail install if deps missing)
6. Print summary of what was done and next steps for any missing system dependencies
7. Script must be idempotent — running it twice should work without errors

## Dependencies
- Task 00 (initial install.sh structure)
- Task 03 (doctor command must work for the final doctor check)
- All previous tasks (for full test suite verification)

## Implementation Approach
1. Read existing `install.sh` from Task 00
2. Enhance with full setup logic (bash version check, symlink, PATH check, doctor run)
3. Run the complete test suite: `./tests/libs/bats/bin/bats tests/`
4. Fix any integration issues discovered
5. Verify install.sh is idempotent

### Verification:
- `./install.sh` completes without errors
- `~/.local/bin/meetballs` symlink exists and points to correct location
- `meetballs --help` works from any directory (if ~/.local/bin is in PATH)
- `./tests/libs/bats/bin/bats tests/` — ALL tests pass across all test files

## Acceptance Criteria

1. **Bash version check**
   - Given bash < 4.0
   - When running `./install.sh`
   - Then it prints an error and exits 1

2. **Bats-core installed**
   - Given `tests/libs/` is empty
   - When running `./install.sh`
   - Then bats-core, bats-support, and bats-assert are cloned

3. **Symlink created**
   - Given `~/.local/bin/meetballs` doesn't exist
   - When running `./install.sh`
   - Then the symlink is created pointing to `$(pwd)/bin/meetballs`

4. **PATH check**
   - Given `~/.local/bin` is not in PATH
   - When running `./install.sh`
   - Then it prints instructions for adding it to PATH

5. **Idempotent**
   - Given `./install.sh` has been run before
   - When running `./install.sh` again
   - Then it completes without errors

6. **Doctor runs**
   - Given install completes
   - When the doctor check runs
   - Then dependency status is printed (pass or fail is informational)

7. **Full test suite passes**
   - Given all implementation is complete
   - When running `./tests/libs/bats/bin/bats tests/`
   - Then ALL tests across ALL test files pass

## Metadata
- **Complexity**: Medium
- **Labels**: install, integration, finalize
- **Required Skills**: Bash, symlinks, PATH management
