# Fast Editor

Fast Editor is a macOS-first, AI-native code editor prototype. The first
vertical slice proves a native SwiftUI/AppKit shell connected to a Rust editor
core.

## Requirements

- Xcode 26.3 or newer.
- Rust installed with the official rustup installer:

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Restart the shell or source Cargo's environment file before building:

```sh
. "$HOME/.cargo/env"
```

## Build

```sh
./scripts/build.sh
```

The build script compiles `editor_core` first so SwiftPM can link the local
`target/debug/libeditor_core.dylib`.

## Zed Development

This repository includes worktree-local Zed tasks in `.zed/tasks.json` for
building, running, and testing from Zed. See `docs/zed-development.md`.

## Current Vertical Slice

- Open a UTF-8 text file from the macOS shell.
- Store and edit file contents through the Rust `editor_core`.
- Save edits back to disk.

Metal rendering, Markdown preview, and AI agent integration are intentionally
left for follow-up slices.
