import SwiftUI
import SwiftData
import AppKit

/// State that has to outlive any one window: the boot sequence runs once per launch.
enum StartupState {
    static var hasRun = false
    static var databaseError: Error?
}

/// Remembers the boot window so it can be closed explicitly once the main window is up.
private final class BootWindowBox {
    weak var window: NSWindow?
}

/// Strips the boot window down to just the content: no title bar, no close, minimize or zoom buttons.
private struct BootWindowStyle: NSViewRepresentable {
    let box: BootWindowBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView.window)
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        box.window = window
        window.styleMask.remove([.closable, .miniaturizable, .resizable])
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
    }
}

/// The Mac boot window. It runs the startup checks, shows each result, and opens the
/// main window when everything is fine. It only ever runs once per launch.
struct BootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var checker = StartupChecker()
    @State private var isFinished = false
    @State private var handOffStalled = false
    @State private var windowBox = BootWindowBox()

    private var needsAttention: Bool { isFinished && (checker.hasFailure || checker.hasWarning) }

    var body: some View {
        ZStack {
            Brand.gradient.ignoresSafeArea()

            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Image("BootPig")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 92)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    Text("Piggybank Financial Budget").lineLimit(1).minimumScaleFactor(0.6)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(needsAttention ? "NEEDS ATTENTION" : "STARTING UP")
                        .font(.caption.weight(.semibold))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 36)

                if !needsAttention { Spacer(minLength: 0) }

                if needsAttention {
                    // Every check still runs. They only show up here when one of them found a problem.
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(checker.problems) { step in
                            row(step)
                        }
                    }
                    .padding(.horizontal, 36)

                    Spacer(minLength: 0)

                    buttons
                        .frame(height: 44)
                        .padding(.bottom, 24)
                } else {
                    ProgressView(value: checker.progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 260)
                        .animation(.easeInOut(duration: 0.35), value: checker.progress)
                        .padding(.bottom, 40)
                    if handOffStalled {
                        buttons
                            .frame(height: 44)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .frame(width: 500, height: needsAttention ? 580 : 330)
        .background(BootWindowStyle(box: windowBox))
        .task { await boot() }
    }

    private func row(_ step: CheckStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(for: step.status)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(step.status == .pending ? 0.55 : 1))
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.smooth, value: step.status)
    }

    @ViewBuilder
    private func icon(for status: CheckStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.white.opacity(0.45))
        case .running:
            ProgressView().controlSize(.small).tint(.white)
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
        case .fixed:
            Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(.yellow)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if handOffStalled {
            // The main window should have replaced this screen by now. Never leave the user stuck here.
            Button("Open Piggybank Financial Budget", action: handOff)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        } else if needsAttention {
            HStack(spacing: 12) {
                if checker.hasFailure {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                    if StartupState.databaseError == nil {
                        Button("Continue Anyway", action: handOff)
                    }
                } else {
                    Button("Continue", action: handOff)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
    }

    private func boot() async {
        // Reopening the app (for example from the Dock) must not run the checks again.
        if StartupState.hasRun {
            handOff()
            return
        }
        StartupState.hasRun = true

        await checker.run(in: modelContext, databaseError: StartupState.databaseError)
        isFinished = true

        if checker.hasFailure || checker.hasWarning { return }
        try? await Task.sleep(for: .milliseconds(600))
        handOff()
    }

    private func handOff() {
        openWindow(id: "main")
        dismissWindow(id: "boot")
        // Without a close button the window doesn't always go away on its own, and the main window would
        // just cover it. Close it for real.
        windowBox.window?.close()

        // If this window is still here a moment later, the hand-off didn't happen: offer a manual way in.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            handOffStalled = true
        }
    }
}
