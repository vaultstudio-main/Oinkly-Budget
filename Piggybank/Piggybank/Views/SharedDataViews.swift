import SwiftUI
import SwiftData
import AppKit

/// Settings ▸ Data & Backup ▸ Shared Data File: turn sharing on and off, save now, close the file for someone else, and
/// check that the shared folder works.
struct SharedDataSection: View {
    @Environment(\.modelContext) private var modelContext
    private var session: SharedDataSession { SharedDataSession.shared }

    @State private var warning = false
    @State private var confirmingStop = false
    @State private var report: [String]?
    @State private var working = false
    @State private var message: String?
    @State private var messageIsError = false

    private var localStore: URL { AppStore.localStoreURL(for: Schema(versionedSchema: PiggybankSchemaV2.self)) }

    var body: some View {
        Section {
            if SharedDataSession.isEnabled {
                sharing
            } else {
                notSharing
            }
            if let message {
                Label(message, systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(messageIsError ? Color.orange : Theme.green)
            }
        } header: {
            Text("Shared Data File")
        } footer: {
            Text(SharedDataSession.isEnabled
                 ? "Everyone who shares uses the data in /Users/Shared/OinklyBudget, one at a time. If another user has it open, Oinkly Budget waits for them to quit."
                 : "Lets other user accounts on this Mac use the same data, one at a time. Nothing is sent anywhere.")
        }
        .alert("Share your data with other users of this Mac?", isPresented: $warning) {
            Button("Share") { turnOn() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Oinkly Budget will copy your data into /Users/Shared/OinklyBudget. That folder can be opened by every user account on this Mac. Your data stays on this Mac and is never sent anywhere, but anyone who can sign in to this Mac can read it. Your original data is not changed or removed.")
        }
        .confirmationDialog("Stop sharing?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Sharing and Use the Shared Data on This Mac") { turnOff() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This Mac gets a copy of the latest shared data, and a copy of what it had before is kept in Application Support ▸ Backups. Other users keep sharing.")
        }
        .sheet(isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
            CheckSharingSheet(lines: report ?? [])
        }
    }

    // MARK: Off

    @ViewBuilder
    private var notSharing: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share This Data").font(.body.weight(.medium))
                Text("Copies your data into a shared folder so other users of this Mac can use it too.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Share…") { warning = true }.disabled(working)
        }
    }

    // MARK: On

    @ViewBuilder
    private var sharing: some View {
        Label("Shared with other users of this Mac", systemImage: "person.2.fill").foregroundStyle(Theme.green)
        LabeledContent("Folder", value: SharedDataFolder.defaultURL.path)
        if let since = session.openSince {
            LabeledContent("Open by you since", value: since.formatted(date: .omitted, time: .shortened))
        }
        if let saved = session.lastSaved {
            LabeledContent("Last saved to the shared data", value: saved.formatted(date: .abbreviated, time: .shortened))
        }
        if let error = session.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.orange).font(.callout)
        }
        HStack {
            Button("Save Now") { saveNow() }.disabled(working || !session.isActive || session.lostLock)
            Button("Close for Others") { closeForOthers() }
                .disabled(working || !session.isActive || session.lostLock)
                .help("Saves and quits, so another user can open the data.")
            Button("Check Sharing…") { checkSharing() }.disabled(working)
            Spacer()
            Button("Stop Sharing…", role: .destructive) { confirmingStop = true }.disabled(working)
        }
    }

    // MARK: Actions

    private func show(_ text: String, error: Bool = false) {
        message = text
        messageIsError = error
    }

    private func turnOn() {
        working = true
        do {
            try session.enable(localStore: localStore, context: modelContext)
        } catch {
            working = false
            show(error.localizedDescription, error: true)
        }
    }

    private func turnOff() {
        working = true
        Task {
            do { try await session.stopSharing(localStore: localStore) }
            catch {
                working = false
                show("Sharing wasn't stopped: \(error.localizedDescription)", error: true)
            }
        }
    }

    private func saveNow() {
        working = true
        Task {
            await session.checkInNow(release: false)
            working = false
            if let error = session.errorMessage { show(error, error: true) } else { show("Saved to the shared data.") }
        }
    }

    private func closeForOthers() {
        working = true
        Task { await session.closeForOthers() }
    }

    private func checkSharing() {
        working = true
        Task {
            report = await session.checkSharing()
            working = false
        }
    }
}

/// The plain-words report from Check Sharing.
private struct CheckSharingSheet: View {
    let lines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Check Sharing").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Label {
                            Text(line)
                        } icon: {
                            Image(systemName: line.hasPrefix("PROBLEM") ? "exclamationmark.triangle.fill" : (line.hasPrefix("OK") ? "checkmark.circle.fill" : "info.circle"))
                                .foregroundStyle(line.hasPrefix("PROBLEM") ? Color.orange : (line.hasPrefix("OK") ? Theme.green : Color.secondary))
                        }
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}

/// Shown in place of the usual start-up screen when the shared data can't simply be opened. It waits, and says why.
struct SharedWaitingView: View {
    @State private var decision: SharedDataSession.Decision

    init(decision: SharedDataSession.Decision) {
        _decision = State(initialValue: decision)
    }

    var body: some View {
        ZStack {
            Brand.gradient.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("BootPig")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 70)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                Text("Oinkly Budget").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
                content
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
        .task { await watch() }
    }

    @ViewBuilder
    private var content: some View {
        switch decision {
        case .heldBy(let lock, let stale):
            if stale {
                message("\(lock.displayName)'s copy of Oinkly Budget seems to have stopped.",
                        "It hasn't shown a sign of life for \(minutes(lock)) minutes, so it may have crashed or been closed unexpectedly. You can open the shared data anyway. What it saved is kept, and anything newer in that copy is kept as a separate copy.")
                HStack {
                    Button("Open Anyway") { SharedDataSession.shared.openAnyway() }.keyboardShortcut(.defaultAction)
                    Button("Quit") { NSApp.terminate(nil) }
                }
            } else {
                message("Oinkly Budget is already open in \(lock.displayName)'s session.",
                        "Your data is open in another user account on this Mac. Quit Oinkly Budget there (switch to that account and press ⌘Q) and this opens by itself.")
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting…").foregroundStyle(.white.opacity(0.8))
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
        case .folderProblem(let text):
            message("The shared data can't be found.", text)
            HStack {
                Button("Try Again") { SharedDataSession.shared.tryAgain() }.keyboardShortcut(.defaultAction)
                Button("Use This Mac's Own Data") { SharedDataSession.shared.useThisMacsData() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        case .failed(let text):
            message("The shared data couldn't be opened.", text + " Nothing was changed.")
            HStack {
                Button("Try Again") { SharedDataSession.shared.tryAgain() }.keyboardShortcut(.defaultAction)
                Button("Use This Mac's Own Data") { SharedDataSession.shared.useThisMacsData() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(detail).font(.callout).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func minutes(_ lock: SharedLock) -> Int { max(Int(Date.now.timeIntervalSince(lock.heartbeat) / 60), 1) }

    /// Looks at the lock every couple of seconds. When the other copy lets go, the app starts again and opens the data.
    private func watch() async {
        guard case .heldBy = decision else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            switch SharedDataSession.shared.lookAgain() {
            case .free:
                SharedDataSession.shared.tryAgain()
                return
            case .heldBy(let lock, let stale):
                decision = .heldBy(lock, isStale: stale)
            case .problem(let text):
                decision = .folderProblem(text)
                return
            }
        }
    }
}
