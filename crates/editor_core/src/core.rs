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
    pub spans: Vec<RenderSpan>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RenderSpan {
    pub start_column: usize,
    pub end_column: usize,
    pub kind: RenderSpanKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RenderSpanKind {
    MarkdownHeading,
    MarkdownListMarker,
    MarkdownQuote,
    MarkdownCode,
    MarkdownInlineCode,
    MarkdownLink,
    MarkdownEmphasis,
}

#[derive(Debug, Clone)]
struct Buffer {
    path: Option<PathBuf>,
    text: String,
    saved_text: String,
    cursor_offset: usize,
    undo_stack: Vec<EditState>,
    redo_stack: Vec<EditState>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct EditState {
    text: String,
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
                undo_stack: Vec::new(),
                redo_stack: Vec::new(),
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
                undo_stack: Vec::new(),
                redo_stack: Vec::new(),
            },
        );
        Ok(id)
    }

    pub fn close_buffer(&mut self, buffer_id: BufferId) -> Result<(), EditorError> {
        self.buffers
            .remove(&buffer_id)
            .map(|_| ())
            .ok_or(EditorError::MissingBuffer(buffer_id))
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
        let text = text.into();
        let cursor_offset = clamp_to_char_boundary(&text, buffer.cursor_offset);
        buffer.replace_text(text, cursor_offset);
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
        buffer.replace_text(text, cursor_offset);
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

    pub fn undo(&mut self, buffer_id: BufferId) -> Result<bool, EditorError> {
        let buffer = self.buffer_mut(buffer_id)?;
        Ok(buffer.undo())
    }

    pub fn redo(&mut self, buffer_id: BufferId) -> Result<bool, EditorError> {
        let buffer = self.buffer_mut(buffer_id)?;
        Ok(buffer.redo())
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

    pub fn markdown_preview_html(&self, buffer_id: BufferId) -> Result<String, EditorError> {
        let buffer = self.buffer(buffer_id)?;
        Ok(markdown_preview_html(&buffer.text))
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

impl Buffer {
    fn edit_state(&self) -> EditState {
        EditState {
            text: self.text.clone(),
            cursor_offset: self.cursor_offset,
        }
    }

    fn replace_text(&mut self, text: String, cursor_offset: usize) {
        let cursor_offset = clamp_to_char_boundary(&text, cursor_offset);
        let next_state = EditState {
            text,
            cursor_offset,
        };

        if self.edit_state() == next_state {
            return;
        }

        self.undo_stack.push(self.edit_state());
        self.redo_stack.clear();
        self.apply_state(next_state);
    }

    fn undo(&mut self) -> bool {
        let Some(previous_state) = self.undo_stack.pop() else {
            return false;
        };

        self.redo_stack.push(self.edit_state());
        self.apply_state(previous_state);
        true
    }

    fn redo(&mut self) -> bool {
        let Some(next_state) = self.redo_stack.pop() else {
            return false;
        };

        self.undo_stack.push(self.edit_state());
        self.apply_state(next_state);
        true
    }

    fn apply_state(&mut self, state: EditState) {
        self.text = state.text;
        self.cursor_offset = clamp_to_char_boundary(&self.text, state.cursor_offset);
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
            spans: markdown_spans(line.trim_end_matches('\r')),
        })
        .collect();

    if lines.is_empty() {
        lines.push(RenderLine {
            index: 0,
            line_number: 1,
            text: String::new(),
            spans: Vec::new(),
        });
    }

    lines
}

fn markdown_spans(line: &str) -> Vec<RenderSpan> {
    let mut spans = Vec::new();
    let trimmed_start = line.trim_start_matches([' ', '\t']);
    let leading_columns = line.chars().count() - trimmed_start.chars().count();

    if is_markdown_heading(trimmed_start) {
        spans.push(RenderSpan {
            start_column: leading_columns,
            end_column: line.chars().count(),
            kind: RenderSpanKind::MarkdownHeading,
        });
        return spans;
    }

    if trimmed_start.starts_with("```") || trimmed_start.starts_with("~~~") {
        spans.push(RenderSpan {
            start_column: leading_columns,
            end_column: line.chars().count(),
            kind: RenderSpanKind::MarkdownCode,
        });
        return spans;
    }

    if trimmed_start.starts_with('>') {
        spans.push(RenderSpan {
            start_column: leading_columns,
            end_column: line.chars().count(),
            kind: RenderSpanKind::MarkdownQuote,
        });
    } else if let Some(marker_len) = markdown_list_marker_len(trimmed_start) {
        spans.push(RenderSpan {
            start_column: leading_columns,
            end_column: leading_columns + marker_len,
            kind: RenderSpanKind::MarkdownListMarker,
        });
    }

    spans.extend(markdown_inline_spans(line));
    spans.sort_by_key(|span| (span.start_column, span.end_column));
    spans
}

fn is_markdown_heading(line: &str) -> bool {
    let heading_marker_len = line
        .chars()
        .take_while(|character| *character == '#')
        .count();
    (1..=6).contains(&heading_marker_len)
        && line
            .chars()
            .nth(heading_marker_len)
            .is_some_and(char::is_whitespace)
}

fn markdown_list_marker_len(line: &str) -> Option<usize> {
    let mut chars = line.chars();
    match (chars.next(), chars.next()) {
        (Some('-' | '*' | '+'), Some(character)) if character.is_whitespace() => Some(1),
        (Some(first), _) if first.is_ascii_digit() => {
            let mut marker_len = 1;
            for character in line.chars().skip(1) {
                if character == '.' {
                    let next = line.chars().nth(marker_len + 1);
                    return next
                        .is_some_and(char::is_whitespace)
                        .then_some(marker_len + 1);
                }

                if !character.is_ascii_digit() {
                    return None;
                }
                marker_len += 1;
            }
            None
        }
        _ => None,
    }
}

fn markdown_inline_spans(line: &str) -> Vec<RenderSpan> {
    let characters: Vec<char> = line.chars().collect();
    let mut spans = Vec::new();
    let mut index = 0;

    while index < characters.len() {
        match characters[index] {
            '`' => {
                if let Some(end_index) = find_next(&characters, index + 1, '`') {
                    spans.push(RenderSpan {
                        start_column: index,
                        end_column: end_index + 1,
                        kind: RenderSpanKind::MarkdownInlineCode,
                    });
                    index = end_index + 1;
                    continue;
                }
            }
            '[' => {
                if let Some(link_end) = markdown_link_end(&characters, index) {
                    spans.push(RenderSpan {
                        start_column: index,
                        end_column: link_end,
                        kind: RenderSpanKind::MarkdownLink,
                    });
                    index = link_end;
                    continue;
                }
            }
            '*' | '_' => {
                let marker = characters[index];
                let marker_len = if characters
                    .get(index + 1)
                    .is_some_and(|character| *character == marker)
                {
                    2
                } else {
                    1
                };
                if let Some(end_index) =
                    find_emphasis_end(&characters, index + marker_len, marker, marker_len)
                {
                    spans.push(RenderSpan {
                        start_column: index,
                        end_column: end_index + marker_len,
                        kind: RenderSpanKind::MarkdownEmphasis,
                    });
                    index = end_index + marker_len;
                    continue;
                }
            }
            _ => {}
        }

        index += 1;
    }

    spans
}

fn markdown_preview_html(text: &str) -> String {
    let mut body = String::new();
    let mut in_unordered_list = false;
    let mut in_ordered_list = false;
    let mut in_code_block = false;

    for raw_line in text.lines() {
        let line = raw_line.trim_end_matches('\r');
        let trimmed = line.trim();

        if is_code_fence(trimmed) {
            close_lists(&mut body, &mut in_unordered_list, &mut in_ordered_list);
            if in_code_block {
                body.push_str("</code></pre>\n");
            } else {
                body.push_str("<pre><code>");
            }
            in_code_block = !in_code_block;
            continue;
        }

        if in_code_block {
            body.push_str(&escape_html(line));
            body.push('\n');
            continue;
        }

        if trimmed.is_empty() {
            close_lists(&mut body, &mut in_unordered_list, &mut in_ordered_list);
            continue;
        }

        if let Some((level, content)) = markdown_heading(trimmed) {
            close_lists(&mut body, &mut in_unordered_list, &mut in_ordered_list);
            body.push_str(&format!(
                "<h{level}>{}</h{level}>\n",
                markdown_inline_html(content.trim())
            ));
            continue;
        }

        if let Some(content) = unordered_list_item(line) {
            if in_ordered_list {
                body.push_str("</ol>\n");
                in_ordered_list = false;
            }
            if !in_unordered_list {
                body.push_str("<ul>\n");
                in_unordered_list = true;
            }
            body.push_str(&format!(
                "<li>{}</li>\n",
                markdown_inline_html(content.trim())
            ));
            continue;
        }

        if let Some(content) = ordered_list_item(line) {
            if in_unordered_list {
                body.push_str("</ul>\n");
                in_unordered_list = false;
            }
            if !in_ordered_list {
                body.push_str("<ol>\n");
                in_ordered_list = true;
            }
            body.push_str(&format!(
                "<li>{}</li>\n",
                markdown_inline_html(content.trim())
            ));
            continue;
        }

        close_lists(&mut body, &mut in_unordered_list, &mut in_ordered_list);

        if let Some(content) = trimmed.strip_prefix('>') {
            body.push_str(&format!(
                "<blockquote>{}</blockquote>\n",
                markdown_inline_html(content.trim())
            ));
        } else {
            body.push_str(&format!("<p>{}</p>\n", markdown_inline_html(trimmed)));
        }
    }

    if in_code_block {
        body.push_str("</code></pre>\n");
    }
    close_lists(&mut body, &mut in_unordered_list, &mut in_ordered_list);

    format!(
        r#"<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
:root {{
  color-scheme: light dark;
  font: -apple-system-body;
}}
body {{
  margin: 0;
  padding: 18px 22px;
  line-height: 1.55;
  color: CanvasText;
  background: Canvas;
}}
h1, h2, h3, h4, h5, h6 {{
  margin: 0.85em 0 0.35em;
  line-height: 1.2;
}}
p, blockquote, pre, ul, ol {{
  margin: 0.7em 0;
}}
ul, ol {{
  padding-left: 1.45em;
}}
li {{
  margin: 0.3em 0;
  padding-left: 0.15em;
}}
blockquote {{
  border-left: 3px solid #8abf88;
  color: color-mix(in srgb, CanvasText 70%, transparent);
  padding-left: 12px;
}}
code, pre {{
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
}}
code {{
  background: color-mix(in srgb, CanvasText 9%, transparent);
  border-radius: 4px;
  padding: 0.1em 0.35em;
}}
pre {{
  background: color-mix(in srgb, CanvasText 8%, transparent);
  border-radius: 6px;
  overflow: auto;
  padding: 12px;
  white-space: pre;
}}
pre code {{
  background: transparent;
  display: block;
  line-height: 1.45;
  padding: 0;
}}
a {{
  color: LinkText;
}}
</style>
</head>
<body>
{}
</body>
</html>"#,
        body
    )
}

fn is_code_fence(line: &str) -> bool {
    line.starts_with("```") || line.starts_with("~~~")
}

fn close_lists(body: &mut String, in_unordered_list: &mut bool, in_ordered_list: &mut bool) {
    if *in_unordered_list {
        body.push_str("</ul>\n");
        *in_unordered_list = false;
    }
    if *in_ordered_list {
        body.push_str("</ol>\n");
        *in_ordered_list = false;
    }
}

fn markdown_heading(line: &str) -> Option<(usize, &str)> {
    let marker_len = line
        .chars()
        .take_while(|character| *character == '#')
        .count();
    if (1..=6).contains(&marker_len)
        && line
            .chars()
            .nth(marker_len)
            .is_some_and(char::is_whitespace)
    {
        Some((marker_len, &line[marker_len..]))
    } else {
        None
    }
}

fn unordered_list_item(line: &str) -> Option<&str> {
    let line = line.trim_start();
    let mut chars = line.chars();
    match (chars.next(), chars.next()) {
        (Some('-' | '*' | '+'), Some(character)) if character.is_whitespace() => Some(&line[2..]),
        _ => None,
    }
}

fn ordered_list_item(line: &str) -> Option<&str> {
    let line = line.trim_start();
    let dot_index = line.find('.')?;
    if dot_index == 0
        || !line[..dot_index]
            .chars()
            .all(|character| character.is_ascii_digit())
    {
        return None;
    }

    let rest = &line[dot_index + 1..];
    let mut chars = rest.char_indices();
    let (_, first) = chars.next()?;
    if !first.is_whitespace() {
        return None;
    }

    Some(chars.next().map_or("", |(index, _)| &rest[index..]))
}

fn markdown_inline_html(text: &str) -> String {
    let characters: Vec<char> = text.chars().collect();
    let mut html = String::new();
    let mut index = 0;

    while index < characters.len() {
        match characters[index] {
            '`' => {
                if let Some(end_index) = find_next(&characters, index + 1, '`') {
                    html.push_str("<code>");
                    html.push_str(&escape_html(
                        &characters[index + 1..end_index].iter().collect::<String>(),
                    ));
                    html.push_str("</code>");
                    index = end_index + 1;
                    continue;
                }
            }
            '[' => {
                if let Some((close_bracket, close_paren)) = markdown_link_bounds(&characters, index)
                {
                    let label = characters[index + 1..close_bracket]
                        .iter()
                        .collect::<String>();
                    let href = characters[close_bracket + 2..close_paren]
                        .iter()
                        .collect::<String>();
                    html.push_str("<a href=\"");
                    html.push_str(&escape_html_attribute(&href));
                    html.push_str("\">");
                    html.push_str(&escape_html(&label));
                    html.push_str("</a>");
                    index = close_paren + 1;
                    continue;
                }
            }
            '*' | '_' => {
                let marker = characters[index];
                let marker_len = if characters
                    .get(index + 1)
                    .is_some_and(|character| *character == marker)
                {
                    2
                } else {
                    1
                };
                if let Some(end_index) =
                    find_emphasis_end(&characters, index + marker_len, marker, marker_len)
                {
                    let content = characters[index + marker_len..end_index]
                        .iter()
                        .collect::<String>();
                    if marker_len == 2 {
                        html.push_str("<strong>");
                        html.push_str(&escape_html(&content));
                        html.push_str("</strong>");
                    } else {
                        html.push_str("<em>");
                        html.push_str(&escape_html(&content));
                        html.push_str("</em>");
                    }
                    index = end_index + marker_len;
                    continue;
                }
            }
            _ => {}
        }

        html.push_str(&escape_html(&characters[index].to_string()));
        index += 1;
    }

    html
}

fn markdown_link_bounds(characters: &[char], start: usize) -> Option<(usize, usize)> {
    let close_bracket = find_next(characters, start + 1, ']')?;
    if characters.get(close_bracket + 1) != Some(&'(') {
        return None;
    }

    let close_paren = find_next(characters, close_bracket + 2, ')')?;
    Some((close_bracket, close_paren))
}

fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn escape_html_attribute(text: &str) -> String {
    escape_html(text).replace('"', "&quot;")
}

fn find_next(characters: &[char], start: usize, target: char) -> Option<usize> {
    characters
        .iter()
        .enumerate()
        .skip(start)
        .find_map(|(index, character)| (*character == target).then_some(index))
}

fn markdown_link_end(characters: &[char], start: usize) -> Option<usize> {
    let close_bracket = find_next(characters, start + 1, ']')?;
    if characters.get(close_bracket + 1) != Some(&'(') {
        return None;
    }

    let close_paren = find_next(characters, close_bracket + 2, ')')?;
    Some(close_paren + 1)
}

fn find_emphasis_end(
    characters: &[char],
    start: usize,
    marker: char,
    marker_len: usize,
) -> Option<usize> {
    let mut index = start;
    while index + marker_len <= characters.len() {
        let is_match = characters[index..index + marker_len]
            .iter()
            .all(|character| *character == marker);
        if is_match {
            return Some(index);
        }
        index += 1;
    }

    None
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
