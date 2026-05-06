use std::collections::HashMap;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;

pub type BufferId = u64;

#[derive(Debug)]
pub enum EditorError {
    Io(std::io::Error),
    MissingBuffer(BufferId),
    InvalidPath,
    InvalidUtf8,
    InvalidCursorOffset(usize),
    MissingPath(BufferId),
}

impl fmt::Display for EditorError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EditorError::Io(error) => write!(f, "{error}"),
            EditorError::MissingBuffer(id) => write!(f, "missing buffer {id}"),
            EditorError::InvalidPath => write!(f, "invalid path"),
            EditorError::InvalidUtf8 => write!(f, "invalid utf-8"),
            EditorError::InvalidCursorOffset(offset) => {
                write!(f, "invalid cursor offset {offset}")
            }
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

#[derive(Debug, Clone, Serialize)]
pub struct RenderSnapshot {
    pub buffer_id: BufferId,
    pub dirty: bool,
    pub cursor_line: usize,
    pub cursor_column: usize,
    pub lines: Vec<RenderLine>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RenderLine {
    pub index: usize,
    pub line_number: usize,
    pub text: String,
}

#[derive(Debug, Clone)]
struct Buffer {
    path: Option<PathBuf>,
    text: String,
    saved_text: String,
    cursor_offset: usize,
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
                cursor_offset: 0,
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
                cursor_offset: 0,
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
        buffer.cursor_offset = clamp_to_char_boundary(&buffer.text, buffer.cursor_offset);
        Ok(())
    }

    pub fn replace_text_with_cursor(
        &mut self,
        buffer_id: BufferId,
        text: impl Into<String>,
        cursor_offset: usize,
    ) -> Result<(), EditorError> {
        let text = text.into();
        if !text.is_char_boundary(cursor_offset) {
            return Err(EditorError::InvalidCursorOffset(cursor_offset));
        }

        let buffer = self.buffer_mut(buffer_id)?;
        buffer.text = text;
        buffer.cursor_offset = cursor_offset;
        Ok(())
    }

    pub fn set_cursor_offset(
        &mut self,
        buffer_id: BufferId,
        cursor_offset: usize,
    ) -> Result<(), EditorError> {
        let buffer = self.buffer_mut(buffer_id)?;
        if !buffer.text.is_char_boundary(cursor_offset) {
            return Err(EditorError::InvalidCursorOffset(cursor_offset));
        }

        buffer.cursor_offset = cursor_offset;
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

    pub fn render_snapshot(&self, buffer_id: BufferId) -> Result<RenderSnapshot, EditorError> {
        let buffer = self.buffer(buffer_id)?;
        let lines = split_render_lines(&buffer.text);
        let (cursor_line, cursor_column) = cursor_position(&buffer.text, buffer.cursor_offset);

        Ok(RenderSnapshot {
            buffer_id,
            dirty: buffer.text != buffer.saved_text,
            cursor_line,
            cursor_column,
            lines,
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

fn split_render_lines(text: &str) -> Vec<RenderLine> {
    let mut lines: Vec<RenderLine> = text
        .split('\n')
        .enumerate()
        .map(|(index, line)| RenderLine {
            index,
            line_number: index + 1,
            text: line.trim_end_matches('\r').to_owned(),
        })
        .collect();

    if lines.is_empty() {
        lines.push(RenderLine {
            index: 0,
            line_number: 1,
            text: String::new(),
        });
    }

    lines
}

fn cursor_position(text: &str, cursor_offset: usize) -> (usize, usize) {
    let cursor_offset = clamp_to_char_boundary(text, cursor_offset);
    let mut line = 0;
    let mut column = 0;

    for character in text[..cursor_offset].chars() {
        if character == '\n' {
            line += 1;
            column = 0;
        } else {
            column += 1;
        }
    }

    (line, column)
}

fn clamp_to_char_boundary(text: &str, cursor_offset: usize) -> usize {
    let mut cursor_offset = cursor_offset.min(text.len());
    while !text.is_char_boundary(cursor_offset) {
        cursor_offset -= 1;
    }
    cursor_offset
}
