import Cocoa

// MARK: - Canvas

final class AnnotationCanvasView: NSView {
    var baseImage: NSImage?
    var elements: [AnnotationElement] = []
    var drawingState = DrawingState()
    var onStrokeCommit: (([AnnotationElement]) -> Void)?

    // isFlipped is intentionally left at the default (false).
    // All coordinates are in AppKit-native space: origin bottom-left, Y up.
    // The CGContext in draw() is therefore unflipped — no manual CTM flip needed.

    private var dragStart: CGPoint?
    private var currentPoints: [CGPoint] = []
    private var pendingElement: AnnotationElement?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        baseImage?.draw(in: bounds)
        for element in elements { drawElement(element, in: ctx) }
        if let pending = pendingElement { drawElement(pending, in: ctx) }
    }

    private func drawElement(_ element: AnnotationElement, in ctx: CGContext) {
        if case .blur(let b) = element {
            drawBlur(rect: b.rect, in: ctx)
        } else {
            element.draw(in: ctx, imageSize: bounds.size)
        }
    }

    private func drawBlur(rect: CGRect, in ctx: CGContext) {
        guard let img = baseImage,
              let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scaleX = CGFloat(cgImg.width) / bounds.width
        let scaleY = CGFloat(cgImg.height) / bounds.height
        // CGImage crop uses top-left origin — flip Y relative to the view
        let srcRect = CGRect(
            x: rect.origin.x * scaleX,
            y: (bounds.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        guard let cropped = cgImg.cropping(to: srcRect) else { return }
        let ciImage = CIImage(cgImage: cropped).applyingGaussianBlur(sigma: 12)
        let ciCtx = CIContext()
        guard let blurred = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return }
        ctx.draw(blurred, in: rect)
    }

    // MARK: - Mouse handling (all coords in AppKit native: bottom-left Y up)

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        dragStart = pt
        currentPoints = [pt]
        pendingElement = nil
        if drawingState.toolType == .text { promptText(at: pt) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let pt = convert(event.locationInWindow, from: nil)
        currentPoints.append(pt)

        switch drawingState.toolType {
        case .pen:
            pendingElement = .path(.init(points: currentPoints,
                                        color: drawingState.color,
                                        lineWidth: drawingState.lineWidth))
        case .arrow:
            pendingElement = .arrow(.init(start: start, end: pt,
                                         color: drawingState.color,
                                         lineWidth: drawingState.lineWidth))
        case .rectangle:
            pendingElement = .rectangle(.init(rect: makeRect(start, pt),
                                             color: drawingState.color,
                                             lineWidth: drawingState.lineWidth))
        case .blur:
            pendingElement = .blur(.init(rect: makeRect(start, pt)))
        case .highlight:
            pendingElement = .highlight(.init(rect: makeRect(start, pt),
                                             color: drawingState.color))
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let pending = pendingElement else { return }
        elements.append(pending)
        pendingElement = nil
        onStrokeCommit?(elements)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.close() }
    }

    private func makeRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func promptText(at point: CGPoint) {
        let alert = NSAlert()
        alert.messageText = "Enter text"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "Label text…"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn, !input.stringValue.isEmpty else { return }
        elements.append(.textLabel(.init(origin: point,
                                        text: input.stringValue,
                                        color: drawingState.color,
                                        fontSize: drawingState.fontSize)))
        onStrokeCommit?(elements)
        needsDisplay = true
    }

    // MARK: - Render to image

    func renderedImage() -> NSImage? {
        guard let base = baseImage else { return nil }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let scale = window?.backingScaleFactor ?? 2.0
        let pixW = Int(size.width * scale)
        let pixH = Int(size.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixW, pixelsHigh: pixH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext

        ctx.scaleBy(x: scale, y: scale)
        base.draw(in: CGRect(origin: .zero, size: size))
        for el in elements { drawElement(el, in: ctx) }

        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}
