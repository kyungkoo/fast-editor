import AppKit
import CoreImage
import FastEditorTextEditing
import MetalKit
import SwiftUI

struct MetalTextEditor: NSViewRepresentable {
    @Binding var text: String
    var snapshot: EditorRenderSnapshot
    var isEditable: Bool
    var focusRevision: Int
    var onTextChange: (String, Int) -> Void
    var onCursorMove: (Int) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void

    func makeNSView(context: Context) -> MetalTextRenderView {
        MetalTextRenderView()
    }

    func updateNSView(_ view: MetalTextRenderView, context: Context) {
        view.text = text
        view.snapshot = snapshot
        view.isEditable = isEditable
        view.onTextChange = onTextChange
        view.onCursorMove = onCursorMove
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.focus(revision: focusRevision)
    }
}

final class MetalTextRenderView: MTKView, @preconcurrency NSTextInputClient {
    var text = "" {
        didSet {
            guard oldValue != text else {
                return
            }

            cursorOffset = clampCursorOffset(cursorOffset)
            selectionAnchorOffset = selectionAnchorOffset.map(clampCursorOffset)
            recalculateContentMetrics()
            clampScrollOffset()
            setNeedsDisplay(bounds)
        }
    }

    var snapshot = EditorRenderSnapshot.empty {
        didSet {
            guard oldValue != snapshot else {
                return
            }

            cursorOffset = utf8Offset(line: snapshot.cursorLine, column: snapshot.cursorColumn)
            recalculateContentMetrics()
            clampScrollOffset()
            ensureCursorVisible()
            setNeedsDisplay(bounds)
        }
    }

    var isEditable = false {
        didSet {
            guard oldValue != isEditable else {
                return
            }

            setNeedsDisplay(bounds)
        }
    }

    var onTextChange: ((String, Int) -> Void)?
    var onCursorMove: ((Int) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?

    private let commandQueue: MTLCommandQueue
    private let imageContext: CIContext
    private let style = MetalTextEditorStyle()
    private var viewport = MetalTextViewport()
    private var cursorOffset = 0
    private var lastFocusedRevision = 0
    private var markedRangeUTF16 = NSRange(location: NSNotFound, length: 0)
    private var selectionAnchorOffset: Int?
    private var mouseSelectionAnchorOffset: Int?
    private var preferredColumn: Int?

    private var scrollOffset: CGPoint {
        get {
            viewport.scrollOffset
        }
        set {
            viewport.scrollOffset = newValue
        }
    }

    private var gutterWidth: CGFloat {
        style.gutterWidth
    }

    private var horizontalPadding: CGFloat {
        style.horizontalPadding
    }

    private var verticalPadding: CGFloat {
        style.verticalPadding
    }

    private var caretWidth: CGFloat {
        style.caretWidth
    }

    private var lineHeight: CGFloat {
        style.lineHeight
    }

    init() {
        guard let metalDevice = MTLCreateSystemDefaultDevice(),
              let queue = metalDevice.makeCommandQueue()
        else {
            preconditionFailure("Fast Editor requires a Metal-capable device.")
        }

        commandQueue = queue
        imageContext = CIContext(mtlDevice: metalDevice)

        super.init(frame: .zero, device: metalDevice)

        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        recalculateContentMetrics()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateDrawableSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
        clampScrollOffset()
        setNeedsDisplay(bounds)
    }

    override func scrollWheel(with event: NSEvent) {
        scrollOffset.x -= event.scrollingDeltaX
        scrollOffset.y -= event.scrollingDeltaY
        clampScrollOffset()
        setNeedsDisplay(bounds)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditable else {
            return
        }

        window?.makeFirstResponder(self)
        inputContext?.discardMarkedText()

        let point = convert(event.locationInWindow, from: nil)
        let clickedOffset = cursorOffset(at: point)

        if event.modifierFlags.contains(.shift) {
            selectionAnchorOffset = selectionAnchorOffset ?? cursorOffset
        } else {
            selectionAnchorOffset = nil
        }

        mouseSelectionAnchorOffset = selectionAnchorOffset ?? clickedOffset
        cursorOffset = clickedOffset
        preferredColumn = nil
        publishCursorMove()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditable else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        selectionAnchorOffset = mouseSelectionAnchorOffset ?? cursorOffset
        cursorOffset = cursorOffset(at: point)
        preferredColumn = nil
        publishCursorMove()
    }

    override func mouseUp(with event: NSEvent) {
        mouseSelectionAnchorOffset = nil
    }

    override func keyDown(with event: NSEvent) {
        guard isEditable else {
            super.keyDown(with: event)
            return
        }

        if handleCommandShortcut(event) {
            return
        }

        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }

        interpretKeyEvents([event])
    }

