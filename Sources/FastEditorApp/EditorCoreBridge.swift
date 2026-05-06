import Foundation
import SwiftUI

private struct FeString {
    let ptr: UnsafeMutablePointer<UInt8>?
    let len: Int
}

@_silgen_name("fe_open_file")
private func feOpenFile(_ path: UnsafePointer<CChar>) -> UInt64

@_silgen_name("fe_new_file")
private func feNewFile() -> UInt64

@_silgen_name("fe_get_text")
private func feGetText(_ bufferID: UInt64) -> FeString

@_silgen_name("fe_get_render_snapshot")
private func feGetRenderSnapshot(_ bufferID: UInt64) -> FeString

@_silgen_name("fe_get_path")
private func feGetPath(_ bufferID: UInt64) -> FeString

@_silgen_name("fe_replace_text")
private func feReplaceText(_ bufferID: UInt64, _ text: UnsafePointer<UInt8>?, _ len: Int) -> Int32

@_silgen_name("fe_replace_text_with_cursor")
private func feReplaceTextWithCursor(
    _ bufferID: UInt64,
    _ text: UnsafePointer<UInt8>?,
    _ len: Int,
    _ cursorOffset: Int
) -> Int32

@_silgen_name("fe_set_cursor_offset")
private func feSetCursorOffset(_ bufferID: UInt64, _ cursorOffset: Int) -> Int32

