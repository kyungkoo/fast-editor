use crate::ffi::*;
use crate::{BufferId, EditorCore, EditorError};
use std::ffi::CString;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

static FFI_TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

#[test]
fn open_file_reads_text_into_buffer() {
    let path = write_temp_file("open_file_reads_text_into_buffer", "hello");
    let mut core = EditorCore::new();

    let buffer_id = core.open_file(&path).expect("open file");

    assert_eq!(core.get_text(buffer_id).expect("buffer text"), "hello");
    assert!(!core.snapshot(buffer_id).expect("snapshot").dirty);
    assert_eq!(core.path(buffer_id).expect("path"), Some(path.as_path()));
    let _ = fs::remove_file(path);
}

#[test]
fn new_file_creates_empty_clean_untitled_buffer() {
    let mut core = EditorCore::new();

    let buffer_id = core.new_file();

    assert_eq!(core.get_text(buffer_id).expect("buffer text"), "");
    assert!(!core.is_dirty(buffer_id).expect("dirty state"));
    assert!(core.path(buffer_id).expect("path").is_none());
}

#[test]
fn replace_text_marks_buffer_dirty() {
    let path = write_temp_file("replace_text_marks_buffer_dirty", "before");
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open file");

    core.replace_text(buffer_id, "after").expect("replace text");

    let snapshot = core.snapshot(buffer_id).expect("snapshot");
    assert_eq!(snapshot.text, "after");
    assert!(snapshot.dirty);
    let _ = fs::remove_file(path);
}

#[test]
fn replacing_text_with_saved_contents_clears_dirty_state() {
    let path = write_temp_file(
        "replacing_text_with_saved_contents_clears_dirty_state",
        "before",
    );
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open file");

    core.replace_text(buffer_id, "after").expect("replace text");
    assert!(core.is_dirty(buffer_id).expect("dirty state"));

    core.replace_text(buffer_id, "before")
        .expect("replace text");

    assert!(!core.is_dirty(buffer_id).expect("dirty state"));
    assert!(!core.snapshot(buffer_id).expect("snapshot").dirty);
    let _ = fs::remove_file(path);
}

#[test]
fn untitled_buffer_clears_dirty_when_replaced_with_empty_baseline() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text(buffer_id, "draft").expect("replace text");
    assert!(core.is_dirty(buffer_id).expect("dirty state"));

    core.replace_text(buffer_id, "").expect("replace text");

    assert!(!core.is_dirty(buffer_id).expect("dirty state"));
}

#[test]
fn save_file_without_path_returns_missing_path() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    let error = core.save_file(buffer_id).expect_err("missing path error");

    assert!(matches!(error, EditorError::MissingPath(id) if id == buffer_id));
}

#[test]
fn save_file_as_assigns_path_writes_to_disk_and_updates_baseline() {
    let path = make_temp_path("save_file_as_assigns_path_writes_to_disk", "txt");
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text(buffer_id, "draft").expect("replace text");
    core.save_file_as(buffer_id, &path).expect("save file as");

    assert_eq!(core.path(buffer_id).expect("path"), Some(path.as_path()));
    assert_eq!(fs::read_to_string(&path).expect("read file"), "draft");
    assert!(!core.is_dirty(buffer_id).expect("dirty state"));

    core.replace_text(buffer_id, "next").expect("replace text");
    assert!(core.is_dirty(buffer_id).expect("dirty state"));
    let _ = fs::remove_file(path);
}

#[test]
fn save_file_writes_replacement_to_disk() {
    let path = write_temp_file("save_file_writes_replacement_to_disk", "before");
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open file");

    core.replace_text(buffer_id, "after").expect("replace text");
    core.save_file(buffer_id).expect("save file");

    assert_eq!(fs::read_to_string(&path).expect("read file"), "after");
    assert!(!core.snapshot(buffer_id).expect("snapshot").dirty);
    let _ = fs::remove_file(path);
}

#[test]
fn open_file_supports_empty_files() {
    let path = write_temp_file("open_file_supports_empty_files", "");
    let mut core = EditorCore::new();

    let buffer_id = core.open_file(&path).expect("open file");

    assert_eq!(core.get_text(buffer_id).expect("buffer text"), "");
    assert!(!core.is_dirty(buffer_id).expect("dirty state"));
    let _ = fs::remove_file(path);
}

#[test]
fn missing_buffer_returns_error() {
    let mut core = EditorCore::new();

    let error = core.save_file(42).expect_err("missing buffer error");

    assert!(matches!(error, EditorError::MissingBuffer(42)));
}

#[test]
fn failed_save_keeps_buffer_dirty() {
    let dir = make_temp_dir("failed_save_keeps_buffer_dirty");
    let path = dir.join("sample.txt");
    fs::write(&path, "before").expect("write temp file");
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open file");

    core.replace_text(buffer_id, "after").expect("replace text");
    fs::remove_file(&path).expect("remove temp file");
    fs::remove_dir(&dir).expect("remove temp dir");

    assert!(core.save_file(buffer_id).is_err());
    assert!(core.is_dirty(buffer_id).expect("dirty state"));
}

#[test]
fn ffi_rejects_invalid_utf8_replacement() {
    let _guard = ffi_test_lock();
    let invalid = [0xff, 0xfe, 0xfd];

    let result = fe_replace_text(999, invalid.as_ptr(), invalid.len());

    assert_eq!(result, 0);
    assert_eq!(take_ffi_string(fe_last_error()), "invalid utf-8");
}

