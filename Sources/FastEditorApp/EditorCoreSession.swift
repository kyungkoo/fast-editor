import FastEditorModels
import Foundation

final class EditorCoreSession {
    private(set) var currentBufferID: UInt64 = 0
    private(set) var openBuffers: [EditorOpenBuffer] = []

    var hasOpenBuffer: Bool {
        currentBufferID != 0
    }

    deinit {
        close()
    }

    func open(buffer: EditorOpenBuffer) {
        if !openBuffers.contains(where: { $0.id == buffer.id }) {
            openBuffers.append(buffer)
        }
        currentBufferID = buffer.id
    }

    func switchToBuffer(id bufferID: UInt64) -> Bool {
        guard openBuffers.contains(where: { $0.id == bufferID }) else {
            return false
        }

        currentBufferID = bufferID
        return true
    }

    func updateCurrentBuffer(fileURL: URL?, isDirty: Bool) {
        updateBuffer(id: currentBufferID, fileURL: fileURL, isDirty: isDirty)
    }

    func updateBuffer(id bufferID: UInt64, fileURL: URL?, isDirty: Bool) {
        guard let index = openBuffers.firstIndex(where: { $0.id == bufferID }) else {
            return
        }

        openBuffers[index].fileURL = fileURL
        openBuffers[index].isDirty = isDirty
    }

    func buffer(for id: UInt64) -> EditorOpenBuffer? {
        openBuffers.first { $0.id == id }
    }

    func buffer(forFileURL url: URL) -> EditorOpenBuffer? {
        let standardizedURL = url.standardizedFileURL
        return openBuffers.first { buffer in
            buffer.fileURL?.standardizedFileURL == standardizedURL
        }
    }

    @discardableResult
    func closeBuffer(id bufferID: UInt64) -> UInt64 {
        guard let index = openBuffers.firstIndex(where: { $0.id == bufferID }) else {
            return currentBufferID
        }

        _ = feCloseBuffer(bufferID)
        openBuffers.remove(at: index)

        if currentBufferID == bufferID {
            if openBuffers.isEmpty {
                currentBufferID = 0
            } else {
                let nextIndex = min(index, openBuffers.count - 1)
                currentBufferID = openBuffers[nextIndex].id
            }
        }

        return currentBufferID
    }

    func close() {
        for buffer in openBuffers {
            _ = feCloseBuffer(buffer.id)
        }

        currentBufferID = 0
        openBuffers = []
    }
}
