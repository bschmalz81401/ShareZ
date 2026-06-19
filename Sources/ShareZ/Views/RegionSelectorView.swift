import Cocoa

final class RegionSelectorWindowController: NSWindowController, NSWindowDelegate {
    private var selectionView: RegionSelectionView!
    private var completion: ((NSImage?) -> Void)?

    // Strong reference so the controller lives until it explicitly cleans itself up
    private static var active: RegionSelectorWindowController?

    static func show(completion: @escaping (NSImage?) -> Void) {
        // Dismiss any existing selector before opening a new one
        active?.cancelAndClose()

        guard let screen = NSScreen.main else { completion(nil); return }
        let controller = RegionSelectorWindowController(screen: screen, completion: completion)
        active = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    init(screen: NSScreen, completion: @escaping (NSImage?) -> Void) {
        self.completion = completion
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // .modalPanel is below system UI so Cmd+Option+Esc (Force Quit) still works
        win.level = .modalPanel
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        selectionView = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        win.contentView = selectionView
        super.init(window: win)
        win.delegate = self

        selectionView.onComplete = { [weak self] rect in
            self?.handleSelection(rect, screen: screen)
        }
        selectionView.onCancel = { [weak self] in
            self?.cancelAndClose()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func handleSelection(_ rect: NSRect, screen: NSScreen) {
        let cb = completion
        completion = nil
        close()
        RegionSelectorWindowController.active = nil

        Task { @MainActor in
            // Let the overlay window fully disappear before capturing
            try? await Task.sleep(nanoseconds: 150_000_000)
            let image = await CaptureManager().captureRect(rect, on: screen)
            cb?(image)
        }
    }

    func cancelAndClose() {
        let cb = completion
        completion = nil
        close()
        RegionSelectorWindowController.active = nil
        cb?(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Safety net: if window closes for any reason, fire completion so callers aren't left hanging
        if completion != nil {
            cancelAndClose()
        }
    }
}

final class RegionSelectionView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isSelecting = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill()

        if isSelecting && currentRect.width > 2 && currentRect.height > 2 {
            // Punch out the selected region so the user sees through the overlay
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                NSColor.clear.setFill()
                NSBezierPath(rect: currentRect).fill()
                ctx.restoreGState()
            }

            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: currentRect)
            border.lineWidth = 1.5
            border.stroke()

            let label = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let labelSize = label.size(withAttributes: attrs)
            let labelOrigin = NSPoint(
                x: min(currentRect.maxX - labelSize.width - 4, bounds.width - labelSize.width - 4),
                y: max(currentRect.maxY + 4, 4)
            )
            label.draw(at: labelOrigin, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isSelecting = true
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard currentRect.width > 5 && currentRect.height > 5 else {
            onCancel?()
            return
        }
        guard let screen = window?.screen else {
            onCancel?()
            return
        }
        // Convert from flipped view coords to screen coords
        let screenRect = NSRect(
            x: screen.frame.origin.x + currentRect.minX,
            y: screen.frame.origin.y + (screen.frame.height - currentRect.maxY),
            width: currentRect.width,
            height: currentRect.height
        )
        onComplete?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