@_silgen_name("fe_undo")
private func feUndo(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_redo")
private func feRedo(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_save_file")
private func feSaveFile(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_save_file_as")
private func feSaveFileAs(_ bufferID: UInt64, _ path: UnsafePointer<CChar>) -> Int32

@_silgen_name("fe_is_dirty")
private func feIsDirty(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_last_error")
private func feLastError() -> FeString

@_silgen_name("fe_free_string")
private func feFreeString(_ value: FeString)

@MainActor
final class EditorCoreBridge: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var statusText = "Open a file to start editing through the Rust core."
    @Published private(set) var isDirty = false
    @Published private(set) var focusRevision = 0
    @Published private(set) var renderSnapshot = EditorRenderSnapshot.empty
    @Published var text = ""
    @Published var errorMessage = ""

    private var bufferID: UInt64 = 0
    private var isSyncingFromCore = false

    var hasOpenBuffer: Bool {
        bufferID != 0
    }

    var canSave: Bool {
        hasOpenBuffer && isDirty
    }

    var isUntitled: Bool {
        hasOpenBuffer && fileURL == nil
    }

    var textBinding: Binding<String> {
        Binding(
            get: { self.text },
            set: { newValue in
                self.text = newValue
                self.replaceText(newValue)
            }
        )
    }

    var errorPresented: Binding<Bool> {
        Binding(
            get: { !self.errorMessage.isEmpty },
            set: { presented in
                if !presented {
                    self.errorMessage = ""
                }
            }
        )
    }

    func open(url: URL) {
        let openedID = url.path.withCString { path in
            feOpenFile(path)
        }

        guard openedID != 0 else {
            reportLastError(prefix: "Open failed")
            return
        }

        bufferID = openedID
        fileURL = url
        syncTextFromCore()
        syncRenderSnapshot()
        syncDirtyState()
        focusRevision += 1
        statusText = "Opened \(url.path)"
    }

    func newFile() {
        let newID = feNewFile()

        guard newID != 0 else {
            reportLastError(prefix: "New file failed")
            return
        }

        bufferID = newID
        fileURL = nil
        syncTextFromCore()
        syncRenderSnapshot()
        syncDirtyState()
        focusRevision += 1
        statusText = "New untitled file"
    }

    func save() -> Bool {
        guard hasOpenBuffer else {
            return false
        }

        if isUntitled {
            return false
        }

        replaceText(text)
        guard feSaveFile(bufferID) != 0 else {
            reportLastError(prefix: "Save failed")
            return false
        }

        syncRenderSnapshot()
        syncDirtyState()
        statusText = "Saved \(displayPath)"
        return true
    }

    func saveAs(url: URL) -> Bool {
        guard hasOpenBuffer else {
            return false
        }

        replaceText(text)
        let result = url.path.withCString { path in
            feSaveFileAs(bufferID, path)
        }

        guard result != 0 else {
            reportLastError(prefix: "Save failed")
            return false
        }

        fileURL = url
        syncPathFromCore()
        syncRenderSnapshot()
        syncDirtyState()
        statusText = "Saved \(displayPath)"
        return true
    }

    func replaceText(_ newText: String, cursorUTF8Offset: Int) {
        guard hasOpenBuffer, !isSyncingFromCore else {
            return
        }

        text = newText
        let bytes = Array(newText.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            feReplaceTextWithCursor(bufferID, buffer.baseAddress, buffer.count, cursorUTF8Offset)
        }

        if result == 0 {
            reportLastError(prefix: "Edit failed")
        } else {
            syncRenderSnapshot()
            syncDirtyState()
            statusText = isDirty ? "Unsaved changes in \(displayPath)" : "Saved \(displayPath)"
        }
    }

    func setCursorUTF8Offset(_ cursorUTF8Offset: Int) {
        guard hasOpenBuffer else {
            return
        }

        guard feSetCursorOffset(bufferID, cursorUTF8Offset) != 0 else {
            reportLastError(prefix: "Cursor update failed")
            return
        }

        syncRenderSnapshot()
    }

    func undo() {
        applyHistoryAction(feUndo, emptyMessage: "Nothing to undo")
    }

    func redo() {
        applyHistoryAction(feRedo, emptyMessage: "Nothing to redo")
    }

    private func syncTextFromCore() {
        guard hasOpenBuffer else {
            return
        }

        let value = feGetText(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            reportLastError(prefix: "Read failed")
            return
        }

        isSyncingFromCore = true
        text = String(decoding: UnsafeBufferPointer(start: pointer, count: value.len), as: UTF8.self)
        isSyncingFromCore = false
    }

    private func syncRenderSnapshot() {
        guard hasOpenBuffer else {
            renderSnapshot = .empty
            return
        }

        let value = feGetRenderSnapshot(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            reportLastError(prefix: "Render snapshot failed")
            return
        }

        let data = Data(bytes: pointer, count: value.len)

        do {
            renderSnapshot = try JSONDecoder().decode(EditorRenderSnapshot.self, from: data)
        } catch {
            errorMessage = "Render snapshot failed: \(error.localizedDescription)"
        }
    }

    private func syncPathFromCore() {
        guard hasOpenBuffer else {
            fileURL = nil
            return
        }

        let value = feGetPath(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr, value.len > 0 else {
            fileURL = nil
            return
        }

        let path = String(decoding: UnsafeBufferPointer(start: pointer, count: value.len), as: UTF8.self)
        fileURL = URL(fileURLWithPath: path)
    }

    private func replaceText(_ newText: String) {
        guard hasOpenBuffer, !isSyncingFromCore else {
            return
        }

        let bytes = Array(newText.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            feReplaceText(bufferID, buffer.baseAddress, buffer.count)
        }

        if result == 0 {
            reportLastError(prefix: "Edit failed")
        } else {
            syncRenderSnapshot()
            syncDirtyState()
            statusText = isDirty ? "Unsaved changes in \(displayPath)" : "Saved \(displayPath)"
        }
    }

    private func applyHistoryAction(_ action: (UInt64) -> Int32, emptyMessage: String) {
        guard hasOpenBuffer else {
            return
        }

        let result = action(bufferID)
        if result == 1 {
            syncTextFromCore()
            syncRenderSnapshot()
            syncDirtyState()
            statusText = isDirty ? "Unsaved changes in \(displayPath)" : "Saved \(displayPath)"
        } else if result == 0 {
            statusText = emptyMessage
        } else {
            reportLastError(prefix: "Edit history failed")
        }
    }

    private func syncDirtyState() {
        guard hasOpenBuffer else {
            isDirty = false
            return
        }

        let result = feIsDirty(bufferID)
        if result == -1 {
            reportLastError(prefix: "State read failed")
        } else {
            isDirty = result == 1
        }
    }

    private func reportLastError(prefix: String) {
        let value = feLastError()
        defer {
            feFreeString(value)
        }

        let detail: String
        if let pointer = value.ptr, value.len > 0 {
            detail = String(decoding: UnsafeBufferPointer(start: pointer, count: value.len), as: UTF8.self)
        } else {
            detail = "Unknown error"
        }

        errorMessage = "\(prefix): \(detail)"
    }

    private var displayPath: String {
        fileURL?.path ?? "Untitled"
    }
}

struct EditorRenderSnapshot: Decodable, Equatable {
    var bufferID: UInt64
    var dirty: Bool
    var cursorLine: Int
    var cursorColumn: Int
    var lines: [EditorRenderLine]

    static let empty = EditorRenderSnapshot(
        bufferID: 0,
        dirty: false,
        cursorLine: 0,
        cursorColumn: 0,
        lines: [EditorRenderLine(index: 0, lineNumber: 1, text: "", spans: [])]
    )

    private enum CodingKeys: String, CodingKey {
        case bufferID = "buffer_id"
        case dirty
        case cursorLine = "cursor_line"
        case cursorColumn = "cursor_column"
        case lines
    }
}

struct EditorRenderLine: Decodable, Equatable {
    var index: Int
    var lineNumber: Int
    var text: String
    var spans: [EditorRenderSpan]

    private enum CodingKeys: String, CodingKey {
        case index
        case lineNumber = "line_number"
        case text
        case spans
    }
}

struct EditorRenderSpan: Decodable, Equatable {
    var startColumn: Int
    var endColumn: Int
    var kind: EditorRenderSpanKind

    private enum CodingKeys: String, CodingKey {
        case startColumn = "start_column"
        case endColumn = "end_column"
        case kind
    }
}

enum EditorRenderSpanKind: String, Decodable {
    case markdownHeading = "markdown_heading"
    case markdownListMarker = "markdown_list_marker"
    case markdownQuote = "markdown_quote"
    case markdownCode = "markdown_code"
    case markdownInlineCode = "markdown_inline_code"
    case markdownLink = "markdown_link"
    case markdownEmphasis = "markdown_emphasis"
}
