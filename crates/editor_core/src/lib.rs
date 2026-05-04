use std::collections::HashMap;
use std::ffi::CStr;
use std::fmt;
use std::fs;
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::{Mutex, OnceLock};

pub type BufferId = u64;

#[derive(Debug)]
pub enum EditorError {
    Io(std::io::Error),
    MissingBuffer(BufferId),
    InvalidPath,
    InvalidUtf8,
}

impl fmt::Display for EditorError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EditorError::Io(error) => write!(f, "{error}"),
            EditorError::MissingBuffer(id) => write!(f, "missing buffer {id}"),
            EditorError::InvalidPath => write!(f, "invalid path"),
            EditorError::InvalidUtf8 => write!(f, "invalid utf-8"),
        }
    }
}

impl std::error::Error for EditorError {}

impl From<std::io::Error> for EditorError {
    fn from(error: std::io::Error) -> Self {
        EditorError::Io(error)
    }
}

#[derive(Debug, Clone)]
pub struct BufferSnapshot {
    pub id: BufferId,
    pub path: PathBuf,
    pub text: String,
    pub dirty: bool,
}

#[derive(Debug, Clone)]
struct Buffer {
    path: PathBuf,
    text: String,
    saved_text: String,
}

#[derive(Debug, Default)]
pub struct EditorCore {
    next_buffer_id: BufferId,
    buffers: HashMap<BufferId, Buffer>,
}

impl EditorCore {
    pub fn new() -> Self {
        Self {
            next_buffer_id: 1,
            buffers: HashMap::new(),
        }
    }

    pub fn open_file(&mut self, path: impl AsRef<Path>) -> Result<BufferId, EditorError> {
        let path = path.as_ref().to_path_buf();
        let text = fs::read_to_string(&path)?;
        let id = self.allocate_buffer_id();
        self.buffers.insert(
            id,
            Buffer {
                path,
                saved_text: text.clone(),
                text,
            },
        );
        Ok(id)
    }

    pub fn get_text(&self, buffer_id: BufferId) -> Result<&str, EditorError> {
        self.buffer(buffer_id).map(|buffer| buffer.text.as_str())
    }

    pub fn replace_text(
        &mut self,
        buffer_id: BufferId,
        text: impl Into<String>,
    ) -> Result<(), EditorError> {
        let buffer = self.buffer_mut(buffer_id)?;
        buffer.text = text.into();
        Ok(())
    }

    pub fn save_file(&mut self, buffer_id: BufferId) -> Result<(), EditorError> {
        let buffer = self.buffer_mut(buffer_id)?;
        fs::write(&buffer.path, &buffer.text)?;
        buffer.saved_text = buffer.text.clone();
        Ok(())
    }

    pub fn is_dirty(&self, buffer_id: BufferId) -> Result<bool, EditorError> {
        self.buffer(buffer_id)
            .map(|buffer| buffer.text != buffer.saved_text)
    }

    pub fn snapshot(&self, buffer_id: BufferId) -> Result<BufferSnapshot, EditorError> {
        let buffer = self.buffer(buffer_id)?;
        Ok(BufferSnapshot {
            id: buffer_id,
            path: buffer.path.clone(),
            text: buffer.text.clone(),
            dirty: buffer.text != buffer.saved_text,
        })
    }

    fn allocate_buffer_id(&mut self) -> BufferId {
        let id = self.next_buffer_id;
        self.next_buffer_id += 1;
        id
    }

    fn buffer(&self, buffer_id: BufferId) -> Result<&Buffer, EditorError> {
        self.buffers
            .get(&buffer_id)
            .ok_or(EditorError::MissingBuffer(buffer_id))
    }

    fn buffer_mut(&mut self, buffer_id: BufferId) -> Result<&mut Buffer, EditorError> {
        self.buffers
            .get_mut(&buffer_id)
            .ok_or(EditorError::MissingBuffer(buffer_id))
    }
}

#[repr(C)]
pub struct FeString {
    pub ptr: *mut u8,
    pub len: usize,
}

impl FeString {
    fn empty() -> Self {
        Self {
            ptr: ptr::null_mut(),
            len: 0,
        }
    }

    fn from_string(value: String) -> Self {
        let bytes = value.into_bytes().into_boxed_slice();
        let len = bytes.len();
        let ptr = Box::into_raw(bytes) as *mut u8;
        Self { ptr, len }
    }
}

