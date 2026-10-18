import SwiftUI
import AppKit
import SwiftData

/// Shown in place of the usual start-up checks when the shared data file can't simply be opened: someone else has it,
/// the folder is missing, or something went wrong. Nothing is opened, and nothing is changed, until a choice is made.
struct SharedFileDecisionView: View {
    let decision: SharedDataSession.Decision
    private let session = SharedDataSession.shared

    var body: some View {
        ZStack {
            Brand.gradient.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("BootPig").resizable().scaledToFit().frame(height: 70)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                Spacer(minLength: 0)
                VStack(spacing: 10) { buttons }
                    .controlSize(.large)
                    .padding(.bottom, 24)
            }
            .padding(.top, 30)
        }
    }

    private var title: String {
        switch decision {
        case .heldBy(let lock, _): "\(lock.fullName.isEmpty ? lock.userName : lock.fullName) has the data open"
        case .folderMissing: "The shared folder can't be found"
        case .failed: "The shared data couldn't be opened"
        }
    }

    private var message: String {
        switch decision {
        case .heldBy(let lock, let stale):
            let since = lock.since.formatted(date: .abbreviated, time: .shortened)
            let who = lock.fullName.isEmpty ? lock.userName : lock.fullName
            if stale {
                return "\(who) has had it open since \(since), but their OinklyBudget hasn't checked in for a while, so it may have closed unexpectedly. Taking over uses what they last saved; anything they hadn't saved is lost."
            }
            return "\(who) has had it open since \(since). Only one person can change it at a time. You can look at it without changing it, or wait until they close it."
        case .folderMissing:
            return "The folder you share data through isn't there. It may be on a drive that isn't connected, or it was moved. Your own data on this Mac is untouched."
        case .failed(let reason):
            return reason
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch decision {
        case .heldBy(_, let stale):
            HStack(spacing: 10) {
                Button("Open to Look Only") { session.resolve(readOnly: true) }
                if stale { Button("Take Over") { session.resolve(takeOver: true) } }
            }
            HStack(spacing: 10) {
                Button("Try Again") { SharedDataSession.relaunch() }
                Button("Use This Mac's Data") { session.useThisMacsData() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        case .folderMissing:
            HStack(spacing: 10) {
                Button("Choose Folder") { chooseFolder() }
                Button("Try Again") { SharedDataSession.relaunch() }
            }
            HStack(spacing: 10) {
                Button("Use This Mac's Data") { session.useThisMacsData() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        case .failed:
            HStack(spacing: 10) {
                Button("Try Again") { SharedDataSession.relaunch() }
                Button("Use This Mac's Data") { session.useThisMacsData() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func chooseFolder() {
        guard let container = PiggybankAppDelegate.container else { return }
        session.chooseFolderAndEnable(currentStore: nil, context: container.mainContext)
    }
}
