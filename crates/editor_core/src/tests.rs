use crate::ffi::*;
use crate::{
    detect_agent_providers_in_path, AgentProviderId, BufferId, DocumentLanguage, EditorCore,
    EditorError, RenderSpanKind,
};
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
fn close_buffer_removes_buffer_from_core() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.close_buffer(buffer_id).expect("close buffer");

    assert!(matches!(
        core.get_text(buffer_id),
        Err(EditorError::MissingBuffer(id)) if id == buffer_id
    ));
}

#[test]
fn render_snapshot_exposes_numbered_lines_and_dirty_state() {
    let path = write_temp_file(
        "render_snapshot_exposes_numbered_lines_and_dirty_state",
        "one\ntwo\n",
    );
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open file");

    core.replace_text(buffer_id, "one\ntwo\nthree")
        .expect("replace text");

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.buffer_id, buffer_id);
    assert!(snapshot.dirty);
    assert_eq!(snapshot.cursor_line, 0);
    assert_eq!(snapshot.cursor_column, 0);
    assert_eq!(snapshot.lines.len(), 3);
    assert_eq!(snapshot.lines[0].line_number, 1);
    assert_eq!(snapshot.lines[0].text, "one");
    assert_eq!(snapshot.lines[2].line_number, 3);
    assert_eq!(snapshot.lines[2].text, "three");
    let _ = fs::remove_file(path);
}

#[test]
fn render_snapshot_tracks_cursor_line_and_column() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text_with_cursor(buffer_id, "one\ntwo\nthree", 8)
        .expect("replace text with cursor");

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.cursor_line, 2);
    assert_eq!(snapshot.cursor_column, 0);

    core.set_cursor_offset(buffer_id, 11)
        .expect("set cursor offset");

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.cursor_line, 2);
    assert_eq!(snapshot.cursor_column, 3);
}

#[test]
fn render_snapshot_exposes_markdown_highlight_spans() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text(
        buffer_id,
        "# Heading\n- item with `code`\n> quote\nA [link](https://example.com) and **bold**",
    )
    .expect("replace text");

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.lines[0].spans.len(), 1);
    assert_eq!(snapshot.lines[0].spans[0].start_column, 0);
    assert_eq!(snapshot.lines[0].spans[0].end_column, 9);
    assert_eq!(
        snapshot.lines[0].spans[0].kind,
        RenderSpanKind::MarkdownHeading
    );

    assert_eq!(
        snapshot.lines[1].spans[0].kind,
        RenderSpanKind::MarkdownListMarker
    );
    assert_eq!(
        snapshot.lines[1].spans[1].kind,
        RenderSpanKind::MarkdownInlineCode
    );

    assert_eq!(
        snapshot.lines[2].spans[0].kind,
        RenderSpanKind::MarkdownQuote
    );
    assert!(snapshot.lines[3]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::MarkdownLink));
    assert!(snapshot.lines[3]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::MarkdownEmphasis));
}

#[test]
fn agent_provider_detection_reports_available_external_clis_from_path() {
    let dir = make_temp_dir("agent_provider_detection_reports_available_external_clis_from_path");
    let codex = dir.join("codex");
    let claude = dir.join("claude");
    fs::write(&codex, "").expect("write codex stub");
    fs::write(&claude, "").expect("write claude stub");

    let providers = detect_agent_providers_in_path(Some(dir.as_os_str()));

    let codex_provider = providers
        .iter()
        .find(|provider| provider.id == AgentProviderId::Codex)
        .expect("codex provider");
    let claude_provider = providers
        .iter()
        .find(|provider| provider.id == AgentProviderId::Claude)
        .expect("claude provider");

    assert!(codex_provider.available);
    assert_eq!(
        codex_provider.executable_path.as_deref(),
        Some(codex.as_path())
    );
    assert!(claude_provider.available);
    assert_eq!(
        claude_provider.executable_path.as_deref(),
        Some(claude.as_path())
    );
    let _ = fs::remove_file(codex);
    let _ = fs::remove_file(claude);
    let _ = fs::remove_dir(dir);
}