static CORE: OnceLock<Mutex<EditorCore>> = OnceLock::new();
static LAST_ERROR: OnceLock<Mutex<Option<String>>> = OnceLock::new();

fn global_core() -> &'static Mutex<EditorCore> {
    CORE.get_or_init(|| Mutex::new(EditorCore::new()))
}

fn last_error_slot() -> &'static Mutex<Option<String>> {
    LAST_ERROR.get_or_init(|| Mutex::new(None))
}

fn set_last_error(error: impl fmt::Display) {
    if let Ok(mut slot) = last_error_slot().lock() {
        *slot = Some(error.to_string());
    }
}

fn clear_last_error() {
    if let Ok(mut slot) = last_error_slot().lock() {
        *slot = None;
    }
}

fn path_from_c(path: *const c_char) -> Result<PathBuf, EditorError> {
    if path.is_null() {
        return Err(EditorError::InvalidPath);
    }

    let value = unsafe { CStr::from_ptr(path) };
    let value = value.to_str().map_err(|_| EditorError::InvalidPath)?;
    Ok(PathBuf::from(value))
}

#[no_mangle]
pub extern "C" fn fe_open_file(path: *const c_char) -> BufferId {
    let result = path_from_c(path).and_then(|path| {
        global_core()
            .lock()
            .map_err(|_| EditorError::InvalidPath)?
            .open_file(path)
    });

    match result {
        Ok(buffer_id) => {
            clear_last_error();
            buffer_id
        }
        Err(error) => {
            set_last_error(error);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn fe_get_text(buffer_id: BufferId) -> FeString {
    let result = global_core()
        .lock()
        .map_err(|_| EditorError::MissingBuffer(buffer_id))
        .and_then(|core| core.get_text(buffer_id).map(ToOwned::to_owned));

    match result {
        Ok(text) => {
            clear_last_error();
            FeString::from_string(text)
        }
        Err(error) => {
            set_last_error(error);
            FeString::empty()
        }
    }
}

#[no_mangle]
pub extern "C" fn fe_replace_text(buffer_id: BufferId, text_ptr: *const u8, len: usize) -> i32 {
    if text_ptr.is_null() && len != 0 {
        set_last_error(EditorError::InvalidUtf8);
        return 0;
    }

    let bytes = if len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(text_ptr, len) }
    };

    let result = std::str::from_utf8(bytes)
        .map_err(|_| EditorError::InvalidUtf8)
        .and_then(|text| {
            global_core()
                .lock()
                .map_err(|_| EditorError::MissingBuffer(buffer_id))?
                .replace_text(buffer_id, text)
        });

    match result {
        Ok(()) => {
            clear_last_error();
            1
        }
        Err(error) => {
            set_last_error(error);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn fe_save_file(buffer_id: BufferId) -> i32 {
    let result = global_core()
        .lock()
        .map_err(|_| EditorError::MissingBuffer(buffer_id))
        .and_then(|mut core| core.save_file(buffer_id));

    match result {
        Ok(()) => {
            clear_last_error();
            1
        }
        Err(error) => {
            set_last_error(error);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn fe_is_dirty(buffer_id: BufferId) -> i32 {
    let result = global_core()
        .lock()
        .map_err(|_| EditorError::MissingBuffer(buffer_id))
        .and_then(|core| core.is_dirty(buffer_id));

    match result {
        Ok(true) => {
            clear_last_error();
            1
        }
        Ok(false) => {
            clear_last_error();
            0
        }
        Err(error) => {
            set_last_error(error);
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn fe_last_error() -> FeString {
    let error = last_error_slot()
        .lock()
        .ok()
        .and_then(|slot| slot.clone())
        .unwrap_or_default();
    FeString::from_string(error)
}

#[no_mangle]
pub extern "C" fn fe_free_string(value: FeString) {
    if value.ptr.is_null() {
        return;
    }

    let slice = ptr::slice_from_raw_parts_mut(value.ptr, value.len);
    unsafe {
        drop(Box::from_raw(slice));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::time::{SystemTime, UNIX_EPOCH};

    static FFI_TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    #[test]
    fn open_file_reads_text_into_buffer() {
        let path = write_temp_file("open_file_reads_text_into_buffer", "hello");
        let mut core = EditorCore::new();

        let buffer_id = core.open_file(&path).expect("open file");

        assert_eq!(core.get_text(buffer_id).expect("buffer text"), "hello");
        assert!(!core.snapshot(buffer_id).expect("snapshot").dirty);
        let _ = fs::remove_file(path);
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
}
