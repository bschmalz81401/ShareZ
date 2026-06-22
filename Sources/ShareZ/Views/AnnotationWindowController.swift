import Cocoa

private func makePNG(from image: NSImage) -> Data? {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    // Re-render through AppKit's own drawing machinery to normalise
    // colour space and avoid any coordinate-system manipulation.
    let clean = NSImage(size: size, flipped: false) { rect in
        image.draw(in: rect)
        return true
    }
    guard let tiff = clean.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

final class AnnotationWindowController: NSWindowController, NSWindowDelegate {
    private let canvas: AnnotationCanvasView
    private var toolbar: AnnotationToolbar!
    private var undoStack: [[AnnotationElement]] = [[]]

    // Retain all open annotation windows until they close themselves
    private static var openWindows: [AnnotationWindowController] = []

    static func show(with image: NSImage) {
        let controller = AnnotationWindowController(image: image)
        openWindows.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(image: NSImage) {
        canvas = AnnotationCanvasView()
        canvas.baseImage = image

        let imgSize = image.size
        let maxW: CGFloat = min(imgSize.width, NSScreen.main?.visibleFrame.width ?? 1400)
        let maxH: CGFloat = min(imgSize.height, (NSScreen.main?.visibleFrame.height ?? 900) - 80)
        let scale = min(maxW / imgSize.width, maxH / imgSize.height, 1.0)
        let displaySize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)

        let toolbarH: CGFloat = 56
        let win = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: displaySize.width, height: displaySize.height + toolbarH)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ShareZ — Annotate"
        win.center()
        super.init(window: win)
        win.delegate = self

        toolbar = AnnotationToolbar(canvas: canvas) { [weak self] in self?.copyToClipboard() }
        toolbar.frame = CGRect(x: 0, y: displaySize.height, width: displaySize.width, height: toolbarH)
        toolbar.autoresizingMask = [.width, .minYMargin]

        canvas.frame = CGRect(origin: .zero, size: displaySize)
        canvas.autoresizingMask = [.width, .height]

        let content = NSView()
        content.frame = win.contentRect(forFrameRect: win.frame)
        content.addSubview(canvas)
        content.addSubview(toolbar)
        win.contentView = content

        canvas.onStrokeCommit = { [weak self] elements in
            self?.undoStack.append(elements)
        }

        let undoMenu = NSMenuItem(title: "Undo", action: #selector(undoAction), keyEquivalent: "z")
        NSApp.mainMenu?.item(withTitle: "Edit")?.submenu?.insertItem(undoMenu, at: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func undoAction() {
        guard undoStack.count > 1 else { return }
        undoStack.removeLast()
        canvas.elements = undoStack.last ?? []
        canvas.needsDisplay = true
    }

    private func copyToClipboard() {
        guard let image = canvas.renderedImage(),
              let png = makePNG(from: image) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        showCopiedToast()
    }


    private func showCopiedToast() {
        guard let win = window else { return }
        let toast = NSTextField(labelWithString: "  Copied to clipboard  ")
        toast.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        toast.textColor = .white
        toast.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        toast.isBezeled = false
        toast.drawsBackground = true
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 8
        toast.sizeToFit()
        toast.frame.origin = CGPoint(
            x: (win.contentView!.bounds.width - toast.frame.width) / 2,
            y: 60
        )
        win.contentView?.addSubview(toast)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                toast.animator().alphaValue = 0
            } completionHandler: {
                toast.removeFromSuperview()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        AnnotationWindowController.openWindows.removeAll { $0 === self }
    }
}

// MARK: - Toolbar

final class AnnotationToolbar: NSView {
    private let canvas: AnnotationCanvasView
    private let copyAction: () -> Void
    private var toolSegment: NSSegmentedControl!
    private var colorWell: NSColorWell!
    private var sizeSlider: NSSlider!

    init(canvas: AnnotationCanvasView, copyAction: @escaping () -> Void) {
        self.canvas = canvas
        self.copyAction = copyAction
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupControls() {
        // Tool selector — NSSegmentedControl is reliable for selection state
        let toolNames = ToolType.allCases.map { $0.rawValue }
        toolSegment = NSSegmentedControl(frame: CGRect(x: 8, y: 10, width: CGFloat(toolNames.count) * 36, height: 36))
        toolSegment.segmentCount = toolNames.count
        toolSegment.trackingMode = .selectOne
        toolSegment.segmentStyle = .texturedSquare
        for (i, name) in toolNames.enumerated() {
            let img = NSImage(systemSymbolName: name, accessibilityDescription: ToolType.allCases[i].label)
            toolSegment.setImage(img, forSegment: i)
            toolSegment.setImageScaling(.scaleProportionallyDown, forSegment: i)
            toolSegment.setToolTip(ToolType.allCases[i].label, forSegment: i)
            toolSegment.setWidth(36, forSegment: i)
        }
        toolSegment.selectedSegment = 0  // pen
        toolSegment.target = self
        toolSegment.action = #selector(toolSelected(_:))
        addSubview(toolSegment)

        var x = toolSegment.frame.maxX + 12

        let sep = NSBox(frame: CGRect(x: x, y: 8, width: 1, height: 40))
        sep.boxType = .separator
        addSubview(sep)
        x += 10

        colorWell = NSColorWell(frame: CGRect(x: x, y: 13, width: 30, height: 30))
        colorWell.color = canvas.drawingState.color
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        addSubview(colorWell)
        x += 38

        let sizeLabel = NSTextField(labelWithString: "Size:")
        sizeLabel.frame = CGRect(x: x, y: 19, width: 34, height: 18)
        sizeLabel.font = NSFont.systemFont(ofSize: 11)
        addSubview(sizeLabel)
        x += 36

        sizeSlider = NSSlider(frame: CGRect(x: x, y: 18, width: 80, height: 20))
        sizeSlider.minValue = 1
        sizeSlider.maxValue = 20
        sizeSlider.doubleValue = Double(canvas.drawingState.lineWidth)
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        addSubview(sizeSlider)
        x += 90

        let copyBtn = NSButton(frame: CGRect(x: x, y: 10, width: 80, height: 36))
        copyBtn.title = "Copy"
        copyBtn.bezelStyle = .rounded
        copyBtn.target = self
        copyBtn.action = #selector(copyTapped)
        addSubview(copyBtn)

        let saveBtn = NSButton(frame: CGRect(x: x + 88, y: 10, width: 80, height: 36))
        saveBtn.title = "Save…"
        saveBtn.bezelStyle = .rounded
        saveBtn.target = self
        saveBtn.action = #selector(saveTapped)
        addSubview(saveBtn)
    }

    @objc private func toolSelected(_ sender: NSSegmentedControl) {
        canvas.drawingState.toolType = ToolType.allCases[sender.selectedSegment]
    }

    @objc private func colorChanged() {
        canvas.drawingState.color = colorWell.color
    }

    @objc private func sizeChanged() {
        canvas.drawingState.lineWidth = CGFloat(sizeSlider.doubleValue)
    }

    @objc private func copyTapped() {
        copyAction()
    }

    @objc private func saveTapped() {
        guard let image = canvas.renderedImage(),
              let png = makePNG(from: image) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot"
        panel.begin { response in
            guard response == .OK, var url = panel.url else { return }
            if url.pathExtension.lowercased() != "png" {
                url = url.appendingPathExtension("png")
            }
            try? png.write(to: url)
        }
    }

}

// MARK: - Window Picker

final class WindowPickerWindowController: NSWindowController {
    private let windows: [SCWindow]
    private var continuation: CheckedContinuation<SCWindow?, Never>?

    init(windows: [SCWindow]) {
        self.windows = windows.filter { $0.isOnScreen && ($0.frame.width > 50) }
        let win = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Pick a Window"
        win.center()
        super.init(window: win)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func pick() async -> SCWindow? {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return await withCheckedContinuation { cont in
            continuation = cont
        }
    }

    private func setupUI() {
        let scroll = NSScrollView(frame: window!.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let table = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        col.title = "Window"
        col.width = 360
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(pick(_:))
        table.target = self
        scroll.documentView = table
        window?.contentView?.addSubview(scroll)
    }

    @objc private func pick(_ sender: Any) {
        guard let table = (window?.contentView?.subviews.first as? NSScrollView)?.documentView as? NSTableView,
              table.selectedRow >= 0 else { return }
        let win = windows[table.selectedRow]
        close()
        continuation?.resume(returning: win)
        continuation = nil
    }

    func windowWillClose(_ notification: Notification) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

import ScreenCaptureKit

extension WindowPickerWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { windows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: windows[row].title ?? "(untitled)")
        return cell
    }
}
