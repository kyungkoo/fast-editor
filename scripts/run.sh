#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export SDKROOT="${SDKROOT:-$(DEVELOPER_DIR="$DEVELOPER_DIR" xcrun --sdk macosx --show-sdk-path)}"

cargo build
DEVELOPER_DIR="$DEVELOPER_DIR" SDKROOT="$SDKROOT" xcrun swift run FastEditor
