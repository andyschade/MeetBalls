# Broken Windows

## Touched Files Only

### [FIXED] [lib/doctor.sh:48-61] Duplicated whisper model search
**Type**: duplication
**Risk**: Low
**Fix**: Will be addressed by design (R8) — extract to `mb_find_whisper_model()` in common.sh
**Code**:
```bash
local model_file="ggml-${WHISPER_MODEL}.bin"
local model_found=false
local search_dirs=(
    "${WHISPER_CPP_MODEL_DIR:-}"
    "$HOME/.local/share/whisper.cpp/models"
    "/usr/local/share/whisper.cpp/models"
)
```
Note: This is the primary motivation for R8, not an incidental find.

### [FIXED] [lib/doctor.sh:65-66] model MISSING message is very long
**Type**: formatting
**Risk**: Low
**Fix**: Could wrap to multiple lines or use a shorter message with a separate "how to fix" line. However, since the design changes doctor.sh, this can be cleaned up during the refactor.
**Code**:
```bash
mb_info "  model:       MISSING — run: mkdir -p ~/.local/share/whisper.cpp/models && curl -L -o ..."
```

### [lib/transcribe.sh:38-51] Duplicated whisper model search
**Type**: duplication
**Risk**: Low
**Fix**: Will be addressed by design (R8) — replace with `mb_find_whisper_model()` call
**Code**:
```bash
local model_file="ggml-${WHISPER_MODEL}.bin"
local model_path=""
local search_dirs=( ... )
```
Note: Same as doctor.sh — both are targets for the shared helper extraction.

No other broken windows found in touched files. The codebase is clean and consistent.
