import Cocoa

extension Notification.Name {
    static let hotkeysSaved = Notification.Name("ShareZ.hotkeysSaved")
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private(set) var regionBinding   = HotkeyBinding.empty
    private(set) var windowBinding   = HotkeyBinding.empty
    private(set) var fullscreenBinding = HotkeyBinding.empty

    var onRegionCapture:    (() -> Void)?
    var onWindowCapture:    (() -> Void)?
    var onFullscreenCapture: (() -> Void)?

    private var monitor: Any?

    private init() { load() }

    // MARK: - Persistence

    func load() {
        regionBinding     = decode("hotkey.region")     ?? .empty
        windowBinding     = decode("hotkey.window")     ?? .empty
        fullscreenBinding = decode("hotkey.fullscreen") ?? .empty
    }

    func save(region: HotkeyBinding, window: HotkeyBinding, fullscreen: HotkeyBinding) {
        regionBinding     = region
        windowBinding     = window
        fullscreenBinding = fullscreen
        encode(region,     key: "hotkey.region")
        encode(window,     key: "hotkey.window")
        encode(fullscreen, key: "hotkey.fullscreen")
        reinstall()
        NotificationCenter.default.post(name: .hotkeysSaved, object: nil)
    }

    private func decode(_ key: String) -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    private func encode(_ binding: HotkeyBinding, key: String) {
        let data = try? JSONEncoder().encode(binding)
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Registration

    func install() { reinstall() }

    private func reinstall() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        guard !regionBinding.isEmpty || !windowBinding.isEmpty || !fullscreenBinding.isEmpty else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if self.regionBinding.matches(event)     { DispatchQueue.main.async { self.onRegionCapture?() } }
            if self.windowBinding.matches(event)     { DispatchQueue.main.async { self.onWindowCapture?() } }
            if self.fullscreenBinding.matches(event) { DispatchQueue.main.async { self.onFullscreenCapture?() } }
        }
    }

    func uninstall() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
