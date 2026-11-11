#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Monterey (macOS 12) fork build entry point. STATUS: preflight only, UNTESTED.
# Source port is not finished; the compile step is expected to fail until it is.
set -euo pipefail
cd "$(dirname "$0")"
fail() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "must run on macOS (found $(uname -s)); Swift/AppKit cannot be built elsewhere."
ARCH="$(uname -m)"; HOST_OS="$(sw_vers -productVersion)"
command -v swiftc >/dev/null || fail "swiftc not found; install Xcode or Command Line Tools."
command -v xcrun  >/dev/null || fail "xcrun not found."
SWIFT_VER="$(swiftc --version 2>&1 | head -1)"
SDK="$(xcrun --show-sdk-path)"; SDK_VER="$(xcrun --show-sdk-version)"
echo "macOS $HOST_OS | arch $ARCH | $SWIFT_VER | SDK $SDK_VER ($SDK)"
echo "Free disk (GB): $(df -g . | awk 'NR==2{print $4}')"

# The code uses Swift 5.7+ syntax (if let x {}) and needs SDK 13+ headers for
# SMAppService; Package.swift needs tools 5.9 (Xcode 15+). Xcode 15 runs on 13.5+,
# not on Monterey itself, so build on a newer Mac and deploy to 12.0.
MAJOR="${SWIFT_VER##*version }"; MAJOR="${MAJOR%%.*}"
(( MAJOR >= 5 )) || fail "Swift 5.9+ (Xcode 15+) required."

TARGET="${ARCH}-apple-macosx12.0"
OUT="build-monterey"; mkdir -p "$OUT"
LOG="$OUT/build.log"
echo "Target: $TARGET  Log: $LOG"
# Delegates to the Package.swift route with the lowered target; fix Package.swift
# platforms to .macOS(.v12) as part of the port before this can succeed.
swift build -c release -Xswiftc -target -Xswiftc "$TARGET" --build-path "$OUT/.build" 2>&1 | tee "$LOG"
echo "Output: $PWD/$OUT/.build/release  (bundle/zip/self-test steps not yet implemented)"
