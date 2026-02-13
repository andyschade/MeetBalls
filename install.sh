#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBS_DIR="$SCRIPT_DIR/tests/libs"
BIN_TARGET="$SCRIPT_DIR/bin/meetballs"
LOCAL_BIN="$HOME/.local/bin"

# --- 1. Check bash version ---
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: bash >= 4.0 required (found ${BASH_VERSION})" >&2
    exit 1
fi

# --- 2. Install bats-core test dependencies ---
echo "Installing bats-core test framework..."
mkdir -p "$LIBS_DIR"

clone_if_missing() {
    local name="$1"
    local repo="$2"
    local dest="$LIBS_DIR/$name"

    if [[ -d "$dest" ]]; then
        echo "  $name: already installed, skipping"
    else
        echo "  $name: cloning..."
        git clone --depth 1 "$repo" "$dest" 2>&1 | sed 's/^/    /'
    fi
}

clone_if_missing "bats" "https://github.com/bats-core/bats-core.git"
clone_if_missing "bats-support" "https://github.com/bats-core/bats-support.git"
clone_if_missing "bats-assert" "https://github.com/bats-core/bats-assert.git"

# --- 3. Create symlink ---
echo ""
echo "Setting up meetballs command..."
mkdir -p "$LOCAL_BIN"

if [[ -L "$LOCAL_BIN/meetballs" ]]; then
    rm "$LOCAL_BIN/meetballs"
fi
ln -s "$BIN_TARGET" "$LOCAL_BIN/meetballs"
echo "  Symlink: $LOCAL_BIN/meetballs -> $BIN_TARGET"

# --- 4. Check PATH ---
case ":$PATH:" in
    *":$LOCAL_BIN:"*) ;;
    *)
        echo ""
        echo "Note: $LOCAL_BIN is not in your PATH."
        echo "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        ;;
esac

# --- 5. Run meetballs doctor ---
echo ""
echo "Running dependency check..."
"$BIN_TARGET" doctor || true

# --- 6. Summary ---
echo ""
echo "MeetBalls installed successfully!"
echo "Run 'meetballs --help' to get started."
