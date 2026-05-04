import Foundation
import SwiftUI

private struct FeString {
    let ptr: UnsafeMutablePointer<UInt8>?
    let len: Int
}

@_silgen_name("fe_open_file")
private func feOpenFile(_ path: UnsafePointer<CChar>) -> UInt64

@_silgen_name("fe_get_text")
private func feGetText(_ bufferID: UInt64) -> FeString

@_silgen_name("fe_replace_text")
private func feReplaceText(_ bufferID: UInt64, _ text: UnsafePointer<UInt8>?, _ len: Int) -> Int32

@_silgen_name("fe_save_file")
private func feSaveFile(_ bufferID: UInt64) -> Int32

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
        syncDirtyState()
        focusRevision += 1
        statusText = "Opened \(url.path)"
    }

    func save() {
        guard hasOpenBuffer else {
            return
        }

        replaceText(text)
        guard feSaveFile(bufferID) != 0 else {
            reportLastError(prefix: "Save failed")
            return
        }

        syncDirtyState()
        statusText = "Saved \(displayPath)"
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
            syncDirtyState()
            statusText = isDirty ? "Unsaved changes in \(displayPath)" : "Saved \(displayPath)"
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
        fileURL?.path ?? "file"
    }
}