#[test]
fn render_snapshot_detects_language_from_file_extension() {
    let cases = [
        ("md", DocumentLanguage::Markdown),
        ("markdown", DocumentLanguage::Markdown),
        ("kt", DocumentLanguage::Kotlin),
        ("kts", DocumentLanguage::Kotlin),
        ("rs", DocumentLanguage::Rust),
        ("swift", DocumentLanguage::Swift),
        ("txt", DocumentLanguage::PlainText),
    ];
    let mut paths = Vec::new();
    let mut core = EditorCore::new();

    for (extension, expected_language) in cases {
        let path = make_temp_path(
            &format!("render_snapshot_detects_language_from_file_extension_{extension}"),
            extension,
        );
        fs::write(&path, sample_text_for_language(expected_language)).expect("write temp file");
        let buffer_id = core.open_file(&path).expect("open file");

        let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

        assert_eq!(snapshot.language, expected_language);
        paths.push(path);
    }

    for path in paths {
        let _ = fs::remove_file(path);
    }
}

#[test]
fn save_file_as_reclassifies_language_for_highlighting() {
    let path = make_temp_path(
        "save_file_as_reclassifies_language_for_highlighting",
        "swift",
    );
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text(buffer_id, "func count() -> Int {\n    return 7\n}\n")
        .expect("replace text");
    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");
    assert_eq!(snapshot.language, DocumentLanguage::Markdown);
    assert!(snapshot.lines[0].spans.is_empty());

    core.save_file_as(buffer_id, &path).expect("save file as");
    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.language, DocumentLanguage::Swift);
    assert!(snapshot.lines[0]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftFunction));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftNumber));
    let _ = fs::remove_file(path);
}

#[test]
fn tree_sitter_highlight_spans_convert_byte_columns_to_character_columns() {
    let cases = [
        (
            "kt",
            DocumentLanguage::Kotlin,
            "val 한글 = 42",
            RenderSpanKind::KotlinNumber,
        ),
        (
            "rs",
            DocumentLanguage::Rust,
            "let 한글 = 42;",
            RenderSpanKind::RustNumber,
        ),
        (
            "swift",
            DocumentLanguage::Swift,
            "let 한글 = 42",
            RenderSpanKind::SwiftNumber,
        ),
    ];
    let mut paths = Vec::new();
    let mut core = EditorCore::new();

    for (extension, language, text, kind) in cases {
        let path = make_temp_path(
            &format!("tree_sitter_highlight_spans_convert_byte_columns_{extension}"),
            extension,
        );
        fs::write(&path, text).expect("write temp file");
        let buffer_id = core.open_file(&path).expect("open file");

        let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");
        let span = snapshot.lines[0]
            .spans
            .iter()
            .find(|span| span.kind == kind)
            .expect("number span");

        assert_eq!(snapshot.language, language);
        assert_eq!(span.start_column, 9);
        assert_eq!(span.end_column, 11);
        paths.push(path);
    }

    for path in paths {
        let _ = fs::remove_file(path);
    }
}

#[test]
fn render_snapshot_exposes_tree_sitter_rust_highlight_spans() {
    let path = make_temp_path(
        "render_snapshot_exposes_tree_sitter_rust_highlight_spans",
        "rs",
    );
    fs::write(
        &path,
        "#[test]\nfn greet(name: &str) -> String {\n    format!(\"hello {name}\")\n}\n",
    )
    .expect("write temp rust file");
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open rust file");

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.language, DocumentLanguage::Rust);
    assert!(snapshot.lines[0]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::RustAttribute));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::RustKeyword));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::RustFunction));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::RustType));
    assert!(snapshot.lines[2]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::RustString));

    core.replace_text(buffer_id, "fn count() -> usize {\n    42\n}\n")
        .expect("replace rust text");
    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.language, DocumentLanguage::Rust);
    assert!(snapshot.lines[0]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::RustFunction));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::RustNumber));
    let _ = fs::remove_file(path);
}

#[test]
fn render_snapshot_exposes_tree_sitter_kotlin_highlight_spans() {
    let path = make_temp_path(
        "render_snapshot_exposes_tree_sitter_kotlin_highlight_spans",
        "kt",
    );
    fs::write(
        &path,
        "@Test\nfun greet(name: String): String {\n    val count = 42\n    return \"hello $name\"\n}\n",
    )
    .expect("write temp kotlin file");
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open kotlin file");

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.language, DocumentLanguage::Kotlin);
    assert!(snapshot.lines[0]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::KotlinAnnotation));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::KotlinKeyword));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::KotlinFunction));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::KotlinType));
    assert!(snapshot.lines[2]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::KotlinNumber));
    assert!(snapshot.lines[3]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::KotlinString));

    core.replace_text(buffer_id, "fun count(): Int {\n    return 7\n}\n")
        .expect("replace kotlin text");
    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.language, DocumentLanguage::Kotlin);
    assert!(snapshot.lines[0]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::KotlinFunction));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::KotlinNumber));
    let _ = fs::remove_file(path);
}

