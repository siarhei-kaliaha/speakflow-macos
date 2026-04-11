#!/usr/bin/env swift
import AppKit
import Foundation

var fnIsDown = false
let rightModifiers: [(UInt16, NSEvent.ModifierFlags, String)] = [
    (54, .command, "RightCommand"),
    (62, .control, "RightControl")
]

func emit(_ message: String) {
    guard let data = (message + "\n").data(using: .utf8) else { return }
    FileHandle.standardOutput.write(data)
    fflush(stdout)
}

guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { event in
    let containsFn = event.modifierFlags.contains(.function)

    if containsFn && !fnIsDown {
        fnIsDown = true
        emit("FN_DOWN")
    } else if !containsFn && fnIsDown {
        fnIsDown = false
        emit("FN_UP")
    }

    let keyCode = event.keyCode
    for (code, flag, name) in rightModifiers where keyCode == code {
        emit(event.modifierFlags.contains(flag) ? "RIGHT_MOD_DOWN:\(name)" : "RIGHT_MOD_UP:\(name)")
    }
}) else {
    FileHandle.standardError.write(Data("Failed to create event monitor\n".utf8))
    exit(1)
}

let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
signalSource.setEventHandler {
    NSEvent.removeMonitor(monitor)
    exit(0)
}
signalSource.resume()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