    override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    override func doCommand(by selector: Selector) {
        guard isEditable else {
            super.doCommand(by: selector)
            return
        }

        switch selector {
        case #selector(insertNewline(_:)):
            inputContext?.discardMarkedText()
            insertMarkdownNewline()
        case #selector(deleteBackward(_:)):
            inputContext?.discardMarkedText()
            replaceCharactersBeforeCursor(1, afterCursor: 0, with: "")
        case #selector(deleteForward(_:)):
            inputContext?.discardMarkedText()
            replaceCharactersBeforeCursor(0, afterCursor: 1, with: "")
        case #selector(moveLeft(_:)):
            inputContext?.discardMarkedText()
            moveCursorHorizontally(-1, extendingSelection: false)
        case #selector(moveRight(_:)):
            inputContext?.discardMarkedText()
            moveCursorHorizontally(1, extendingSelection: false)
        case #selector(moveUp(_:)):
            inputContext?.discardMarkedText()
            moveCursorVertically(-1, extendingSelection: false)
        case #selector(moveDown(_:)):
            inputContext?.discardMarkedText()
            moveCursorVertically(1, extendingSelection: false)
        case #selector(moveLeftAndModifySelection(_:)):
            inputContext?.discardMarkedText()
            moveCursorHorizontally(-1, extendingSelection: true)
        case #selector(moveRightAndModifySelection(_:)):
            inputContext?.discardMarkedText()
            moveCursorHorizontally(1, extendingSelection: true)
        case #selector(moveUpAndModifySelection(_:)):
            inputContext?.discardMarkedText()
            moveCursorVertically(-1, extendingSelection: true)
        case #selector(moveDownAndModifySelection(_:)):
            inputContext?.discardMarkedText()
            moveCursorVertically(1, extendingSelection: true)
        case #selector(moveToBeginningOfLine(_:)):
            inputContext?.discardMarkedText()
            moveCursorToLineBoundary(.beginning, extendingSelection: false)
        case #selector(moveToEndOfLine(_:)):
            inputContext?.discardMarkedText()
            moveCursorToLineBoundary(.end, extendingSelection: false)
        case #selector(moveToBeginningOfLineAndModifySelection(_:)):
            inputContext?.discardMarkedText()
            moveCursorToLineBoundary(.beginning, extendingSelection: true)
        case #selector(moveToEndOfLineAndModifySelection(_:)):
            inputContext?.discardMarkedText()
            moveCursorToLineBoundary(.end, extendingSelection: true)
        default:
            super.doCommand(by: selector)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        autoreleasepool {
            renderFrame()
        }
    }

    func focus(revision: Int) {
        guard isEditable, lastFocusedRevision != revision else {
            return
        }

        lastFocusedRevision = revision
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
    }

    func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard isEditable, let insertedText = plainText(from: insertString) else {
            return
        }

        if insertedText == "\n", replacementRange.location == NSNotFound {
            insertMarkdownNewline()
            return
        }

        let targetRange = effectiveReplacementRange(replacementRange)
        guard replaceUTF16Range(targetRange, with: insertedText) else {
            return
        }

        markedRangeUTF16 = NSRange(location: NSNotFound, length: 0)
        selectionAnchorOffset = nil
        cursorOffset = utf8Offset(atUTF16Location: targetRange.location + insertedText.utf16.count)
        preferredColumn = nil
        publishTextChange()
    }

    func setMarkedText(_ insertString: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard isEditable, let markedText = plainText(from: insertString) else {
            return
        }

        let targetRange = effectiveReplacementRange(replacementRange)
        guard replaceUTF16Range(targetRange, with: markedText) else {
            return
        }

        if markedText.isEmpty {
            markedRangeUTF16 = NSRange(location: NSNotFound, length: 0)
        } else {
            markedRangeUTF16 = NSRange(location: targetRange.location, length: markedText.utf16.count)
        }

        selectionAnchorOffset = nil
        let selectedLocation = min(max(0, selectedRange.location + selectedRange.length), markedText.utf16.count)
        cursorOffset = utf8Offset(atUTF16Location: targetRange.location + selectedLocation)
        preferredColumn = nil
        publishTextChange()
    }

