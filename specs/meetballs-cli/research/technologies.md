# Technologies — System Environment Research

## System Environment (verified 2026-02-12)

| Tool | Available | Version / Notes |
|------|-----------|-----------------|
| bash | YES | 5.2.21(1)-release (x86_64-pc-linux-gnu) |
| git | YES | 2.43.0 |
| readlink | YES | GNU coreutils 9.4 (supports `-f`) |
| mktemp | YES | GNU coreutils 9.4 |
| stat | YES | GNU coreutils 9.4 |
| date | YES | Verified: `date +%Y-%m-%dT%H-%M-%S` → `2026-02-12T22-43-45` |
| df | YES | Standard utility |
| claude | YES | 2.1.41 (Claude Code CLI) at `/home/andy/.nvm/versions/node/v24.12.0/bin/claude` |
| bats-core | YES | Installed to `tests/libs/bats/` via `install.sh` |
| pw-record | NO | Not installed |
| parecord | NO | Not installed |
| arecord | NO | Not installed (alsa-topology-conf and alsa-ucm-conf present but not alsa-utils) |
| whisper-cli | NO | Not installed, no model directories found |

**Platform**: Linux 6.6.87.2-microsoft-standard-WSL2
**Disk space**: ~960 GB free on /home

## Audio Backend Flags (verified from documentation)

### pw-record (PipeWire) — WAV 16kHz mono 16-bit
```bash
pw-record --rate=16000 --channels=1 --format=s16 "$output_file"
```
- Infers WAV format from `.wav` file extension
- Short flags also work: `-r 16000 -c 1 -f s16`

### parecord (PulseAudio) — WAV 16kHz mono 16-bit
```bash
parecord --rate=16000 --channels=1 --format=s16le --file-format=wav "$output_file"
```
- Requires explicit `--file-format=wav` flag

### arecord (ALSA) — WAV 16kHz mono 16-bit
```bash
arecord -f S16_LE -r 16000 -c 1 -t wav "$output_file"
```
- `-t wav` is the default if omitted, but explicit is safer

**Design doc flags for pw-record used `--format=s16` which is correct.**
The design critic concern about pw-record producing raw PCM instead of WAV is **resolved**: pw-record infers WAV from the `.wav` extension.

## Claude Code CLI Flags (verified from `claude --help`)

### Single-shot mode (ask with question)
```bash
claude -p "$question" --append-system-prompt "$system_prompt"
```
- `-p, --print` — Print response and exit (pipe-friendly)
- `--append-system-prompt <prompt>` — Append to default system prompt

### Interactive mode (ask without question)
```bash
claude --append-system-prompt "$system_prompt"
```
- Launches interactive session with transcript context

**Important constraint**: Claude CLI cannot be launched inside another Claude Code session (`CLAUDECODE=1` env var blocks it). This means:
1. Tests for `ask.sh` MUST mock `claude` — cannot test real invocations from within this session
2. The `meetballs ask` command should work fine for end users (they won't have `CLAUDECODE` set)

### Alternative: `--system-prompt` vs `--append-system-prompt`
- `--system-prompt` — Replaces the default system prompt entirely
- `--append-system-prompt` — Appends to the default (preserves Claude Code's built-in behavior)
- Design chose `--append-system-prompt` which is appropriate for interactive mode (keeps Claude Code tools available)
- For single-shot mode with `-p`, either works since there's no interactive context

## bats-core Testing Setup

### Installation (complete)
bats-core and helpers installed to `tests/libs/` via `install.sh`:
```bash
tests/libs/bats/          # bats-core
tests/libs/bats-support/  # assertion helpers
tests/libs/bats-assert/   # assertion library
```

### Running tests
```bash
./tests/libs/bats/bin/bats tests/
```

### Mocking external commands (established pattern)
From `tests/test_helper.bash:32-40`:
```bash
create_mock_command() {
    local name="$1"
    local body="${2:-exit 0}"
    cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$MOCK_BIN/$name"
}
```

### Key bats assertions (bats-assert)
- `assert_success` / `assert_failure`
- `assert_output "exact"` / `assert_output --partial "substring"` / `assert_output --regexp "pattern"`
- `assert_line 0 "first line"` / `assert_line -1 "last line"`
- `refute_output --partial "should not contain"`

## WAV Header Arithmetic

Design specifies: `duration_secs = (file_size - 44) / (16000 * 2)`
- 44 bytes = standard WAV header for PCM format
- 16000 = sample rate, 2 = bytes per sample (16-bit)
- Works for all three backends since they all produce standard WAV files
- In bash: `stat -c %s "$file"` to get file size, then arithmetic with `$(( ))`
- Note: bash arithmetic is integer-only; integer seconds is sufficient for display via `mb_format_duration`

Source: `specs/meetballs-cli/design.md:176-182`

## Whisper.cpp Model Path Detection

From design (`specs/meetballs-cli/design.md:207-211`):
- Check common locations: `~/.local/share/whisper.cpp/models/`, `/usr/local/share/whisper.cpp/models/`, `$WHISPER_CPP_MODEL_DIR`
- Look for `ggml-${WHISPER_MODEL}.bin`
- If not found, print download URL and instructions
