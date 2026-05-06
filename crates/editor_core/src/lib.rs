mod core;
mod ffi;

#[cfg(test)]
mod tests;

pub use core::{
    BufferId, BufferSnapshot, EditorCore, EditorError, RenderLine, RenderSnapshot, RenderSpan,
    RenderSpanKind,
};
