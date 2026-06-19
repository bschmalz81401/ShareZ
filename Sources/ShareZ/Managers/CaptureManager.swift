import Cocoa
import ScreenCaptureKit

@MainActor
final class CaptureManager {

    // MARK: - Permission

    func requestPermission() async {
        // Calling SCShareableContent triggers the system permission prompt
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Open System Settings → Privacy & Security → Screen Recording and enable ShareZ, then relaunch the app."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    // MARK: - Capture

    func captureFullscreen() async -> NSImage? {
        guard let screen = NSScreen.main else { return nil }
        return await captureRect(screen.frame, on: screen)
    }

    /// rect is in NS screen coordinates (origin bottom-left of main screen, Y up).
    func captureRect(_ rect: CGRect, on screen: NSScreen) async -> NSImage? {
        guard hasPermission() else {
            showPermissionAlert()
            return nil
        }

        if #available(macOS 14.0, *) {
            if let img = await captureRectSCKit(rect, screen: screen) { return img }
        }
        return captureRectCG(rect)
    }

    @available(macOS 14.0, *)
    private func captureRectSCKit(_ rect: CGRect, screen: NSScreen) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // SCDisplay.frame is in CG display space (top-left origin, Y down)
            let cgRect = nsToCGScreenRect(rect)
            guard let display = content.displays.first(where: { $0.frame.intersects(cgRect) }) else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor

            // Capture the full display then crop — avoids sourceRect coordinate ambiguity
            config.width = Int(display.frame.width * scale)
            config.height = Int(display.frame.height * scale)
            config.showsCursor = false

            let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            // Crop to the selection in physical pixels
            let dispH = display.frame.height
            let dispOriginX = display.frame.origin.x
            let dispOriginY = display.frame.origin.y  // in CG display space (Y down)

            // cgRect.origin is top-left of selection in CG screen space
            let cropX = (cgRect.origin.x - dispOriginX) * scale
            let cropY = (cgRect.origin.y - dispOriginY) * scale
            let cropW = cgRect.width * scale
            let cropH = cgRect.height * scale

            let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
            guard let cropped = fullImage.cropping(to: cropRect) else { return nil }
            return NSImage(cgImage: cropped, size: rect.size)
        } catch {
            return nil
        }
    }

    /// Fallback using CGWindowListCreateImage.
    /// CGWindowListCreateImage expects CG screen coords: top-left of main display, Y down.
    private func captureRectCG(_ rect: CGRect) -> NSImage? {
        let cgRect = nsToCGScreenRect(rect)
        guard let img = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) else { return nil }
        return NSImage(cgImage: img, size: rect.size)
    }

    // MARK: - Window capture

    func captureInteractiveWindow() async -> NSImage? {
        guard hasPermission() else { showPermissionAlert(); return nil }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch { return nil }

        let visibleWindows = content.windows.filter { $0.isOnScreen && $0.frame.width > 50 }
        let picker = WindowPickerWindowController(windows: visibleWindows)
        guard let window = await picker.pick() else { return nil }

        guard #available(macOS 14.0, *) else { return nil }
        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: window.frame.size)
        } catch { return nil }
    }

    // MARK: - Coordinate conversion

    /// NS screen coordinates → CG screen coordinates.
    /// NS: origin at bottom-left of primary screen, Y up.
    /// CG: origin at top-left of primary screen, Y down.
    private func nsToCGScreenRect(_ rect: CGRect) -> CGRect {
        let mainH = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(
            x: rect.origin.x,
            y: mainH - rect.maxY,   // flip Y using the rect's top edge
            width: rect.width,
            height: rect.height
        )
    }
}