#[test]
fn render_snapshot_exposes_tree_sitter_swift_highlight_spans() {
    let path = make_temp_path(
        "render_snapshot_exposes_tree_sitter_swift_highlight_spans",
        "swift",
    );
    fs::write(
        &path,
        "@MainActor\nfunc greet(name: String) -> String {\n    let count = 42\n    return \"hello \\(name)\"\n}\n",
    )
    .expect("write temp swift file");
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open swift file");

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.language, DocumentLanguage::Swift);
    assert!(snapshot.lines[0]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftAttribute));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftKeyword));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftFunction));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftType));
    assert!(snapshot.lines[2]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftNumber));
    assert!(snapshot.lines[3]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftString));

    core.replace_text(buffer_id, "func count() -> Int {\n    return 7\n}\n")
        .expect("replace swift text");
    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");

    assert_eq!(snapshot.language, DocumentLanguage::Swift);
    assert!(snapshot.lines[0]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftFunction));
    assert!(snapshot.lines[1]
        .spans
        .iter()
        .any(|span| span.kind == RenderSpanKind::SwiftNumber));
    let _ = fs::remove_file(path);
}

#[test]
fn markdown_preview_html_renders_current_buffer_text() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text(
        buffer_id,
        "# Heading\n\n- item with `code`\n\n> quote\n\nA [link](https://example.com) and **bold**",
    )
    .expect("replace text");

    let html = core
        .markdown_preview_html(buffer_id)
        .expect("markdown preview html");

    assert!(html.contains("<h1>Heading</h1>"));
    assert!(html.contains("<ul>"));
    assert!(html.contains("<li>item with <code>code</code></li>"));
    assert!(html.contains("<blockquote>quote</blockquote>"));
    assert!(html.contains("<a href=\"https://example.com\">link</a>"));
    assert!(html.contains("<strong>bold</strong>"));
}

#[test]
fn markdown_preview_html_renders_indented_lists_and_fenced_code_blocks() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text(
        buffer_id,
        "1. **Branch off the right base**\n   - Release: `git checkout -b release/X.Y.Z develop`\n   - Hotfix: `git checkout -b hotfix/X.Y.Z master`\n2. **Merge into `master`** with `--no-ff`:\n   ```bash\n   git checkout master && git pull\n   git merge --no-ff release/X.Y.Z\n   ```",
    )
    .expect("replace text");

    let html = core
        .markdown_preview_html(buffer_id)
        .expect("markdown preview html");

    assert!(html.contains("<ol>"));
    assert!(html.contains("<li><strong>Branch off the right base</strong></li>"));
    assert!(html.contains("<ul>"));
    assert!(html.contains("<li>Release: <code>git checkout -b release/X.Y.Z develop</code></li>"));
    assert!(html.contains("<pre><code>"));
    assert!(html.contains("git checkout master &amp;&amp; git pull"));
    assert!(html.contains("git merge --no-ff release/X.Y.Z"));
    assert!(!html.contains("```bash"));
}

#[test]
fn markdown_preview_html_escapes_untrusted_content() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text(
        buffer_id,
        "# <script>alert(1)</script>\n[bad](\" onclick=\"alert(1))",
    )
    .expect("replace text");

    let html = core
        .markdown_preview_html(buffer_id)
        .expect("markdown preview html");

    assert!(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"));
    assert!(html.contains("href=\"&quot; onclick=&quot;alert(1\""));
    assert!(!html.contains("<script>alert(1)</script>"));
}

#[test]
fn cursor_offset_must_be_utf8_boundary() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    let error = core
        .replace_text_with_cursor(buffer_id, "aé", 2)
        .expect_err("cursor boundary error");

    assert!(matches!(error, EditorError::InvalidCursorOffset(2)));
}

#[test]
fn undo_and_redo_restore_text_cursor_and_dirty_state() {
    let path = write_temp_file(
        "undo_and_redo_restore_text_cursor_and_dirty_state",
        "before",
    );
    let mut core = EditorCore::new();
    let buffer_id = core.open_file(&path).expect("open file");

    core.replace_text_with_cursor(buffer_id, "after", 5)
        .expect("replace text");
    assert!(core.is_dirty(buffer_id).expect("dirty state"));

    assert!(core.undo(buffer_id).expect("undo"));
    assert_eq!(core.get_text(buffer_id).expect("buffer text"), "before");
    assert!(!core.is_dirty(buffer_id).expect("dirty state"));

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");
    assert_eq!(snapshot.cursor_line, 0);
    assert_eq!(snapshot.cursor_column, 0);

    assert!(core.redo(buffer_id).expect("redo"));
    assert_eq!(core.get_text(buffer_id).expect("buffer text"), "after");
    assert!(core.is_dirty(buffer_id).expect("dirty state"));

    let snapshot = core.render_snapshot(buffer_id).expect("render snapshot");
    assert_eq!(snapshot.cursor_line, 0);
    assert_eq!(snapshot.cursor_column, 5);
    let _ = fs::remove_file(path);
}

