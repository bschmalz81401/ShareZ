import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var captureManager: CaptureManager!
    private var regionMenuItem: NSMenuItem!
    private var windowMenuItem: NSMenuItem!
    private var fullscreenMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureManager = CaptureManager()
        setupStatusItem()
        setupHotkeyManager()
        requestScreenCapturePermission()
        requestAccessibilityPermission()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "ShareZ")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let mgr = HotkeyManager.shared
        let menu = NSMenu()

        regionMenuItem = NSMenuItem(title: menuTitle("Capture Region", mgr.regionBinding),
                                   action: #selector(captureRegion), keyEquivalent: "")
        windowMenuItem = NSMenuItem(title: menuTitle("Capture Window", mgr.windowBinding),
                                   action: #selector(captureWindow), keyEquivalent: "")
        fullscreenMenuItem = NSMenuItem(title: menuTitle("Capture Fullscreen", mgr.fullscreenBinding),
                                       action: #selector(captureFullscreen), keyEquivalent: "")
        menu.addItem(regionMenuItem)
        menu.addItem(windowMenuItem)
        menu.addItem(fullscreenMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ShareZ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func menuTitle(_ base: String, _ binding: HotkeyBinding) -> String {
        binding.isEmpty ? base : "\(base)   \(binding.displayString)"
    }

    // MARK: - Hotkeys

    private func setupHotkeyManager() {
        let mgr = HotkeyManager.shared
        mgr.onRegionCapture    = { [weak self] in self?.captureRegion() }
        mgr.onWindowCapture    = { [weak self] in self?.captureWindow() }
        mgr.onFullscreenCapture = { [weak self] in self?.captureFullscreen() }
        mgr.install()

        // Rebuild menu labels whenever prefs are saved
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeysSaved),
                                               name: .hotkeysSaved, object: nil)
    }

    @objc private func hotkeysSaved() { rebuildMenu() }

    // MARK: - Actions

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

    @objc private func openPreferences() {
        PreferencesWindowController.showOrBring()
    }

    private func openAnnotationEditor(with image: NSImage) {
        AnnotationWindowController.show(with: image)
    }

    private func requestScreenCapturePermission() {
        if #available(macOS 14.0, *) {
            Task { await captureManager.requestPermission() }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            // Poll until granted, then reinstall hotkeys
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.pollAccessibilityUntilGranted()
            }
        }
    }

    private func pollAccessibilityUntilGranted() {
        if AXIsProcessTrusted() {
            HotkeyManager.shared.install()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.pollAccessibilityUntilGranted()
            }
        }
    }
}

