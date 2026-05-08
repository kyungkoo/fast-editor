import Foundation

struct FeString {
    let ptr: UnsafeMutablePointer<UInt8>?
    let len: Int
}

@_silgen_name("fe_open_file")
func feOpenFile(_ path: UnsafePointer<CChar>) -> UInt64

@_silgen_name("fe_new_file")
func feNewFile() -> UInt64

@_silgen_name("fe_close_buffer")
func feCloseBuffer(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_get_text")
func feGetText(_ bufferID: UInt64) -> FeString

@_silgen_name("fe_get_render_snapshot")
func feGetRenderSnapshot(_ bufferID: UInt64) -> FeString

@_silgen_name("fe_get_markdown_preview_html")
func feGetMarkdownPreviewHTML(_ bufferID: UInt64) -> FeString

@_silgen_name("fe_get_path")
func feGetPath(_ bufferID: UInt64) -> FeString

@_silgen_name("fe_detect_agent_providers")
func feDetectAgentProviders() -> FeString

@_silgen_name("fe_replace_text")
func feReplaceText(_ bufferID: UInt64, _ text: UnsafePointer<UInt8>?, _ len: Int) -> Int32

@_silgen_name("fe_replace_text_with_cursor")
func feReplaceTextWithCursor(
    _ bufferID: UInt64,
    _ text: UnsafePointer<UInt8>?,
    _ len: Int,
    _ cursorOffset: Int
) -> Int32

@_silgen_name("fe_set_cursor_offset")
func feSetCursorOffset(_ bufferID: UInt64, _ cursorOffset: Int) -> Int32

@_silgen_name("fe_undo")
func feUndo(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_redo")
func feRedo(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_save_file")
func feSaveFile(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_save_file_as")
func feSaveFileAs(_ bufferID: UInt64, _ path: UnsafePointer<CChar>) -> Int32

@_silgen_name("fe_is_dirty")
func feIsDirty(_ bufferID: UInt64) -> Int32

@_silgen_name("fe_last_error")
func feLastError() -> FeString

@_silgen_name("fe_free_string")
func feFreeString(_ value: FeString)
