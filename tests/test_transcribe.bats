#!/usr/bin/env bats
# Tests for lib/transcribe.sh — transcribe command (task-06)

load test_helper

setup() {
    common_setup
    isolate_path
}

# Helper: create a fixture WAV file of known duration
create_fixture_wav() {
    local name="${1:-test-recording.wav}"
    local duration_secs="${2:-10}"
    local data_size=$(( duration_secs * 16000 * 2 ))
    local file_size=$(( 44 + data_size ))
    truncate -s "$file_size" "$MEETBALLS_DIR/recordings/$name"
    echo "$MEETBALLS_DIR/recordings/$name"
}

# Helper: create a mock whisper-cli that parses --output-file and creates .txt
create_mock_whisper() {
    local transcript_content="${1:-This is a test transcript.}"
    create_mock_command "whisper-cli" "
output_file=''
while [[ \$# -gt 0 ]]; do
    case \"\$1\" in
        --output-file) output_file=\"\$2\"; shift 2 ;;
        *) shift ;;
    esac
done
if [[ -n \"\$output_file\" ]]; then
    echo '$transcript_content' > \"\${output_file}.txt\"
fi
"
}

# Helper: create a mock whisper-cli that produces empty output
create_mock_whisper_empty() {
    create_mock_command "whisper-cli" "
output_file=''
while [[ \$# -gt 0 ]]; do
    case \"\$1\" in
        --output-file) output_file=\"\$2\"; shift 2 ;;
        *) shift ;;
    esac
done
if [[ -n \"\$output_file\" ]]; then
    touch \"\${output_file}.txt\"
fi
"
}

# --- Help ---

@test "transcribe --help prints usage and exits 0" {
    run "$BIN_DIR/meetballs" transcribe --help
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "transcribe"
}

# --- Missing argument ---

@test "transcribe errors on missing argument" {
    run "$BIN_DIR/meetballs" transcribe
    assert_failure
    assert_output --partial "recording"
}

# --- Nonexistent file ---

@test "transcribe errors on nonexistent file" {
    run "$BIN_DIR/meetballs" transcribe /fake/path/nonexistent.wav
    assert_failure
    assert_output --partial "not found"
}

# --- Missing whisper-cli ---

@test "transcribe errors when whisper-cli not available" {
    local wav_file
    wav_file=$(create_fixture_wav "test.wav" 10)

    run "$BIN_DIR/meetballs" transcribe "$wav_file"
    assert_failure
    assert_output --partial "whisper-cli"
}

# --- Successful transcription ---

@test "transcribe creates transcript file in transcripts directory" {
    local wav_file
    wav_file=$(create_fixture_wav "2026-02-12T14-30-00.wav" 10)
    create_mock_whisper "This is a meeting transcript."

    # Create a mock model file in isolated temp dir
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run "$BIN_DIR/meetballs" transcribe "$wav_file"
    assert_success

    [ -f "$MEETBALLS_DIR/transcripts/2026-02-12T14-30-00.txt" ]
}

# --- Transcript path printed ---

@test "transcribe prints transcript path on completion" {
    local wav_file
    wav_file=$(create_fixture_wav "2026-02-12T14-30-00.wav" 10)
    create_mock_whisper "Transcript content."

    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run "$BIN_DIR/meetballs" transcribe "$wav_file"
    assert_success
    assert_output --partial "2026-02-12T14-30-00.txt"
}

# --- Empty transcript handled gracefully ---

@test "transcribe handles empty whisper output gracefully" {
    local wav_file
    wav_file=$(create_fixture_wav "2026-02-12T14-30-00.wav" 10)
    create_mock_whisper_empty

    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run "$BIN_DIR/meetballs" transcribe "$wav_file"
    assert_success
}