    func unmarkText() {
        markedRangeUTF16 = NSRange(location: NSNotFound, length: 0)
        setNeedsDisplay(bounds)
    }

    func selectedRange() -> NSRange {
        if let selectedRange = selectedUTF8Range {
            let location = utf16Offset(forUTF8Offset: selectedRange.lowerBound)
            let end = utf16Offset(forUTF8Offset: selectedRange.upperBound)
            return NSRange(location: location, length: end - location)
        }

        return NSRange(location: utf16Offset(forUTF8Offset: cursorOffset), length: 0)
    }

    func markedRange() -> NSRange {
        markedRangeUTF16
    }

    func hasMarkedText() -> Bool {
        markedRangeUTF16.location != NSNotFound
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        guard let validRange = validUTF16Range(range) else {
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
            return nil
        }

        actualRange?.pointee = validRange
        let substring = (text as NSString).substring(with: validRange)
        return NSAttributedString(string: substring, attributes: [.font: style.font])
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.font, .foregroundColor, .underlineStyle]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let validRange = validUTF16Range(range) ?? selectedRange()
        actualRange?.pointee = validRange

        let cursorUTF8Offset = utf8Offset(atUTF16Location: validRange.location)
        let position = cursorPosition(forUTF8Offset: cursorUTF8Offset)
        let line = snapshot.lines[safe: position.line]
        let caretX = gutterWidth + horizontalPadding + layoutMetrics.prefixWidth(column: position.column, in: line) - scrollOffset.x
        let caretY = verticalPadding + CGFloat(position.line) * lineHeight - scrollOffset.y
        let localRect = NSRect(x: caretX, y: caretY, width: caretWidth, height: lineHeight)
        let windowRect = convert(localRect, to: nil)

        return window?.convertToScreen(windowRect) ?? windowRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        guard let window else {
            return utf16Offset(forUTF8Offset: cursorOffset)
        }

        let screenRect = NSRect(origin: point, size: .zero)
        let windowPoint = window.convertFromScreen(screenRect).origin
        let localPoint = convert(windowPoint, from: nil)
        let lineIndex = lineIndex(at: localPoint.y)
        let line = snapshot.lines[safe: lineIndex]
        let textX = localPoint.x - gutterWidth - horizontalPadding + scrollOffset.x
        let column = layoutMetrics.column(in: line, closestTo: textX)

