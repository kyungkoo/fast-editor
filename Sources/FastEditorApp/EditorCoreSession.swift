final class EditorCoreSession {
    private(set) var currentBufferID: UInt64 = 0

    var hasOpenBuffer: Bool {
        currentBufferID != 0
    }

    deinit {
        close()
    }

    func replace(with bufferID: UInt64) {
        close()
        currentBufferID = bufferID
    }

    func close() {
        guard currentBufferID != 0 else {
            return
        }

        _ = feCloseBuffer(currentBufferID)
        currentBufferID = 0
    }
}
