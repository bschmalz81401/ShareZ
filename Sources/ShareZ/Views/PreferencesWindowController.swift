import Cocoa

final class PreferencesWindowController: NSWindowController {
    private static var shared: PreferencesWindowController?

    static func showOrBring() {
        if shared == nil { shared = PreferencesWindowController() }
        shared!.showWindow(nil)
        shared!.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var regionField:     HotkeyRecorderField!
    private var windowField:     HotkeyRecorderField!
    private var fullscreenField: HotkeyRecorderField!

    init() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 380, height: 200),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "ShareZ Preferences"
        win.center()
        super.init(window: win)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        let mgr = HotkeyManager.shared
        let content = NSView()
        content.frame = window!.contentRect(forFrameRect: window!.frame)
        window!.contentView = content

        func makeLabel(_ text: String, y: CGFloat) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.frame = CGRect(x: 20, y: y, width: 140, height: 22)
            lbl.alignment = .right
            return lbl
        }

        let rows: [(String, HotkeyBinding, CGFloat)] = [
            ("Capture Region:", mgr.regionBinding,     130),
            ("Capture Window:", mgr.windowBinding,     90),
            ("Capture Fullscreen:", mgr.fullscreenBinding, 50),
        ]

        regionField     = HotkeyRecorderField(binding: rows[0].1)
        windowField     = HotkeyRecorderField(binding: rows[1].1)
        fullscreenField = HotkeyRecorderField(binding: rows[2].1)

        let fields = [regionField!, windowField!, fullscreenField!]

        for (i, (label, _, y)) in rows.enumerated() {
            let lbl = makeLabel(label, y: y)
            content.addSubview(lbl)

            let f = fields[i]
            f.frame = CGRect(x: 168, y: y, width: 170, height: 24)
            content.addSubview(f)
        }

        let note = NSTextField(labelWithString: "Click a field and press keys to record a hotkey. Press Esc to clear.")
        note.frame = CGRect(x: 20, y: 16, width: 340, height: 28)
        note.font = NSFont.systemFont(ofSize: 10)
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
        content.addSubview(note)

        let save = NSButton(frame: CGRect(x: 280, y: 160, width: 80, height: 28))
        save.title = "Save"
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.target = self
        save.action = #selector(saveAction)
        content.addSubview(save)
    }

    @objc private func saveAction() {
        HotkeyManager.shared.save(
            region:     regionField.binding,
            window:     windowField.binding,
            fullscreen: fullscreenField.binding
        )
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        PreferencesWindowController.shared = nil
    }
}

// MARK: - Hotkey Recorder Field

final class HotkeyRecorderField: NSView {
    private(set) var binding: HotkeyBinding
    private var label: NSTextField!
    private var isRecording = false
    private var localMonitor: Any?

    init(binding: HotkeyBinding) {
        self.binding = binding
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        updateAppearance()
        setupLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLabel() {
        label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.autoresizingMask = [.width, .height]
        addSubview(label)
        updateLabel()
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 4, dy: 1)
    }

    private func updateLabel() {
        if isRecording {
            label.stringValue = "Type shortcut…"
            label.textColor = .secondaryLabelColor
        } else {
            label.stringValue = binding.isEmpty ? "Click to set" : binding.displayString
            label.textColor = binding.isEmpty ? .tertiaryLabelColor : .labelColor
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = isRecording
            ? NSColor.selectedControlColor.withAlphaComponent(0.2).cgColor
            : NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = isRecording
            ? NSColor.selectedControlColor.cgColor
            : NSColor.separatorColor.cgColor
    }

    // MARK: - Recording

    override func mouseDown(with event: NSEvent) {
        isRecording ? stopRecording(clearBinding: false) : startRecording()
    }

    private func startRecording() {
        isRecording = true
        updateLabel()
        updateAppearance()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 { // Escape — clear the binding
                self.binding = .empty
                self.stopRecording(clearBinding: false)
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier to avoid capturing bare letter keys
            guard mods.contains(.command) || mods.contains(.control) ||
                  mods.contains(.option) || mods.contains(.shift) else { return event }

            self.binding = HotkeyBinding(keyCode: event.keyCode, modifierFlags: mods.rawValue)
            self.stopRecording(clearBinding: false)
            return nil
        }
    }

    private func stopRecording(clearBinding: Bool) {
        if clearBinding { binding = .empty }
        isRecording = false
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        updateLabel()
        updateAppearance()
    }
}
