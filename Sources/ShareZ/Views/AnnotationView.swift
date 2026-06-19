import Cocoa

// MARK: - Canvas

final class AnnotationCanvasView: NSView {
    var baseImage: NSImage?
    var elements: [AnnotationElement] = []
    var drawingState = DrawingState()

    var onStrokeCommit: (([AnnotationElement]) -> Void)?

    private var currentPoints: [CGPoint] = []
    private var currentTool: ToolType { drawingState.toolType }
    private var dragStart: CGPoint?

    // In-progress element overlay (not yet committed)
    private var pendingElement: AnnotationElement?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Draw base image
        if let img = baseImage {
            img.draw(in: bounds)
        }

        // Flip context for CG drawing (NSView isFlipped = true, but CG origin is bottom-left)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        for element in elements {
            if case .blur(let b) = element {
                drawBlur(rect: b.rect, in: ctx)
            } else {
                element.draw(in: ctx, imageSize: bounds.size)
            }
        }
        if let pending = pendingElement {
            if case .blur(let b) = pending {
                drawBlur(rect: b.rect, in: ctx)
            } else {
                pending.draw(in: ctx, imageSize: bounds.size)
            }
        }

        ctx.restoreGState()
    }

    private func drawBlur(rect: CGRect, in ctx: CGContext) {
        guard let img = baseImage, let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = bounds.width > 0 ? CGFloat(cgImg.width) / bounds.width : 1
        let srcRect = CGRect(x: rect.origin.x * scale,
                             y: (bounds.height - rect.maxY) * scale,
                             width: rect.width * scale,
                             height: rect.height * scale)
        guard let cropped = cgImg.cropping(to: srcRect) else { return }
        let ciImage = CIImage(cgImage: cropped)
        let blurred = ciImage.applyingGaussianBlur(sigma: 12)
        let rep = NSCIImageRep(ciImage: blurred)
        let ns = NSImage(size: NSSize(width: rect.width, height: rect.height))
        ns.addRepresentation(rep)
        // Draw in flipped context rect
        let drawRect = CGRect(x: rect.origin.x, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        ctx.draw(ns.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: drawRect)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        dragStart = pt
        currentPoints = [pt]
        pendingElement = nil

        if currentTool == .text {
            promptText(at: pt)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        currentPoints.append(pt)
        guard let start = dragStart else { return }

        switch currentTool {
        case .pen:
            pendingElement = .path(.init(points: currentPoints, color: drawingState.color, lineWidth: drawingState.lineWidth))
        case .arrow:
            pendingElement = .arrow(.init(start: start, end: pt, color: drawingState.color, lineWidth: drawingState.lineWidth))
        case .rectangle:
            let r = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y),
                           width: abs(pt.x - start.x), height: abs(pt.y - start.y))
            pendingElement = .rectangle(.init(rect: r, color: drawingState.color, lineWidth: drawingState.lineWidth))
        case .blur:
            let r = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y),
                           width: abs(pt.x - start.x), height: abs(pt.y - start.y))
            pendingElement = .blur(.init(rect: r))
        case .highlight:
            let r = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y),
                           width: abs(pt.x - start.x), height: abs(pt.y - start.y))
            pendingElement = .highlight(.init(rect: r, color: drawingState.color))
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
        let el = AnnotationElement.textLabel(.init(
            origin: CGPoint(x: point.x, y: bounds.height - point.y),
            text: input.stringValue,
            color: drawingState.color,
            fontSize: drawingState.fontSize
        ))
        elements.append(el)
        onStrokeCommit?(elements)
        needsDisplay = true
    }

    func renderedImage() -> NSImage? {
        guard let base = baseImage else { return nil }
        let size = base.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                   pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        base.draw(in: CGRect(origin: .zero, size: size))
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        for el in elements {
            if case .blur(let b) = el { drawBlur(rect: b.rect, in: ctx) }
            else { el.draw(in: ctx, imageSize: size) }
        }
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}
