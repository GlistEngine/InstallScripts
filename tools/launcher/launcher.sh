#!/bin/bash
# GlistEngine dispatcher.
#
# The companion C binary (`launcher`) resolves its own path through symlinks
# and passes the bundle's eclipse/ directory as $GLIST_ECLIPSE_DIR before
# exec'ing this script. Layout assumption:
#   $GLIST_ECLIPSE_DIR/eclipsecpp-arm64/Eclipse.app/Contents/MacOS/eclipse
#   $GLIST_ECLIPSE_DIR/eclipsecpp-x86_64/Eclipse.app/Contents/MacOS/eclipse
#   $GLIST_ECLIPSE_DIR/workspace/

set -u

die() {
    osascript -e "display dialog \"$1\" buttons {\"OK\"} default button \"OK\" with icon stop" >/dev/null
    exit 1
}

if [[ -z "${GLIST_ECLIPSE_DIR:-}" ]]; then
    # Fallback for running this script directly (without the C launcher).
    HERE="$(cd "$(dirname "$0")" && pwd -P)" || die "Could not resolve launcher directory."
    GLIST_ECLIPSE_DIR="$(cd "$HERE/../../.." && pwd -P)" || die "Could not resolve Eclipse directory from $HERE."
fi

ECLIPSE_DIR="$GLIST_ECLIPSE_DIR"
WORKSPACE="$ECLIPSE_DIR/workspace"

ARCH="$(uname -m)"
case "$ARCH" in
    arm64)
        ECLIPSE_BIN="$ECLIPSE_DIR/eclipsecpp-arm64/Eclipse.app/Contents/MacOS/eclipse"
        BREW_BIN="/opt/homebrew/bin"
        COMPILER_DIR="/usr/bin"
        ;;
    x86_64)
        ECLIPSE_BIN="$ECLIPSE_DIR/eclipsecpp-x86_64/Eclipse.app/Contents/MacOS/eclipse"
        BREW_BIN="/usr/local/bin"
        COMPILER_DIR="/usr/bin"
        ;;
    *)
        die "Unsupported architecture: $ARCH"
        ;;
esac

if [[ ! -x "$ECLIPSE_BIN" ]]; then
    die "Eclipse binary not found for $ARCH at: $ECLIPSE_BIN"
fi

# Apps launched from Finder inherit launchd's minimal PATH (no Homebrew, no
# CommandLineTools shims). Prepend the arch-correct brew bin + standard system
# dirs so the wizard's `git`, CMake, compilers, etc. resolve. Everything Eclipse
# spawns (ProcessBuilder, external tools, terminal view) inherits this PATH.
export PATH="$BREW_BIN:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"
export CC="$COMPILER_DIR/clang"
export CXX="$COMPILER_DIR/clang++"

mkdir -p "$WORKSPACE"
exec "$ECLIPSE_BIN" -data "$WORKSPACE" "$@"
