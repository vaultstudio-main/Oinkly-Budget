import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Settings ▸ Data & Backup ▸ Encryption. Turning it on, changing the passphrase and the recovery key, remembering the
/// key on this Mac, and turning it off again.
struct EncryptionSection: View {
    private var session: VaultSession { VaultSession.shared }

    @State private var enabling = false
    @State private var changingPassphrase = false
    @State private var makingRecoveryKey = false
    @State private var confirmingOff = false
    @State private var remember = VaultSession.shared.hasRemembered
    @State private var message: String?

    var body: some View {
        Section {
            if VaultSession.isEnabled {
                Label("Your data is encrypted", systemImage: "lock.fill").foregroundStyle(Theme.green)
                if let sealed = session.lastSealed {
                    LabeledContent("Last saved encrypted", value: sealed.formatted(date: .abbreviated, time: .shortened))
                }
                Toggle("Remember on this Mac", isOn: Binding(get: { remember }, set: { remember = $0; session.setRemember($0) }))
                Text("With this on, OinklyBudget opens without asking for the passphrase on this Mac. Turn it off to be asked every time.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Change Passphrase") { changingPassphrase = true }
                    Button("New Recovery Key") { makingRecoveryKey = true }
                    Spacer()
                    Button("Turn Off Encryption", role: .destructive) { confirmingOff = true }
                }
                if let error = session.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
                Text("The encrypted file is saved every couple of minutes, when you hide the app and when you quit. While OinklyBudget is open it works on a readable copy that is removed when you quit, so this protects your data when the app is closed, such as a copied file, a backup or a lost Mac without FileVault. It does not hide it from someone using your Mac while it is unlocked and open.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Encrypt Data").font(.body.weight(.medium))
                        Text("Lock your data with a passphrase so the data file and backups can't be read without it. You get a recovery key to keep somewhere safe. If you lose both the passphrase and the recovery key, nobody can open the data, not even us.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Turn On") { enabling = true }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
        } header: {
            Text("Encryption")
        }
        .sheet(isPresented: $enabling) { EnableEncryptionSheet() }
        .sheet(isPresented: $changingPassphrase) { ChangePassphraseSheet() }
        .sheet(isPresented: $makingRecoveryKey) { NewRecoveryKeySheet() }
        .confirmationDialog("Turn off encryption?", isPresented: $confirmingOff, titleVisibility: .visible) {
            Button("Turn Off and Restart", role: .destructive, action: turnOff)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data goes back to a plain data file on this Mac, and the encrypted copy is removed. You'll be asked for your passphrase first.")
        }
    }

    private func turnOff() {
        guard let passphrase = VaultPrompt.askPassphrase(title: "Turn off encryption", detail: "Enter your passphrase to confirm.", button: "Turn Off") else { return }
        guard session.confirm(passphrase) else { message = "That isn't your passphrase. Nothing was changed."; return }
        message = nil
        let schema = Schema(versionedSchema: PiggybankSchemaV1.self)
        Task {
            do { try await session.turnOff(current: passphrase, localStore: VaultSession.localStoreURL(for: schema)) }
            catch { message = "Couldn't turn off encryption: \(error.localizedDescription)" }
        }
    }
}

// MARK: Turn on

private struct EnableEncryptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var remember = true
    @State private var pending: VaultSession.Pending?
    @State private var saved = false
    @State private var working = false
    @State private var errorMessage: String?

    private var problem: String? {
        if passphrase.count < 8 { return "Use at least 8 characters. A few random words make a strong passphrase that is easy to remember." }
        if passphrase != confirmation { return "The two passphrases don't match." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pending {
                recoveryStep(pending)
            } else {
                passphraseStep
            }
        }
        .padding(22)
        .frame(width: 480)
        .disabled(working)
    }

    private var passphraseStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Encrypt your data").font(.title2.bold())
            Text("Choose a passphrase. You'll type it when OinklyBudget opens, unless you ask this Mac to remember it. There is no way to reset it, so choose one you won't forget.")
                .foregroundStyle(.secondary)
            SecureField("Passphrase", text: $passphrase)
            SecureField("Type it again", text: $confirmation)
            Toggle("Remember on this Mac", isOn: $remember)
            if !passphrase.isEmpty, let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(Theme.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue", action: next)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
    }

    private func recoveryStep(_ pending: VaultSession.Pending) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save your recovery key").font(.title2.bold())
            Text("If you forget your passphrase, this key opens your data. Keep it somewhere safe, such as printed and put away, or in a password manager. It is shown only now.")
                .foregroundStyle(.secondary)
            Text(pending.recoveryKey)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pending.recoveryKey, forType: .string)
                }
                Button("Save as Text File") { saveText(pending.recoveryKey) }
            }
            Toggle("I have saved my recovery key", isOn: $saved)
            Text("OinklyBudget will now encrypt your data and restart. Your current data file is removed only after the encrypted copy opens.")
                .font(.footnote).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(Theme.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Encrypt and Restart") { finish(pending) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!saved)
            }
        }
    }

    private func next() {
        working = true
        errorMessage = nil
        let secret = passphrase
        Task {
            do {
                let made = try await Task.detached { try await VaultSession.shared.prepareEnable(passphrase: secret) }.value
                pending = made
            } catch {
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }

    private func finish(_ pending: VaultSession.Pending) {
        working = true
        errorMessage = nil
        let schema = Schema(versionedSchema: PiggybankSchemaV1.self)
        Task {
            do {
                try await VaultSession.shared.commitEnable(pending, localStore: VaultSession.localStoreURL(for: schema), remember: remember)
            } catch {
                errorMessage = "Couldn't encrypt your data: \(error.localizedDescription) Nothing was changed."
                working = false
            }
        }
    }

    private func saveText(_ key: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "OinklyBudget Recovery Key.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "OinklyBudget recovery key\n\n\(key)\n\nKeep this somewhere safe. With this key, anyone can open your OinklyBudget data.\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: Change passphrase

private struct ChangePassphraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    private var problem: String? {
        if new.count < 8 { return "Use at least 8 characters." }
        if new != confirmation { return "The two new passphrases don't match." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change passphrase").font(.title2.bold())
            SecureField("Current passphrase", text: $current)
            SecureField("New passphrase", text: $new)
            SecureField("Type the new one again", text: $confirmation)
            if !new.isEmpty, let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(Theme.red) }
            Text("Your data isn't re-encrypted, so this is instant. Your recovery key keeps working.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Change Passphrase") {
                    do {
                        try VaultSession.shared.changePassphrase(current: current, to: new)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(current.isEmpty || problem != nil)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

// MARK: New recovery key

private struct NewRecoveryKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var key: String?
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New recovery key").font(.title2.bold())
            if let key {
                Text("Your old recovery key no longer works. Keep this one somewhere safe. It is shown only now.")
                    .foregroundStyle(.secondary)
                Text(key)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(key, forType: .string)
                }
                Toggle("I have saved my recovery key", isOn: $saved)
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).disabled(!saved) }
            } else {
                Text("Enter your passphrase to make a new recovery key. The old one stops working.")
                    .foregroundStyle(.secondary)
                SecureField("Passphrase", text: $current)
                if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(Theme.red) }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Make New Key") {
                        do { key = try VaultSession.shared.newRecoveryKey(current: current) }
                        catch { errorMessage = error.localizedDescription }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(current.isEmpty)
                }
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
