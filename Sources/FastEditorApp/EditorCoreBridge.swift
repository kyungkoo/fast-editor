import Foundation
import SwiftUI

@MainActor
final class EditorCoreBridge: ObservableObject {
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var fileURL: URL?
    @Published private(set) var statusText = "Open a file to start editing through the Rust core."
    @Published private(set) var isDirty = false
    @Published private(set) var focusRevision = 0
    @Published private(set) var renderSnapshot = EditorRenderSnapshot.empty
    @Published private(set) var markdownPreviewHTML = ""
    @Published var text = ""
    @Published var errorMessage = ""

    private let session = EditorCoreSession()
    private var isSyncingFromCore = false

    private var bufferID: UInt64 {
        session.currentBufferID
    }

    var hasOpenBuffer: Bool {
        session.hasOpenBuffer
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

        session.replace(with: openedID)
        fileURL = url
        syncTextFromCore()
        syncRenderSnapshot()
        syncMarkdownPreviewHTML()
        syncDirtyState()
        focusRevision += 1
        statusText = "Opened \(url.path)"
    }

    func openFolder(url: URL) {
        workspaceURL = url
        statusText = "Opened folder \(url.path)"
    }

    func newFile() {
        let newID = feNewFile()

        guard newID != 0 else {
            reportLastError(prefix: "New file failed")
            return
        }

        session.replace(with: newID)
        fileURL = nil
        syncTextFromCore()
        syncRenderSnapshot()
        syncMarkdownPreviewHTML()
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
        syncMarkdownPreviewHTML()
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
        syncMarkdownPreviewHTML()
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
            syncMarkdownPreviewHTML()
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

    private func syncMarkdownPreviewHTML() {
        guard hasOpenBuffer else {
            markdownPreviewHTML = ""
            return
        }

        let value = feGetMarkdownPreviewHTML(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            reportLastError(prefix: "Markdown preview failed")
            return
        }

        markdownPreviewHTML = String(
            decoding: UnsafeBufferPointer(start: pointer, count: value.len),
            as: UTF8.self
        )
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
            syncMarkdownPreviewHTML()
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
            syncMarkdownPreviewHTML()
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
