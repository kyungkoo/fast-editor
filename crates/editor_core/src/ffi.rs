use crate::{BufferId, EditorCore, EditorError};
use std::ffi::CStr;
use std::fmt;
use std::os::raw::c_char;
use std::path::PathBuf;
use std::ptr;
use std::sync::{Mutex, OnceLock};

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
pub extern "C" fn fe_new_file() -> BufferId {
    match global_core().lock() {
        Ok(mut core) => {
            clear_last_error();
            core.new_file()
        }
        Err(_) => {
            set_last_error(EditorError::InvalidPath);
            0
        }
    }
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
pub extern "C" fn fe_get_render_snapshot(buffer_id: BufferId) -> FeString {
    let result = global_core()
        .lock()
        .map_err(|_| EditorError::MissingBuffer(buffer_id))
        .and_then(|core| core.render_snapshot(buffer_id))
        .and_then(|snapshot| {
            serde_json::to_string(&snapshot).map_err(|_| EditorError::InvalidUtf8)
        });

    match result {
        Ok(snapshot) => {
            clear_last_error();
            FeString::from_string(snapshot)
        }
        Err(error) => {
            set_last_error(error);
            FeString::empty()
        }
    }
}

#[no_mangle]
pub extern "C" fn fe_get_path(buffer_id: BufferId) -> FeString {
    let result = global_core()
        .lock()
        .map_err(|_| EditorError::MissingBuffer(buffer_id))
        .and_then(|core| {
            core.path(buffer_id)
                .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
        });

    match result {
        Ok(Some(path)) => {
            clear_last_error();
            FeString::from_string(path)
        }
        Ok(None) => {
            clear_last_error();
            FeString::empty()
        }
        Err(error) => {
            set_last_error(error);
            FeString::empty()
        }
    }
}

#[no_mangle]
pub extern "C" fn fe_replace_text(buffer_id: BufferId, text_ptr: *const u8, len: usize) -> i32 {
    replace_text(buffer_id, text_ptr, len, None)
}

#[no_mangle]
pub extern "C" fn fe_replace_text_with_cursor(
    buffer_id: BufferId,
    text_ptr: *const u8,
    len: usize,
    cursor_offset: usize,
) -> i32 {
    replace_text(buffer_id, text_ptr, len, Some(cursor_offset))
}

#[no_mangle]
pub extern "C" fn fe_set_cursor_offset(buffer_id: BufferId, cursor_offset: usize) -> i32 {
    let result = global_core()
        .lock()
        .map_err(|_| EditorError::MissingBuffer(buffer_id))
        .and_then(|mut core| core.set_cursor_offset(buffer_id, cursor_offset));

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

fn replace_text(
    buffer_id: BufferId,
    text_ptr: *const u8,
    len: usize,
    cursor_offset: Option<usize>,
) -> i32 {
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
            let mut core = global_core()
                .lock()
                .map_err(|_| EditorError::MissingBuffer(buffer_id))?;

            if let Some(cursor_offset) = cursor_offset {
                core.replace_text_with_cursor(buffer_id, text, cursor_offset)
            } else {
                core.replace_text(buffer_id, text)
            }
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
pub extern "C" fn fe_save_file_as(buffer_id: BufferId, path: *const c_char) -> i32 {
    let result = path_from_c(path).and_then(|path| {
        global_core()
            .lock()
            .map_err(|_| EditorError::MissingBuffer(buffer_id))?
            .save_file_as(buffer_id, path)
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