#[test]
fn ffi_reports_dirty_state_for_missing_buffer() {
    let _guard = ffi_test_lock();
    let result = fe_is_dirty(999);

    assert_eq!(result, -1);
    assert_eq!(take_ffi_string(fe_last_error()), "missing buffer 999");
}

#[test]
fn ffi_new_file_creates_empty_clean_untitled_buffer() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(take_ffi_string(fe_get_text(buffer_id)), "");
    assert_eq!(take_ffi_string(fe_get_path(buffer_id)), "");
    assert_eq!(fe_is_dirty(buffer_id), 0);
}

#[test]
fn ffi_untitled_buffer_dirty_state_tracks_empty_baseline() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text(buffer_id, "draft"), 1);
    assert_eq!(fe_is_dirty(buffer_id), 1);

    assert_eq!(ffi_replace_text(buffer_id, ""), 1);
    assert_eq!(fe_is_dirty(buffer_id), 0);
}

#[test]
fn ffi_save_file_as_assigns_path_and_updates_dirty_baseline() {
    let _guard = ffi_test_lock();
    let path = make_temp_path(
        "ffi_save_file_as_assigns_path_and_updates_dirty_baseline",
        "txt",
    );
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text(buffer_id, "draft"), 1);
    assert_eq!(fe_is_dirty(buffer_id), 1);

    assert_eq!(ffi_save_file_as(buffer_id, &path), 1);
    assert_eq!(fe_is_dirty(buffer_id), 0);
    assert_eq!(
        take_ffi_string(fe_get_path(buffer_id)),
        path.to_string_lossy()
    );
    assert_eq!(fs::read_to_string(&path).expect("read file"), "draft");
    let _ = fs::remove_file(path);
}

#[test]
fn ffi_save_file_reports_missing_path_for_untitled_buffer() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(fe_save_file(buffer_id), 0);
    assert_eq!(
        take_ffi_string(fe_last_error()),
        format!("missing path for buffer {buffer_id}")
    );
}

#[test]
fn ffi_editing_back_to_saved_text_clears_dirty_state() {
    let _guard = ffi_test_lock();
    let path = write_temp_file(
        "ffi_editing_back_to_saved_text_clears_dirty_state",
        "before",
    );
    let buffer_id = ffi_open_file(&path);

    assert_ne!(buffer_id, 0);
    assert_eq!(take_ffi_string(fe_get_text(buffer_id)), "before");
    assert_eq!(fe_is_dirty(buffer_id), 0);

    assert_eq!(ffi_replace_text(buffer_id, "after"), 1);
    assert_eq!(fe_is_dirty(buffer_id), 1);

    assert_eq!(ffi_replace_text(buffer_id, "before"), 1);
    assert_eq!(fe_is_dirty(buffer_id), 0);
    let _ = fs::remove_file(path);
}

#[test]
fn ffi_save_updates_dirty_baseline_and_disk_contents() {
    let _guard = ffi_test_lock();
    let path = write_temp_file(
        "ffi_save_updates_dirty_baseline_and_disk_contents",
        "before",
    );
    let buffer_id = ffi_open_file(&path);

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text(buffer_id, "after"), 1);
    assert_eq!(fe_is_dirty(buffer_id), 1);

    assert_eq!(fe_save_file(buffer_id), 1);
    assert_eq!(fe_is_dirty(buffer_id), 0);
    assert_eq!(fs::read_to_string(&path).expect("read file"), "after");

    assert_eq!(ffi_replace_text(buffer_id, "after again"), 1);
    assert_eq!(fe_is_dirty(buffer_id), 1);
    let _ = fs::remove_file(path);
}

fn ffi_test_lock() -> std::sync::MutexGuard<'static, ()> {
    FFI_TEST_LOCK
        .get_or_init(|| Mutex::new(()))
        .lock()
        .expect("ffi test lock")
}

fn ffi_open_file(path: &Path) -> BufferId {
    let path = CString::new(path.to_string_lossy().as_bytes()).expect("ffi path");
    fe_open_file(path.as_ptr())
}

fn ffi_replace_text(buffer_id: BufferId, text: &str) -> i32 {
    fe_replace_text(buffer_id, text.as_ptr(), text.len())
}

fn ffi_save_file_as(buffer_id: BufferId, path: &Path) -> i32 {
    let path = CString::new(path.to_string_lossy().as_bytes()).expect("ffi path");
    fe_save_file_as(buffer_id, path.as_ptr())
}

fn write_temp_file(name: &str, text: &str) -> PathBuf {
    let path = make_temp_path(name, "txt");
    fs::write(&path, text).expect("write temp file");
    path
}

fn make_temp_dir(name: &str) -> PathBuf {
    let path = make_temp_path(name, "dir");
    fs::create_dir(&path).expect("create temp dir");
    path
}

fn make_temp_path(name: &str, extension: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system time")
        .as_nanos();
    std::env::temp_dir().join(format!("fast_editor_{name}_{nonce}.{extension}"))
}

fn take_ffi_string(value: FeString) -> String {
    let text = if value.ptr.is_null() {
        String::new()
    } else {
        let bytes = unsafe { std::slice::from_raw_parts(value.ptr, value.len) };
        String::from_utf8(bytes.to_vec()).expect("utf-8 ffi string")
    };
    fe_free_string(value);
    text
}
