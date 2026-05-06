import AppKit
import CoreImage
import MetalKit
import SwiftUI

struct MetalTextEditor: NSViewRepresentable {
    var snapshot: EditorRenderSnapshot
    var showsInsertionPoint: Bool

    func makeNSView(context: Context) -> MetalTextRenderView {
        MetalTextRenderView()
    }

    func updateNSView(_ view: MetalTextRenderView, context: Context) {
        view.snapshot = snapshot
        view.showsInsertionPoint = showsInsertionPoint
    }
}

final class MetalTextRenderView: MTKView {
    var snapshot = EditorRenderSnapshot.empty {
        didSet {
            guard oldValue != snapshot else {
                return
            }

            recalculateContentMetrics()
            clampScrollOffset()
            setNeedsDisplay(bounds)
        }
    }

    var showsInsertionPoint = false {
        didSet {
            guard oldValue != showsInsertionPoint else {
                return
            }

            setNeedsDisplay(bounds)
        }
    }

    private let commandQueue: MTLCommandQueue
    private let imageContext: CIContext
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private var scrollOffset = CGPoint.zero
    private var contentSize = CGSize.zero

    private let gutterWidth: CGFloat = 56
    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 10
    private let caretWidth: CGFloat = 1.5

    private lazy var lineHeight: CGFloat = {
        ceil(font.ascender - font.descender + font.leading + 5)
    }()

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

    override func draw(_ dirtyRect: NSRect) {
        autoreleasepool {
            renderFrame()
        }
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
        let firstLine = max(0, Int(scrollOffset.y / lineHeight))
        let visibleLineCount = Int(ceil(bounds.height / lineHeight)) + 2
        let endLine = min(snapshot.lines.count, firstLine + visibleLineCount)

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
        let lineNumberAttributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        for lineIndex in firstLine..<endLine {
            let line = snapshot.lines[lineIndex]
            let baselineY = verticalPadding + CGFloat(lineIndex) * lineHeight - scrollOffset.y
            let lineNumber = "\(line.lineNumber)" as NSString
            let lineNumberSize = lineNumber.size(withAttributes: lineNumberAttributes)
            let lineNumberPoint = CGPoint(
                x: gutterWidth - horizontalPadding - lineNumberSize.width,
                y: baselineY
            )

            lineNumber.draw(at: lineNumberPoint, withAttributes: lineNumberAttributes)

            let textPoint = CGPoint(
                x: gutterWidth + horizontalPadding - scrollOffset.x,
                y: baselineY
            )
            context.saveGState()
            context.clip(to: textClipRect)
            (line.text as NSString).draw(at: textPoint, withAttributes: textAttributes)
            context.restoreGState()
        }
    }

    private func drawInsertionPointIfNeeded(in context: CGContext) {
        guard showsInsertionPoint, !snapshot.lines.isEmpty else {
            return
        }

        let caretY = verticalPadding - scrollOffset.y
        guard caretY + lineHeight >= 0, caretY <= bounds.height else {
            return
        }

        context.saveGState()
        context.clip(to: textClipRect)
        context.setFillColor(NSColor.controlAccentColor.cgColor)
        context.fill(CGRect(
            x: gutterWidth + horizontalPadding - scrollOffset.x,
            y: caretY + 1,
            width: caretWidth,
            height: lineHeight - 2
        ))
        context.restoreGState()
    }

    private func recalculateContentMetrics() {
        let textAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let longestLineWidth = snapshot.lines.reduce(CGFloat.zero) { width, line in
            max(width, (line.text as NSString).size(withAttributes: textAttributes).width)
        }

        contentSize = CGSize(
            width: gutterWidth + horizontalPadding * 2 + longestLineWidth,
            height: verticalPadding * 2 + CGFloat(max(snapshot.lines.count, 1)) * lineHeight
        )
    }

    private func clampScrollOffset() {
        let maxX = max(0, contentSize.width - bounds.width)
        let maxY = max(0, contentSize.height - bounds.height)

        scrollOffset.x = min(max(0, scrollOffset.x), maxX)
        scrollOffset.y = min(max(0, scrollOffset.y), maxY)
    }

    private func updateDrawableSize() {
        let scale = backingScaleFactor
        drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
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
}
