// DictusCore/Sources/DictusCore/DarwinNotifications.swift
import Foundation

/// Darwin notification names for cross-process signaling.
/// Darwin notifications carry no payload — they are ping-only.
/// After receiving a notification, read the actual data from AppGroup.defaults.
public enum DarwinNotificationName {
    /// Posted by DictusApp when transcription result is written to App Group.
    public static let transcriptionReady = "com.pivi.dictus.transcriptionReady" as CFString

    /// Posted by DictusApp when dictation status changes.
    public static let statusChanged = "com.pivi.dictus.statusChanged" as CFString

    /// Posted by keyboard extension to request DictusApp stop recording (keyboard -> app).
    public static let stopRecording = "com.pivi.dictus.stopRecording" as CFString

    /// Posted by keyboard extension to request DictusApp cancel recording (keyboard -> app).
    public static let cancelRecording = "com.pivi.dictus.cancelRecording" as CFString

    /// Posted by DictusApp when waveform energy data is written to App Group (app -> keyboard).
    public static let waveformUpdate = "com.pivi.dictus.waveformUpdate" as CFString
}

/// Global callback registry for Darwin notifications.
/// Must be at module level because CFNotificationCenter callbacks are C function pointers
/// that cannot capture Swift context. The registry is thread-safe via NSLock.
private let _darwinCallbackLock = NSLock()
private var _darwinCallbacks: [String: () -> Void] = [:]

/// C-compatible callback dispatched by CFNotificationCenter.
/// No context captured — looks up handler in the global registry by notification name.
private let _darwinCallback: CFNotificationCallback = { _, _, cfName, _, _ in
    guard let cfName = cfName else { return }
    let key = cfName.rawValue as String
    _darwinCallbackLock.lock()
    let cb = _darwinCallbacks[key]
    _darwinCallbackLock.unlock()
    cb?()
}

/// Helper to post and observe Darwin notifications.
/// Thread safety: `_darwinCallbacks` is protected by `_darwinCallbackLock`.
public enum DarwinNotificationCenter {

    public static func post(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil, nil, true
        )
    }

    public static func addObserver(
        for name: CFString,
        callback: @escaping () -> Void
    ) {
        _darwinCallbackLock.lock()
        _darwinCallbacks[name as String] = callback
        _darwinCallbackLock.unlock()

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            _darwinCallback,
            name,
            nil,
            .deliverImmediately
        )
    }

    /// Remove a specific observer by notification name.
    /// Prefer this over removeAllObservers() for safer cleanup.
    public static func removeObserver(for name: CFString) {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            CFNotificationName(name),
            nil
        )
        _darwinCallbackLock.lock()
        _darwinCallbacks.removeValue(forKey: name as String)
        _darwinCallbackLock.unlock()
    }

    /// Remove all registered observers.
    public static func removeAllObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        _darwinCallbackLock.lock()
        let names = Array(_darwinCallbacks.keys)
        _darwinCallbacks.removeAll()
        _darwinCallbackLock.unlock()

        for name in names {
            CFNotificationCenterRemoveObserver(
                center,
                nil,
                CFNotificationName(name as CFString),
                nil
            )
        }
    }
}
