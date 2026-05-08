import FastEditorModels
import SwiftUI

extension ContentView {
    @ViewBuilder
    var editorSurface: some View {
        VStack(spacing: 0) {
            if editor.hasOpenBuffer {
                editorTabs
                Divider()
                if showsFindBar {
                    findBar
                    Divider()
                }
            }

            editorBody
        }
    }

    @ViewBuilder
    var editorBody: some View {
        if showsMarkdownPreview {
            HStack(spacing: 0) {
                editorPane
                Divider()
                MarkdownPreview(html: editor.markdownPreviewHTML)
                    .frame(minWidth: 280)
            }
        } else {
            editorPane
        }
    }

    var editorTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(editor.openBuffers) { buffer in
                    bufferTab(buffer)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    func bufferTab(_ buffer: EditorOpenBuffer) -> some View {
        HStack(spacing: 6) {
            Button {
                editor.switchToBuffer(id: buffer.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: buffer.fileURL == nil ? "doc.badge.plus" : "doc.text")
                    Text(buffer.title)
                        .lineLimit(1)
                    if buffer.isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 8)
            }
            .buttonStyle(.plain)

            Button {
                closeBuffer(buffer)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(.trailing, 6)
        }
        .foregroundStyle(editor.renderSnapshot.bufferID == buffer.id ? Color.primary : Color.secondary)
        .background(editor.renderSnapshot.bufferID == buffer.id ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(buffer.subtitle)
    }

    var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in file", text: Binding(
                get: { editor.findQuery },
                set: { query in
                    editor.updateFindQuery(query)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
            .onSubmit {
                editor.selectNextFindMatch()
            }

            Text(editor.findStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Button {
                editor.selectPreviousFindMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(editor.findMatches.isEmpty)
            .help("Previous match")

            Button {
                editor.selectNextFindMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(editor.findMatches.isEmpty)
            .help("Next match")

            Button {
                showsFindBar = false
            } label: {
                Image(systemName: "xmark")
            }
            .help("Hide find")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    var editorPane: some View {
        MetalTextEditor(
            text: editor.textBinding,
            snapshot: editor.renderSnapshot,
            isEditable: editor.hasOpenBuffer,
            focusRevision: editor.focusRevision,
            scrollPosition: editor.currentScrollPosition,
            scrollPositionRevision: editor.scrollPositionRevision,
            diagnosticLineIndexes: editor.diagnosticLineIndexesForCurrentFile,
            onTextChange: editor.replaceText,
            onCursorMove: editor.setCursorUTF8Offset,
            onSelectionChange: editor.setSelectionUTF8Range,
            onScrollPositionChange: editor.setScrollPosition,
            onUndo: editor.undo,
            onRedo: editor.redo
        )
    }
}
