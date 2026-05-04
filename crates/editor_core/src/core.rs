use std::collections::HashMap;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

pub type BufferId = u64;

#[derive(Debug)]
pub enum EditorError {
    Io(std::io::Error),
    MissingBuffer(BufferId),
    InvalidPath,
    InvalidUtf8,
    MissingPath(BufferId),
}

impl fmt::Display for EditorError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EditorError::Io(error) => write!(f, "{error}"),
            EditorError::MissingBuffer(id) => write!(f, "missing buffer {id}"),
            EditorError::InvalidPath => write!(f, "invalid path"),
            EditorError::InvalidUtf8 => write!(f, "invalid utf-8"),
            EditorError::MissingPath(id) => write!(f, "missing path for buffer {id}"),
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
    pub path: Option<PathBuf>,
    pub text: String,
    pub dirty: bool,
}

#[derive(Debug, Clone)]
struct Buffer {
    path: Option<PathBuf>,
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

    pub fn new_file(&mut self) -> BufferId {
        let id = self.allocate_buffer_id();
        self.buffers.insert(
            id,
            Buffer {
                path: None,
                text: String::new(),
                saved_text: String::new(),
            },
        );
        id
    }

    pub fn open_file(&mut self, path: impl AsRef<Path>) -> Result<BufferId, EditorError> {
        let path = path.as_ref().to_path_buf();
        let text = fs::read_to_string(&path)?;
        let id = self.allocate_buffer_id();
        self.buffers.insert(
            id,
            Buffer {
                path: Some(path),
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
        let path = buffer
            .path
            .as_ref()
            .ok_or(EditorError::MissingPath(buffer_id))?;
        fs::write(path, &buffer.text)?;
        buffer.saved_text = buffer.text.clone();
        Ok(())
    }

    pub fn save_file_as(
        &mut self,
        buffer_id: BufferId,
        path: impl AsRef<Path>,
    ) -> Result<(), EditorError> {
        let path = path.as_ref().to_path_buf();
        let buffer = self.buffer_mut(buffer_id)?;
        fs::write(&path, &buffer.text)?;
        buffer.path = Some(path);
        buffer.saved_text = buffer.text.clone();
        Ok(())
    }

    pub fn is_dirty(&self, buffer_id: BufferId) -> Result<bool, EditorError> {
        self.buffer(buffer_id)
            .map(|buffer| buffer.text != buffer.saved_text)
    }

    pub fn path(&self, buffer_id: BufferId) -> Result<Option<&Path>, EditorError> {
        self.buffer(buffer_id).map(|buffer| buffer.path.as_deref())
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
