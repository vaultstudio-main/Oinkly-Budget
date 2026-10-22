import AppKit

/// Says that Oinkly Budget is about to close or restart, and counts down so there is time to finish up. Nothing is
/// done until the count reaches zero or the person chooses to go now; Cancel leaves everything as it was.
@MainActor
enum ClosingCountdown {
    enum Kind {
        case restart, quit

        var verb: String { self == .restart ? "restart" : "close" }
        var now: String { self == .restart ? "Restart Now" : "Close Now" }
    }

    /// True to go ahead (the count ran out, or "Now" was chosen), false when cancelled.
    static func run(_ kind: Kind, reason: String, seconds: Int = 5) -> Bool {
        var remaining = max(seconds, 1)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        func title() -> String { "Oinkly Budget will \(kind.verb) in \(remaining) second\(remaining == 1 ? "" : "s")" }
        alert.messageText = title()
        alert.informativeText = reason
        alert.addButton(withTitle: kind.now)
        alert.addButton(withTitle: "Cancel")

        var counted = false
        // The timer has to run while the alert is up, so it is added for every run loop mode, including the alert's own.
        let timer = Timer(timeInterval: 1, repeats: true) { timer in
            MainActor.assumeIsolated {
                remaining -= 1
                if remaining <= 0 {
                    counted = true
                    timer.invalidate()
                    NSApp.abortModal()
                } else {
                    alert.messageText = title()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        let response = alert.runModal()
        timer.invalidate()
        return counted || response == .alertFirstButtonReturn
    }
}

#if DEBUG
extension ClosingCountdown {
    /// `-closingCountdownTest` shows a 3 second countdown, logs how it ended and how long it took, then quits. Debug only.
    static func runTestIfRequested() {
        guard CommandLine.arguments.contains("-closingCountdownTest") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let begin = Date()
            let proceeded = run(.restart, reason: "Test of the countdown.", seconds: 3)
            NSLog("COUNTDOWN: proceeded \(proceeded) after \(String(format: "%.1f", Date().timeIntervalSince(begin))) s")
            exit(0)
        }
    }
}
#endif