#[test]
fn new_edit_after_undo_clears_redo_stack() {
    let mut core = EditorCore::new();
    let buffer_id = core.new_file();

    core.replace_text_with_cursor(buffer_id, "one", 3)
        .expect("replace text");
    core.replace_text_with_cursor(buffer_id, "two", 3)
        .expect("replace text");

    assert!(core.undo(buffer_id).expect("undo"));
    assert_eq!(core.get_text(buffer_id).expect("buffer text"), "one");

    core.replace_text_with_cursor(buffer_id, "three", 5)
        .expect("replace text");

    assert!(!core.redo(buffer_id).expect("redo"));
    assert_eq!(core.get_text(buffer_id).expect("buffer text"), "three");
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
fn ffi_render_snapshot_returns_json_payload() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text(buffer_id, "alpha\nbeta"), 1);

    let snapshot = take_ffi_string(fe_get_render_snapshot(buffer_id));

    assert!(snapshot.contains("\"buffer_id\":"));
    assert!(snapshot.contains("\"line_number\":1"));
    assert!(snapshot.contains("\"text\":\"alpha\""));
    assert!(snapshot.contains("\"line_number\":2"));
    assert!(snapshot.contains("\"text\":\"beta\""));
}

#[test]
fn ffi_render_snapshot_reports_cursor_from_replace_payload() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text_with_cursor(buffer_id, "alpha\nbeta", 8), 1);

    let snapshot = take_ffi_string(fe_get_render_snapshot(buffer_id));

    assert!(snapshot.contains("\"cursor_line\":1"));
    assert!(snapshot.contains("\"cursor_column\":2"));
}

#[test]
fn ffi_render_snapshot_includes_markdown_span_payload() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text(buffer_id, "# Heading\n`code`"), 1);

    let snapshot = take_ffi_string(fe_get_render_snapshot(buffer_id));

    assert!(snapshot.contains("\"spans\""));
    assert!(snapshot.contains("\"kind\":\"markdown_heading\""));
    assert!(snapshot.contains("\"kind\":\"markdown_inline_code\""));
}

#[test]
fn ffi_detect_agent_providers_returns_provider_payload() {
    let _guard = ffi_test_lock();

    let providers = take_ffi_string(fe_detect_agent_providers());

    assert!(providers.contains("\"id\":\"codex\""));
    assert!(providers.contains("\"id\":\"claude\""));
    assert!(providers.contains("\"id\":\"gemini\""));
    assert!(providers.contains("\"available\""));
}

#[test]
fn ffi_inspect_project_tasks_returns_android_task_payload() {
    let _guard = ffi_test_lock();
    let root = make_temp_dir("ffi_inspect_project_tasks_returns_android_task_payload");
    fs::create_dir_all(root.join("app/src/main")).expect("create android sample dirs");
    fs::write(root.join("settings.gradle.kts"), "pluginManagement {}\n").expect("write settings");
    fs::write(root.join("gradlew"), "").expect("write gradle wrapper");
    fs::write(root.join("app/build.gradle.kts"), "plugins {}\n").expect("write module gradle");
    fs::write(
        root.join("app/src/main/AndroidManifest.xml"),
        "<manifest />\n",
    )
    .expect("write manifest");
    let path = CString::new(root.to_string_lossy().as_bytes()).expect("ffi path");

    let summary = take_ffi_string(fe_inspect_project_tasks(path.as_ptr()));

    assert!(summary.contains("\"provider_id\":\"android\""));
    assert!(summary.contains("\"id\":\"android-build\""));
    assert!(summary.contains("\"id\":\"android-run\""));
    assert!(summary.contains("\"has_gradle_wrapper\":true"));
    let _ = fs::remove_dir_all(root);
}

