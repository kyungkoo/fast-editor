# Developing Fast Editor in Zed

This project is configured with worktree-local Zed tasks in `.zed/tasks.json`.
Open the repository root in Zed, install the Swift extension when prompted, then
use `task: spawn` to run the project tasks.

## Local Tasks

- `FastEditor: Build` builds the Rust `editor_core` dylib and then builds the
  Swift package.
- `FastEditor: Run` rebuilds the Rust core and launches the Swift executable
  with `swift run FastEditor`.
- `FastEditor: Rust Tests` runs `cargo test`.
- `FastEditor: Swift Build` runs only `swift build`.
- `FastEditor: Open current file in Xcode` opens the current Zed file in Xcode
  for cases where SwiftUI previews or Xcode-specific tools are still useful.

## Tooling Notes

The setup follows the workflow described in:

- <https://luxmentis.org/blog/ios-and-mac-apps-in-zed/>
- <https://zed.dev/docs/tasks>

Installed/expected local tools:

- Zed stable, preferably installed with `brew install --cask zed`.
- Rust installed via `rustup`.
- Xcode or Xcode Command Line Tools for SwiftPM.
- `xcode-build-server` for future Xcode project support.
- `xcbeautify` for future Xcode build log formatting.

This repository is currently a Swift Package, not an Xcode project, so it does
not require `xcede.yml` or `buildServer.json` yet. If the project later grows an
Xcode project or workspace, add `xcede` and an `xcede.yml` file, then consider
adding Zed tasks for `xcede build`, `xcede buildrun`, and `xcede test`.

## Suggested Zed Keybindings

Zed keybindings are global/user-level, so they are documented here rather than
committed as project configuration. Add something like this to your Zed
`keymap.json` if you want Xcode-like shortcuts:

```json
{
  "context": "Workspace",
  "bindings": {
    "cmd-b": [
      "action::Sequence",
      ["workspace::Save", ["task::Spawn", { "task_name": "FastEditor: Build" }]]
    ],
    "cmd-r": [
      "action::Sequence",
      ["workspace::Save", ["task::Spawn", { "task_name": "FastEditor: Run" }]]
    ]
  }
}
```