        return utf16Offset(forUTF8Offset: utf8Offset(line: lineIndex, column: column))
    }

    private func clearTransientEditingState() {
        selectionAnchorOffset = nil
        mouseSelectionAnchorOffset = nil
        markedRangeUTF16 = NSRange(location: NSNotFound, length: 0)
        preferredColumn = nil
    }

    private func renderFrame() {
        guard bounds.width > 0,
              bounds.height > 0,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let image = makeFrameImage()
        else {
            return
        }

        let destination = CIRenderDestination(
            width: Int(drawableSize.width),
            height: Int(drawableSize.height),
            pixelFormat: colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { drawable.texture }
        )

        do {
            try imageContext.startTask(toRender: image, to: destination)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } catch {
            commandBuffer.commit()
        }
    }

    private func makeFrameImage() -> CIImage? {
        let scale = backingScaleFactor
        let pixelWidth = max(1, Int(bounds.width * scale))
        let pixelHeight = max(1, Int(bounds.height * scale))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        drawBackground(in: context)
        drawSelectionHighlights(in: context)
        drawVisibleText(in: context)
        drawInsertionPointIfNeeded(in: context)

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else {
            return nil
        }

        return CIImage(cgImage: cgImage)
            .oriented(.downMirrored)
    }

    private func drawBackground(in context: CGContext) {
        context.setFillColor(NSColor.textBackgroundColor.cgColor)
        context.fill(CGRect(origin: .zero, size: bounds.size))

        context.setFillColor(NSColor.controlBackgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height))

        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: gutterWidth - 0.5, y: 0))
        context.addLine(to: CGPoint(x: gutterWidth - 0.5, y: bounds.height))
        context.strokePath()
    }

    private func drawVisibleText(in context: CGContext) {
        for lineIndex in visibleLineRange {
            let line = snapshot.lines[lineIndex]
            let baselineY = style.verticalPadding + CGFloat(lineIndex) * style.lineHeight - scrollOffset.y
            let lineNumber = "\(line.lineNumber)" as NSString
            let lineNumberSize = lineNumber.size(withAttributes: style.lineNumberAttributes)
            let lineNumberPoint = CGPoint(
                x: style.gutterWidth - style.horizontalPadding - lineNumberSize.width,
                y: baselineY
            )

            lineNumber.draw(at: lineNumberPoint, withAttributes: style.lineNumberAttributes)

            let textPoint = CGPoint(
                x: style.gutterWidth + style.horizontalPadding - scrollOffset.x,
                y: baselineY
            )
            context.saveGState()
            context.clip(to: textClipRect)
            drawText(line, at: textPoint)
            context.restoreGState()
        }
    }

    private func drawText(
        _ line: EditorRenderLine,
        at point: CGPoint
    ) {
        let characters = Array(line.text)
        var currentColumn = 0
        var currentX = CGFloat.zero

        for span in line.spans.sorted(by: { $0.startColumn < $1.startColumn }) {
            let startColumn = min(max(span.startColumn, currentColumn), characters.count)
            let endColumn = min(max(span.endColumn, startColumn), characters.count)

            if currentColumn < startColumn {
                currentX += drawTextSegment(
                    characters[currentColumn..<startColumn],
                    at: CGPoint(x: point.x + currentX, y: point.y),
                    attributes: textAttributes
                )
            }

            currentX += drawTextSegment(
                characters[startColumn..<endColumn],
                at: CGPoint(x: point.x + currentX, y: point.y),
                attributes: textAttributes(for: span.kind, defaultAttributes: textAttributes)
            )
            currentColumn = endColumn
        }

        if currentColumn < characters.count {
            drawTextSegment(
                characters[currentColumn..<characters.count],
                at: CGPoint(x: point.x + currentX, y: point.y),
                attributes: textAttributes
            )
        }
    }

    @discardableResult
    private func drawTextSegment(
        _ segment: ArraySlice<Character>,
        at point: CGPoint,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        guard !segment.isEmpty else {
            return 0
        }

        let segmentText = String(segment)
        (segmentText as NSString).draw(at: point, withAttributes: attributes)
        return layoutMetrics.width(of: segmentText, attributes: attributes)
    }

    private func textAttributes(
        for kind: EditorRenderSpanKind,
        defaultAttributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        style.textAttributes(for: kind, defaultAttributes: defaultAttributes)
    }

    private func drawSelectionHighlights(in context: CGContext) {
        guard let selectedRange = selectedUTF8Range else {
            return
        }

        context.saveGState()
        context.clip(to: textClipRect)
        context.setFillColor(NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45).cgColor)

        for lineIndex in visibleLineRange {
            let line = snapshot.lines[lineIndex]
            let lineStart = utf8Offset(line: lineIndex, column: 0)
            let lineTextEnd = utf8Offset(line: lineIndex, column: line.text.count)
            let lineSelectionStart = max(selectedRange.lowerBound, lineStart)
            let lineSelectionEnd = min(selectedRange.upperBound, lineTextEnd)
            let selectsLineBreak = selectedRange.upperBound > lineTextEnd
                && selectedRange.lowerBound <= lineTextEnd
                && lineIndex < snapshot.lines.count - 1

            guard lineSelectionStart < lineSelectionEnd || selectsLineBreak else {
                continue
            }

            let startColumn = cursorPosition(forUTF8Offset: lineSelectionStart).column
            let endColumn = cursorPosition(forUTF8Offset: lineSelectionEnd).column
            let startX = gutterWidth + horizontalPadding + layoutMetrics.prefixWidth(column: startColumn, in: line) - scrollOffset.x
            var highlightWidth = layoutMetrics.prefixWidth(column: endColumn, in: line)
                - layoutMetrics.prefixWidth(column: startColumn, in: line)

            if selectsLineBreak {
                highlightWidth = max(highlightWidth + layoutMetrics.width(of: " "), layoutMetrics.width(of: " "))
            }

            let highlightY = verticalPadding + CGFloat(lineIndex) * lineHeight - scrollOffset.y
            context.fill(CGRect(
                x: startX,
                y: highlightY,
                width: max(caretWidth, highlightWidth),
                height: lineHeight
            ))
        }

        context.restoreGState()
    }


    private func drawInsertionPointIfNeeded(in context: CGContext) {
        guard isEditable, !snapshot.lines.isEmpty else {
            return
        }

        let caretY = verticalPadding + CGFloat(snapshot.cursorLine) * lineHeight - scrollOffset.y
        guard caretY + lineHeight >= 0, caretY <= bounds.height else {
            return
        }

        let caretX = gutterWidth + horizontalPadding + cursorX(for: snapshot) - scrollOffset.x
        context.saveGState()
        context.clip(to: textClipRect)
        context.setFillColor(NSColor.controlAccentColor.cgColor)
        context.fill(CGRect(
            x: caretX,
            y: caretY + 1,
            width: caretWidth,
            height: lineHeight - 2
        ))
        context.restoreGState()
    }

    private func recalculateContentMetrics() {
        viewport.recalculateContentSize(
            snapshot: snapshot,
            layoutMetrics: layoutMetrics,
            style: style
        )
    }

    private func clampScrollOffset() {
        viewport.clamp(to: bounds)
    }

    private func updateDrawableSize() {
        let scale = backingScaleFactor
        drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    private func insertMarkdownNewline() {
        let result = TextEditingPrimitives.replacingMarkdownNewline(
            in: text,
            cursorUTF8Offset: cursorOffset,
            selectedRange: selectedUTF8Range
        )
        text = result.text
        cursorOffset = result.cursorUTF8Offset
        selectionAnchorOffset = nil
        markedRangeUTF16 = NSRange(location: NSNotFound, length: 0)
        preferredColumn = nil
        publishTextChange()
    }

    private func replaceCharactersBeforeCursor(
        _ charactersBeforeCursor: Int,
        afterCursor charactersAfterCursor: Int,
        with replacement: String
    ) {
        if let selectedRange = selectedUTF8Range {
            replaceUTF8Range(selectedRange, with: replacement)
            return
        }

        let cursorIndex = stringIndex(atUTF8Offset: cursorOffset)
        var lowerBound = cursorIndex
        var upperBound = cursorIndex

        for _ in 0..<charactersBeforeCursor where lowerBound > text.startIndex {
            lowerBound = text.index(before: lowerBound)
        }

        for _ in 0..<charactersAfterCursor where upperBound < text.endIndex {
            upperBound = text.index(after: upperBound)
        }

        guard lowerBound != upperBound || !replacement.isEmpty else {
            return
        }

        text.replaceSubrange(lowerBound..<upperBound, with: replacement)
        cursorOffset = utf8Offset(of: lowerBound) + replacement.utf8.count
        selectionAnchorOffset = nil
        preferredColumn = nil
        publishTextChange()
    }

    private func moveCursorHorizontally(_ direction: Int, extendingSelection: Bool) {
        guard direction != 0 else {
            return
        }

        let existingSelection = selectedUTF8Range
        if !extendingSelection, let selectedRange = existingSelection {
            cursorOffset = direction < 0 ? selectedRange.lowerBound : selectedRange.upperBound
            selectionAnchorOffset = nil
            preferredColumn = nil
            publishCursorMove()
            return
        }

        updateSelectionAnchor(extendingSelection: extendingSelection)

        let index = stringIndex(atUTF8Offset: cursorOffset)
        if direction < 0, index > text.startIndex {
            cursorOffset = utf8Offset(of: text.index(before: index))
        } else if direction > 0, index < text.endIndex {
            cursorOffset = utf8Offset(of: text.index(after: index))
        }

        preferredColumn = nil
        publishCursorMove()
    }

    private func moveCursorVertically(_ direction: Int, extendingSelection: Bool) {
        updateSelectionAnchor(extendingSelection: extendingSelection)

        let position = cursorPosition(forUTF8Offset: cursorOffset)
        let targetLine = min(max(0, position.line + direction), max(snapshot.lines.count - 1, 0))
        let targetColumn = preferredColumn ?? position.column

        preferredColumn = targetColumn
        cursorOffset = utf8Offset(line: targetLine, column: targetColumn)
        publishCursorMove()
    }

    private enum LineBoundary {
        case beginning
        case end
    }

    private func moveCursorToLineBoundary(_ boundary: LineBoundary, extendingSelection: Bool) {
        updateSelectionAnchor(extendingSelection: extendingSelection)

        let position = cursorPosition(forUTF8Offset: cursorOffset)
        let lineText = snapshot.lines[safe: position.line]?.text ?? ""

        switch boundary {
        case .beginning:
            cursorOffset = utf8Offset(line: position.line, column: 0)
        case .end:
            cursorOffset = utf8Offset(line: position.line, column: lineText.count)
        }

        preferredColumn = nil
        publishCursorMove()
    }

    private func updateSelectionAnchor(extendingSelection: Bool) {
        if extendingSelection {
            selectionAnchorOffset = selectionAnchorOffset ?? cursorOffset
        } else {
            selectionAnchorOffset = nil
        }
    }

    private func publishTextChange() {
        cursorOffset = clampCursorOffset(cursorOffset)
        selectionAnchorOffset = selectionAnchorOffset.map(clampCursorOffset)
        ensureCursorVisible()
        onTextChange?(text, cursorOffset)
        setNeedsDisplay(bounds)
    }

    private func publishCursorMove() {
        cursorOffset = clampCursorOffset(cursorOffset)
        selectionAnchorOffset = selectionAnchorOffset.map(clampCursorOffset)
        ensureCursorVisible()
        onCursorMove?(cursorOffset)
        setNeedsDisplay(bounds)
    }

    private func ensureCursorVisible() {
        let position = cursorPosition(forUTF8Offset: cursorOffset)
        let line = snapshot.lines[safe: position.line]
        let caretX = gutterWidth + horizontalPadding + layoutMetrics.prefixWidth(column: position.column, in: line)
        let caretY = verticalPadding + CGFloat(position.line) * lineHeight
        let visibleMinX = scrollOffset.x
        let visibleMaxX = scrollOffset.x + max(0, bounds.width - gutterWidth - horizontalPadding)

        if caretX < gutterWidth + horizontalPadding + visibleMinX {
            scrollOffset.x = max(0, caretX - gutterWidth - horizontalPadding)
        } else if caretX + caretWidth > gutterWidth + visibleMaxX {
            scrollOffset.x = caretX + caretWidth - gutterWidth - max(0, bounds.width - gutterWidth - horizontalPadding)
        }

        if caretY < scrollOffset.y {
            scrollOffset.y = caretY
        } else if caretY + lineHeight > scrollOffset.y + bounds.height {
            scrollOffset.y = caretY + lineHeight - bounds.height
        }

        clampScrollOffset()
    }

    private func plainText(from insertString: Any) -> String? {
        MetalTextInputDecoder.plainText(from: insertString)
    }

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let command = event.charactersIgnoringModifiers?.lowercased()
        else {
            return false
        }

        switch command {
        case "a":
            inputContext?.discardMarkedText()
            selectAll()
            return true
        case "c":
            inputContext?.discardMarkedText()
            copySelection()
            return true
        case "x":
            inputContext?.discardMarkedText()
            cutSelection()
            return true
        case "v":
            inputContext?.discardMarkedText()
            pasteFromClipboard()
            return true
        case "z":
            inputContext?.discardMarkedText()
            clearTransientEditingState()
            if event.modifierFlags.contains(.shift) {
                onRedo?()
            } else {
                onUndo?()
            }
            return true
        default:
            return false
        }
    }

    private func selectAll() {
        selectionAnchorOffset = 0
        cursorOffset = text.utf8.count
        preferredColumn = nil
        publishCursorMove()
    }

    private func copySelection() {
        guard let selectedText else {
            return
        }

        MetalTextClipboard.copy(selectedText)
    }

    private func cutSelection() {
        guard let selectedRange = selectedUTF8Range, let selectedText else {
            return
        }

        MetalTextClipboard.copy(selectedText)
        replaceUTF8Range(selectedRange, with: "")
    }

    private func pasteFromClipboard() {
        guard let pastedText = MetalTextClipboard.readString(), !pastedText.isEmpty else {
            return
        }

        if let selectedRange = selectedUTF8Range {
            replaceUTF8Range(selectedRange, with: pastedText)
        } else {
            replaceCharactersBeforeCursor(0, afterCursor: 0, with: pastedText)
        }
    }

    private func effectiveReplacementRange(_ replacementRange: NSRange) -> NSRange {
        if let validRange = validUTF16Range(replacementRange) {
            return validRange
        }

        if hasMarkedText(), let validMarkedRange = validUTF16Range(markedRangeUTF16) {
            return validMarkedRange
        }

        if let selectedRange = selectedUTF8Range {
            let location = utf16Offset(forUTF8Offset: selectedRange.lowerBound)
            let end = utf16Offset(forUTF8Offset: selectedRange.upperBound)
            return NSRange(location: location, length: end - location)
        }

        return NSRange(location: utf16Offset(forUTF8Offset: cursorOffset), length: 0)
    }

    private func validUTF16Range(_ range: NSRange) -> NSRange? {
        guard range.location != NSNotFound else {
            return nil
        }

        let textLength = (text as NSString).length
        guard range.location >= 0,
              range.length >= 0,
              range.location <= textLength,
              range.location + range.length <= textLength
        else {
            return nil
        }

        return range
    }

    private func replaceUTF16Range(_ range: NSRange, with replacement: String) -> Bool {
        guard let validRange = validUTF16Range(range) else {
            return false
        }

        text = (text as NSString).replacingCharacters(in: validRange, with: replacement)
        return true
    }

    private func replaceUTF8Range(_ range: Range<Int>, with replacement: String) {
        let result = TextEditingPrimitives.replacingUTF8Range(range, in: text, with: replacement)
        text = result.text
        cursorOffset = result.cursorUTF8Offset
        selectionAnchorOffset = nil
        markedRangeUTF16 = NSRange(location: NSNotFound, length: 0)
        preferredColumn = nil
        publishTextChange()
    }

    private func lineIndex(at y: CGFloat) -> Int {
        let rawLine = Int(floor((y + scrollOffset.y - verticalPadding) / lineHeight))
        return min(max(0, rawLine), max(snapshot.lines.count - 1, 0))
    }

    private func cursorOffset(at point: CGPoint) -> Int {
        let lineIndex = lineIndex(at: point.y)
        let line = snapshot.lines[safe: lineIndex]
        let textX = point.x - gutterWidth - horizontalPadding + scrollOffset.x
        let column = layoutMetrics.column(in: line, closestTo: textX)

        return utf8Offset(line: lineIndex, column: column)
    }

    private func cursorX(for snapshot: EditorRenderSnapshot) -> CGFloat {
        layoutMetrics.prefixWidth(
            column: snapshot.cursorColumn,
            in: snapshot.lines[safe: snapshot.cursorLine]
        )
    }

    private func stringIndex(atUTF8Offset offset: Int) -> String.Index {
        TextEditingPrimitives.stringIndex(in: text, atUTF8Offset: offset)
    }

    private func utf8Offset(of index: String.Index) -> Int {
        text[..<index].utf8.count
    }

    private func utf8Offset(atUTF16Location location: Int) -> Int {
        TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: location)
    }

    private func utf16Offset(forUTF8Offset offset: Int) -> Int {
        TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: offset)
    }

    private func utf8Offset(line targetLine: Int, column targetColumn: Int) -> Int {
        TextEditingPrimitives.utf8Offset(in: text, line: targetLine, column: targetColumn)
    }

    private func cursorPosition(forUTF8Offset offset: Int) -> (line: Int, column: Int) {
        TextEditingPrimitives.cursorPosition(in: text, forUTF8Offset: offset)
    }

    private func clampCursorOffset(_ offset: Int) -> Int {
        TextEditingPrimitives.clampUTF8Offset(offset, in: text)
    }

    private var selectedUTF8Range: Range<Int>? {
        TextEditingPrimitives.selectedUTF8Range(
            anchor: selectionAnchorOffset,
            cursor: cursorOffset,
            in: text
        )
    }

    private var selectedText: String? {
        guard let selectedRange = selectedUTF8Range else {
            return nil
        }

        return TextEditingPrimitives.substring(in: text, utf8Range: selectedRange)
    }

    private var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private var textClipRect: CGRect {
        CGRect(
            x: gutterWidth,
            y: 0,
            width: max(0, bounds.width - gutterWidth),
            height: bounds.height
        )
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        style.textAttributes
    }

    private var layoutMetrics: MetalTextLayoutMetrics {
        MetalTextLayoutMetrics(
            defaultAttributes: textAttributes,
            attributesForSpanKind: textAttributes(for:defaultAttributes:)
        )
    }

    private var visibleLineRange: Range<Int> {
        viewport.visibleLineRange(
            lineHeight: lineHeight,
            lineCount: snapshot.lines.count,
            viewportHeight: bounds.height
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