#[test]
fn ffi_render_snapshot_includes_tree_sitter_language_and_span_payload() {
    let _guard = ffi_test_lock();
    let cases = [
        (
            "kt",
            "fun count(): Int {\n    return 7\n}\n",
            "\"language\":\"kotlin\"",
            "\"kind\":\"kotlin_function\"",
        ),
        (
            "rs",
            "fn count() -> usize {\n    7\n}\n",
            "\"language\":\"rust\"",
            "\"kind\":\"rust_function\"",
        ),
        (
            "swift",
            "func count() -> Int {\n    return 7\n}\n",
            "\"language\":\"swift\"",
            "\"kind\":\"swift_function\"",
        ),
    ];
    let mut paths = Vec::new();

    for (extension, text, language_payload, span_payload) in cases {
        let path = make_temp_path(
            &format!("ffi_render_snapshot_includes_tree_sitter_payload_{extension}"),
            extension,
        );
        fs::write(&path, text).expect("write temp file");
        let buffer_id = ffi_open_file(&path);

        let snapshot = take_ffi_string(fe_get_render_snapshot(buffer_id));

        assert!(snapshot.contains(language_payload));
        assert!(snapshot.contains(span_payload));
        paths.push(path);
    }

    for path in paths {
        let _ = fs::remove_file(path);
    }
}

#[test]
fn ffi_markdown_preview_html_uses_unsaved_buffer_text() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text(buffer_id, "# Draft"), 1);

    let html = take_ffi_string(fe_get_markdown_preview_html(buffer_id));

    assert!(html.contains("<h1>Draft</h1>"));
}

#[test]
fn ffi_set_cursor_offset_updates_render_snapshot() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text(buffer_id, "alpha\nbeta"), 1);
    assert_eq!(fe_set_cursor_offset(buffer_id, 10), 1);

    let snapshot = take_ffi_string(fe_get_render_snapshot(buffer_id));

    assert!(snapshot.contains("\"cursor_line\":1"));
    assert!(snapshot.contains("\"cursor_column\":4"));
}

#[test]
fn ffi_undo_and_redo_restore_text_and_cursor() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(ffi_replace_text_with_cursor(buffer_id, "alpha", 5), 1);
    assert_eq!(ffi_replace_text_with_cursor(buffer_id, "alpha\nbeta", 8), 1);

    assert_eq!(fe_undo(buffer_id), 1);
    assert_eq!(take_ffi_string(fe_get_text(buffer_id)), "alpha");
    let snapshot = take_ffi_string(fe_get_render_snapshot(buffer_id));
    assert!(snapshot.contains("\"cursor_line\":0"));
    assert!(snapshot.contains("\"cursor_column\":5"));

    assert_eq!(fe_redo(buffer_id), 1);
    assert_eq!(take_ffi_string(fe_get_text(buffer_id)), "alpha\nbeta");
    let snapshot = take_ffi_string(fe_get_render_snapshot(buffer_id));
    assert!(snapshot.contains("\"cursor_line\":1"));
    assert!(snapshot.contains("\"cursor_column\":2"));
}

#[test]
fn ffi_undo_and_redo_report_noop_without_error() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(fe_undo(buffer_id), 0);
    assert_eq!(take_ffi_string(fe_last_error()), "");
    assert_eq!(fe_redo(buffer_id), 0);
    assert_eq!(take_ffi_string(fe_last_error()), "");
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
fn ffi_close_buffer_releases_buffer() {
    let _guard = ffi_test_lock();
    let buffer_id = fe_new_file();

    assert_ne!(buffer_id, 0);
    assert_eq!(fe_close_buffer(buffer_id), 1);
    assert_eq!(fe_is_dirty(buffer_id), -1);
    assert_eq!(
        take_ffi_string(fe_last_error()),
        format!("missing buffer {buffer_id}")
    );
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

fn ffi_replace_text_with_cursor(buffer_id: BufferId, text: &str, cursor_offset: usize) -> i32 {
    fe_replace_text_with_cursor(buffer_id, text.as_ptr(), text.len(), cursor_offset)
}

fn ffi_save_file_as(buffer_id: BufferId, path: &Path) -> i32 {
    let path = CString::new(path.to_string_lossy().as_bytes()).expect("ffi path");
    fe_save_file_as(buffer_id, path.as_ptr())
}

fn sample_text_for_language(language: DocumentLanguage) -> &'static str {
    match language {
        DocumentLanguage::Markdown => "# Heading",
        DocumentLanguage::Kotlin => "fun count(): Int {\n    return 7\n}\n",
        DocumentLanguage::Rust => "fn count() -> usize {\n    7\n}\n",
        DocumentLanguage::Swift => "func count() -> Int {\n    return 7\n}\n",
        DocumentLanguage::PlainText => "plain text",
    }
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
