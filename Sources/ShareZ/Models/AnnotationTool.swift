import Cocoa

enum ToolType: String, CaseIterable {
    case pen = "pencil"
    case arrow = "arrow.up.right"
    case rectangle = "rectangle"
    case text = "textformat"
    case blur = "square.and.pencil"
    case highlight = "highlighter"

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .text: return "Text"
        case .blur: return "Blur"
        case .highlight: return "Highlight"
        }
    }
}

struct DrawingState {
    var toolType: ToolType = .pen
    var color: NSColor = .red
    var lineWidth: CGFloat = 3
    var fontSize: CGFloat = 18
}

// MARK: - Annotation elements

enum AnnotationElement {
    case path(Path)
    case arrow(Arrow)
    case rectangle(Rectangle)
    case textLabel(TextLabel)
    case blur(BlurRegion)
    case highlight(HighlightRegion)

    struct Path {
        var points: [CGPoint]
        var color: NSColor
        var lineWidth: CGFloat
    }

    struct Arrow {
        var start: CGPoint
        var end: CGPoint
        var color: NSColor
        var lineWidth: CGFloat
    }

    struct Rectangle {
        var rect: CGRect
        var color: NSColor
        var lineWidth: CGFloat
    }

    struct TextLabel {
        var origin: CGPoint
        var text: String
        var color: NSColor
        var fontSize: CGFloat
    }

    struct BlurRegion {
        var rect: CGRect
    }

    struct HighlightRegion {
        var rect: CGRect
        var color: NSColor
    }

    func draw(in ctx: CGContext, imageSize: CGSize) {
        switch self {
        case .path(let p):
            guard p.points.count > 1 else { return }
            ctx.setStrokeColor(p.color.cgColor)
            ctx.setLineWidth(p.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.beginPath()
            ctx.move(to: p.points[0])
            for pt in p.points.dropFirst() { ctx.addLine(to: pt) }
            ctx.strokePath()

        case .arrow(let a):
            ctx.setStrokeColor(a.color.cgColor)
            ctx.setFillColor(a.color.cgColor)
            ctx.setLineWidth(a.lineWidth)
            let dx = a.end.x - a.start.x
            let dy = a.end.y - a.start.y
            let angle = atan2(dy, dx)
            let headLen: CGFloat = max(a.lineWidth * 4, 14)
            let tip = a.end
            let base1 = CGPoint(
                x: tip.x - headLen * cos(angle - .pi / 6),
                y: tip.y - headLen * sin(angle - .pi / 6)
            )
            let base2 = CGPoint(
                x: tip.x - headLen * cos(angle + .pi / 6),
                y: tip.y - headLen * sin(angle + .pi / 6)
            )
            ctx.beginPath()
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.strokePath()
            ctx.beginPath()
            ctx.move(to: tip)
            ctx.addLine(to: base1)
            ctx.addLine(to: base2)
            ctx.closePath()
            ctx.fillPath()

        case .rectangle(let r):
            ctx.setStrokeColor(r.color.cgColor)
            ctx.setLineWidth(r.lineWidth)
            ctx.stroke(r.rect)

        case .textLabel(let t):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: t.fontSize, weight: .semibold),
                .foregroundColor: t.color
            ]
            let str = NSAttributedString(string: t.text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)
            ctx.textPosition = t.origin
            CTLineDraw(line, ctx)

        case .blur(let b):
            // Handled separately at render time — needs source bitmap
            break

        case .highlight(let h):
            ctx.setFillColor(h.color.withAlphaComponent(0.35).cgColor)
            ctx.fill(h.rect)
        }
    }
}
