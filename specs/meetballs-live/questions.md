# Questions & Answers

## Q1: whisper-stream `--save-audio` output location

The spec says `whisper-stream --save-audio` should capture audio for post-session archiving to `~/.meetballs/recordings/`. However, `whisper-stream` saves its audio file to a hardcoded location relative to where it runs (typically `output.wav` in the CWD).

**Question:** Should the `transcriber.sh` helper simply set its CWD to the session directory (so `--save-audio` writes there) and then copy the resulting WAV to `~/.meetballs/recordings/` during cleanup? Or should we skip `--save-audio` entirely and rely on a separate background `parecord`/`pw-record` process to capture audio in parallel — giving us explicit control over format (16kHz mono 16-bit WAV) matching the existing `meetballs record` output?

The trade-off: `--save-audio` is simpler (one process) but we don't control the output format and the file name is opaque. A parallel recorder is more complex but produces output identical to `meetballs record`.

### A1: Use `--save-audio` — formats already match

**Research findings:** After reviewing the whisper-stream source code (`examples/stream/stream.cpp`), `--save-audio` produces:
- **16kHz sample rate, mono, 16-bit PCM WAV** — written via `wavWriter.open(filename, WHISPER_SAMPLE_RATE, 16, 1)`
- File is saved to the **current working directory** with a timestamp filename like `20260213143022.wav`

This is **identical** to the format `meetballs record` produces (16kHz mono 16-bit WAV via parecord/pw-record/arecord). The original concern about format inconsistency is unfounded.

**Recommendation: Use `--save-audio`** (Option 1)
- Formats are already consistent — both produce 16kHz mono 16-bit WAV
- Set `transcriber.sh`'s CWD to the session directory so the WAV lands in a known location
- During cleanup, find the `*.wav` file in the session dir and copy it to `~/.meetballs/recordings/` with the standard timestamp naming convention
- This avoids the complexity of managing a parallel recording process alongside whisper-stream
- The only minor difference is the filename format (`YYYYMMDDhhmmss.wav` vs `YYYY-MM-DDTHH-MM-SS.wav`) — cleanup handles the rename
