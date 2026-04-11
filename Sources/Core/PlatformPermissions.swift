import ApplicationServices
import CoreGraphics

enum PlatformPermissions {
    @MainActor
    static func accessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func postEvent(prompt: Bool) -> Bool {
        if CGPreflightPostEventAccess() {
            return true
        }
        guard prompt else {
            return false
        }
        return CGRequestPostEventAccess()
    }

    @MainActor
    static func listenEvent(prompt: Bool) -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        guard prompt else {
            return false
        }
        return CGRequestListenEventAccess()
    }
}
