import SwiftUI
import SwiftData

/// A small colored label for a tag.
struct TagChip: View {
    let name: String
    let colorHex: String
    var onRemove: (() -> Void)?

    var body: some View {
        let color = Color(hex: colorHex)
        HStack(spacing: 4) {
            Text(name).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .help("Remove this tag")
                    .accessibilityLabel("Remove tag \(name)")
            }
        }
        .accessibilityElement(children: onRemove == nil ? .ignore : .contain)
        .accessibilityLabel("Tag \(name)")
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.18), in: Capsule())
        .fixedSize()
    }
}

/// A transaction's tags in the register: the first few, then "+N" for the rest.
struct TagChips: View {
    let transaction: Transaction
    var limit = 2

    var body: some View {
        let tags = transaction.sortedTags
        HStack(spacing: 4) {
            ForEach(tags.prefix(limit)) { TagChip(name: $0.name, colorHex: $0.colorHex) }
            if tags.count > limit {
                Text("+\(tags.count - limit)").font(.caption).foregroundStyle(.secondary)
                    .help(tags.dropFirst(limit).map(\.name).joined(separator: ", "))
            }
        }
    }
}

/// Lays chips out in lines, starting a new line when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The Tags row in New Transaction and Edit Transaction. It works on names, so nothing is created until the
/// transaction is saved: pick an existing tag from the menu, or type a new one and press Return.
struct TagField: View {
    @Binding var names: [String]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newName = ""

    private var available: [Tag] {
        allTags.live.filter { tag in !names.contains { Tags.key($0) == Tags.key(tag.name) } }
    }

    private func colorHex(for name: String) -> String {
        Tags.find(name, in: allTags.live)?.colorHex ?? Tags.palette[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !names.isEmpty {
                FlowLayout {
                    ForEach(names, id: \.self) { name in
                        TagChip(name: name, colorHex: colorHex(for: name)) { names.removeAll { $0 == name } }
                    }
                }
            }
            HStack {
                TextField("Tags", text: $newName, prompt: Text("Add a tag, then press Return"))
                    .labelsHidden()
                    .onSubmit(add)
                if !Tags.clean(newName).isEmpty {
                    Button("Add", action: add)
                }
                if !available.isEmpty {
                    Menu("Existing") {
                        ForEach(available) { tag in
                            Button(tag.name) { names.append(tag.name) }
                        }
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
            }
        }
    }

    private func add() {
        let cleaned = Tags.clean(newName)
        newName = ""
        guard !cleaned.isEmpty, !names.contains(where: { Tags.key($0) == Tags.key(cleaned) }) else { return }
        // Use the spelling of a tag that already exists.
        names.append(Tags.find(cleaned, in: allTags.live)?.name ?? cleaned)
    }
}

/// Settings ▸ Tags: rename, recolor, merge and delete.
struct TagsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var newName = ""
    @State private var deleting: Tag?
    @State private var message: String?

    private var tags: [Tag] { allTags.live }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Labels you can put on any transaction, such as Vacation or Reimbursable. Tag a transaction in New Transaction or Edit Transaction, or right-click it in a register. Reports can be filtered by a tag.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("New tag", text: $newName, prompt: Text("New tag name"))
                    .onSubmit(add)
                Button("Add Tag", action: add)
                    .disabled(Tags.clean(newName).isEmpty)
            }

            if tags.isEmpty {
                ContentUnavailableView("No Tags Yet", systemImage: "tag", description: Text("Add one above, or type a new tag when you enter a transaction."))
            } else {
                List {
                    ForEach(tags) { tag in
                        TagRow(tag: tag, others: tags.filter { $0 !== tag }, onDelete: { deleting = tag }, onMessage: { message = $0 })
                    }
                }
            }
            if let message { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.callout) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(deleting.map { "Delete the tag “\($0.name)”?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Tag", role: .destructive) {
                if let tag = deleting { Tags.delete(tag, in: modelContext) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            if let tag = deleting {
                Text("It comes off \(tag.transactions.live.count) transaction\(tag.transactions.live.count == 1 ? "" : "s"). The transactions stay.")
            }
        }
    }

    private func add() {
        let cleaned = Tags.clean(newName)
        guard !cleaned.isEmpty else { return }
        newName = ""
        if Tags.find(cleaned, in: tags) != nil { message = "“\(cleaned)” already exists."; return }
        _ = Tags.resolve([cleaned], in: modelContext)
        modelContext.saveNow()
        message = nil
    }
}

private struct TagRow: View {
    @Environment(\.modelContext) private var modelContext
    let tag: Tag
    let others: [Tag]
    let onDelete: () -> Void
    let onMessage: (String) -> Void
    @State private var name = ""
    @State private var choosingColor = false

    var body: some View {
        HStack(spacing: 10) {
            Button { choosingColor = true } label: {
                Circle().fill(Color(hex: tag.colorHex)).frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Change the color")
            .accessibilityLabel("Change the color of \(tag.name)")
            .popover(isPresented: $choosingColor, arrowEdge: .bottom) {
                HStack(spacing: 8) {
                    ForEach(Tags.palette, id: \.self) { hex in
                        Button {
                            tag.colorHex = hex
                            modelContext.saveNow()
                            choosingColor = false
                        } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                                .overlay { if hex == tag.colorHex { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }

            TextField("Name", text: $name)
                .labelsHidden()
                .onSubmit(rename)
            Text("\(tag.transactions.live.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Transactions with this tag")
            if !others.isEmpty {
                Menu("Merge Into") {
                    ForEach(others) { target in
                        Button(target.name) {
                            Tags.merge(tag, into: target, in: modelContext)
                            onMessage("Merged into “\(target.name)”.")
                        }
                    }
                }
                .fixedSize()
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this tag")
                .accessibilityLabel("Delete tag \(tag.name)")
        }
        .onAppear { name = tag.name }
    }

    private func rename() {
        let cleaned = Tags.clean(name)
        guard !cleaned.isEmpty else { name = tag.name; return }
        if let clash = Tags.find(cleaned, in: others) {
            onMessage("“\(clash.name)” already exists. Use Merge Into to combine them.")
            name = tag.name
            return
        }
        tag.name = cleaned
        name = cleaned
        modelContext.saveNow()
    }
}
