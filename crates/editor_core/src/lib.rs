mod core;
mod ffi;

#[cfg(test)]
mod tests;

pub use core::{
    BufferId, BufferSnapshot, DocumentLanguage, EditorCore, EditorError, RenderLine,
    RenderSnapshot, RenderSpan, RenderSpanKind,
};
