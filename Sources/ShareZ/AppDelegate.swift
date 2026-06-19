import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var captureManager: CaptureManager!
    private var hotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureManager = CaptureManager()
        setupStatusItem()
        setupGlobalHotkeys()
        requestScreenCapturePermission()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Screenshot")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Region  ⌘⇧4", action: #selector(captureRegion), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Window  ⌘⇧3", action: #selector(captureWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Fullscreen  ⌘⇧F", action: #selector(captureFullscreen), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupGlobalHotkeys() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let cmd_shift: NSEvent.ModifierFlags = [.command, .shift]
            guard flags == cmd_shift else { return }
            switch event.keyCode {
            case 21: self?.captureRegion()     // 4
            case 20: self?.captureWindow()     // 3
            case 3:  self?.captureFullscreen() // F
            default: break
            }
        }
    }

    private func requestScreenCapturePermission() {
        if #available(macOS 14.0, *) {
            Task { await captureManager.requestPermission() }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    @objc func captureRegion() {
        RegionSelectorWindowController.show { [weak self] image in
            guard let image else { return }
            self?.openAnnotationEditor(with: image)
        }
    }

    @objc func captureWindow() {
        Task { @MainActor in
            guard let image = await self.captureManager.captureInteractiveWindow() else { return }
            self.openAnnotationEditor(with: image)
        }
    }

    @objc func captureFullscreen() {
        Task { @MainActor in
            guard let image = await self.captureManager.captureFullscreen() else { return }
            self.openAnnotationEditor(with: image)
        }
    }

    private func openAnnotationEditor(with image: NSImage) {
        AnnotationWindowController.show(with: image)
    }
}

