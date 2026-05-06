#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: $0 <file>" >&2
  exit 64
fi

osascript <<END
tell application "Xcode"
    activate
    open POSIX file "$1"
end tell
END
