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
    @State private var versions: [SharedVersion]?
    @State private var working = false
    @State private var message: String?
    @State private var messageIsError = false

    private var localStore: URL { AppStore.localStoreURL(for: Schema(versionedSchema: OinklyBudgetSchemaV4.self)) }

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
            Text("Sharing")
        } footer: {
            Text(SharedDataSession.isEnabled
                 ? "Other users of this Mac use the same data, one at a time."
                 : "Lets other users of this Mac use your data, one at a time.")
        }
        .alert("Share your data?", isPresented: $warning) {
            Button("Share") { turnOn() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data is copied to /Users/Shared/OinklyBudget. Anyone with an account on this Mac can read it. Your own copy is not changed.")
        }
        .sheet(isPresented: $confirmingStop) {
            StopSharingSheet { removeFolder in turnOff(removeFolder: removeFolder) }
        }
        .sheet(isPresented: Binding(get: { versions != nil }, set: { if !$0 { versions = nil } })) {
            PreviousSavesSheet(versions: versions ?? [])
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
                Text("Share with Other Users").font(.body.weight(.medium))
                Text("Other users of this Mac can open this data, one at a time.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Share…") { warning = true }.disabled(working)
        }
    }

    // MARK: On

    @ViewBuilder
    private var sharing: some View {
        Label("Sharing is on", systemImage: "person.2.fill").foregroundStyle(Theme.green)
        LabeledContent("Folder", value: SharedDataFolder.defaultURL.path)
        if let saved = session.lastSaved {
            LabeledContent("Last saved", value: saved.formatted(date: .abbreviated, time: .shortened))
        }
        if let error = session.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.orange).font(.callout)
        }
        HStack {
            Button("Save Now") { saveNow() }.disabled(working || !session.isActive || session.lostLock)
            Button("Save and Quit") { closeForOthers() }
                .disabled(working || !session.isActive || session.lostLock)
                .help("Saves and quits so another user can open the data")
            Button("Previous Saves…") { showPreviousSaves() }.disabled(working || !session.isActive || session.lostLock)
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
        guard ClosingCountdown.run(.restart, reason: "It restarts to start sharing your data. Finish anything you are doing now.") else { return }
        working = true
        do {
            try session.enable(localStore: localStore, context: modelContext)
        } catch {
            working = false
            show(error.localizedDescription, error: true)
        }
    }

    private func turnOff(removeFolder: Bool) {
        guard ClosingCountdown.run(.restart, reason: "It restarts to stop sharing. Finish anything you are doing now.") else { return }
        working = true
        Task {
            do { try await session.stopSharing(localStore: localStore, removeSharedFolder: removeFolder) }
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
        guard ClosingCountdown.run(.quit, reason: "Your data is saved first, then Oinkly Budget closes so another user can open it.") else { return }
        working = true
        Task { await session.closeForOthers() }
    }

    private func showPreviousSaves() {
        working = true
        Task {
            versions = await session.previousSaves()
            working = false
        }
    }

    private func checkSharing() {
        working = true
        Task {
            report = await session.checkSharing()
            working = false
        }
    }
}

/// The earlier saves, with a way to go back to one.
private struct PreviousSavesSheet: View {
    let versions: [SharedVersion]
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: SharedVersion?
    @State private var restoring = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Previous Saves").font(.title2.bold())
            Text("Each save keeps the one before it. Going back saves what you have now first, so you can return to it.")
                .font(.callout).foregroundStyle(.secondary)
            if versions.isEmpty {
                Text("There are no previous saves yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(versions) { version in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.info.savedAt.formatted(date: .abbreviated, time: .shortened))
                            Text("Saved by \(version.info.savedBy)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Go Back to This…") { chosen = version }.disabled(restoring)
                    }
                }
                .frame(minHeight: 200)
            }
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.orange).font(.callout) }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).disabled(restoring)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .confirmationDialog("Go back to this save?", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible) {
            Button("Go Back and Restart") { restore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let chosen {
                Text("Goes back to \(chosen.info.savedAt.formatted(date: .abbreviated, time: .shortened)). What is open now is saved first. Oinkly Budget restarts.")
            }
        }
    }

    private func restore() {
        guard let version = chosen else { return }
        guard ClosingCountdown.run(.restart, reason: "What is open now is saved first, then Oinkly Budget restarts on the save you chose.") else { return }
        restoring = true
        errorMessage = nil
        Task {
            do { try await SharedDataSession.shared.restore(version) }
            catch {
                errorMessage = "Nothing was changed: \(error.localizedDescription)"
                restoring = false
            }
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
                // The other copy has closed. Say so and count down, rather than restarting out of the blue.
                if ClosingCountdown.run(.restart, reason: "The other copy of Oinkly Budget has closed, so your data can open now.", seconds: 3) {
                    SharedDataSession.shared.tryAgain()
                    return
                }
            case .heldBy(let lock, let stale):
                decision = .heldBy(lock, isStale: stale)
            case .problem(let text):
                decision = .folderProblem(text)
                return
            }
        }
    }
}


/// Asks before sharing stops, and offers to remove the shared folder when nobody else uses it.
private struct StopSharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onStop: (Bool) -> Void

    @State private var others: [SharedOtherUser]?
    @State private var removeFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stop sharing?").font(.title3.weight(.semibold))
            Text("This Mac keeps a copy of the latest data. Other users keep sharing.")
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Also remove the shared folder", isOn: $removeFolder)
                    .disabled(others?.isEmpty != true)
                if let others {
                    if others.isEmpty {
                        Text("Moves \(SharedDataFolder.defaultURL.path) to the Trash, with its saved history. Choose this when you are the last one using it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Not available: " + others.prefix(3).map { "\($0.name) \($0.why) (\($0.lastSeen.formatted(date: .abbreviated, time: .omitted)))" }.joined(separator: "; ")
                             + ". The folder stays so they can keep using it. The last person to stop sharing can remove it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Checking who else uses it…").font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Stop Sharing") {
                    let remove = removeFolder && others?.isEmpty == true
                    dismiss()
                    onStop(remove)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            let user = NSUserName(), full = NSFullUserName()
            others = await Task.detached { SharedDataFolder.standard.otherUsers(besides: user, fullName: full) }.value
        }
    }
}
