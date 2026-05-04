# Fast Editor Agent Guide

## Project Goal

Fast Editor is a macOS-first, AI-native code editor. It should feel fast like Zed
or Sublime Text while supporting modern development workflows through LSP,
syntax highlighting, AI agent integration, and build/task orchestration.

The editor should not ship its own AI model. Instead, it should integrate deeply
with external developer agents such as Codex, Claude Code, and Gemini.

## v0.1 Target

The first milestone is a vertical slice:

- Prove a native app and Rust editor core bootstrap first:
  - Scaffold the macOS app shell and Rust workspace.
  - Add an `editor_core` crate with file load, buffer, basic edit, and save APIs.
  - Add the thinnest practical Swift-Rust bridge smoke test.
  - Prove the loop: open a file, manage contents through Rust core, display it
    in the app, edit it, and save it back to disk.
- Launch a native macOS app.
- Open a file or folder.
- Manage file contents through the Rust editor core.
- Render and edit text in a Metal-backed editor view.
- Save edits back to disk.
- Show basic syntax highlighting.
- Support Markdown as a first-class editing format:
  - Highlight Markdown syntax.
  - Provide editing ergonomics for headings, lists, links, code fences, and
    block quotes.
  - Show a side-by-side or toggleable Markdown preview.
  - Update preview from the current buffer state, not only from saved files.
- Open an AI Agent Panel.
- Detect an available external AI CLI or agent.
- Send current file or selection context to the agent.
- Stream the agent response in the panel.
- Preview proposed diffs before applying them.

## Architecture

The initial architecture is:

- SwiftUI/AppKit native shell for macOS UX.
- Rust core for editor, language, AI, and task logic.
- Metal-backed editor view for GPU-accelerated text rendering.

SwiftUI/AppKit should own platform-native surfaces such as windows, menu bar,
toolbar, settings, file picker, native dialogs, sidebars, and panel chrome.

The editor surface should avoid SwiftUI text editing controls for the main code
buffer. Large text rendering, cursor, selection, syntax highlight layers,
minimap, and viewport scrolling should use a custom Metal-backed view.

## Shared Core Strategy

macOS is the v1 target, but the core should be prepared for future platforms.

Keep these areas platform-neutral where practical:

- Buffer and rope data structures.
- Selection, cursor, undo, and redo.
- Tree-sitter parsing and syntax token models.
- Markdown document model, syntax tokens, and preview state where practical.
- LSP state and protocol handling.
- AI provider adapters.
- Build/task provider abstractions.
- Settings schema, command model, keybinding model, and theme tokens.

Platform shells may differ later so each platform can provide native UX, but
they should consume the same Rust core and shared UI state model where possible.

## AI Integration Policy

AI integration should be provider-oriented. Codex, Claude Code, and Gemini
should be integrated through external CLI or agent adapters first.

The default safety model is approval-based:

- Agents may read explicitly provided workspace context.
- Agents may propose diffs.
- Agents may propose shell commands.
- Users must approve file changes before they are applied.
- Users must approve shell commands before they are executed.
- Agent output, proposed changes, and command requests should be auditable.

## Initial Rust Core Areas

Recommended crate boundaries:

- `editor_core`: buffer, rope, cursor, selection, undo/redo, file snapshots,
  viewport model.
- `language_core`: tree-sitter syntax parsing, LSP lifecycle, diagnostics,
  completion, hover, and go-to-definition.
- `agent_core`: external agent provider detection, process lifecycle,
  streaming events, diff proposals, and command approval flow.
- `task_core`: project detection, task discovery, task execution, and
  diagnostics parsing for build systems.

## IDE and Build Direction

Android, Swift Package, and Web development support should be built on a common
task provider abstraction.

Android support should start from `android-cli` concepts:

- SDK/environment inspection.
- Project description.
- Build/run task discovery.
- Device and emulator integration later.

Swift Package support should build around `swift build` and `swift test`.
Web support should discover package manager scripts for npm, pnpm, bun, and
yarn projects.

## Explicit Non-Goals for v0.1

Do not include these in the first vertical slice unless the scope changes:

- Full IDE build system.
- Extension/plugin marketplace.
- Embedded terminal emulator.
- Advanced LSP completion UI.
- Debugger integration.
- Multi-platform shell implementation.
- Complex project indexing.
- Full theme and keymap customization.

## Engineering Principles

- Keep the editor core independent from macOS UI details.
- Prefer explicit, typed core APIs over leaking platform UI state into Rust.
- Keep the Swift-Rust bridge simple first, then optimize after measurement.
- Use incremental rendering and parsing for editor responsiveness.
- Treat AI actions as reviewable proposals by default.
- Favor vertical slices that prove the full product loop before broad feature
  expansion.
