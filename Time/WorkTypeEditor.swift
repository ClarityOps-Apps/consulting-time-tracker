import SwiftUI

struct WorkTypeEditor: View {
    @ObservedObject var store: TimeStore
    var kind: NamedListKind = .workType
    var onDone: () -> Void
    @State private var draft: [Int64: String] = [:]
    @State private var newName = ""

    private var palette: Palette { store.palette }
    private var items: [NamedListItem] { store.items(for: kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Edit list…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.quiet)
                Spacer()
                Button("Done") {
                    commitAll()
                    onDone()
                }
                .buttonStyle(SmallActionButtonStyle(color: palette.action))
            }

            List {
                ForEach(items) { item in
                    HStack {
                        TextField("", text: binding(for: item))
                            .textFieldStyle(.plain)
                            .onSubmit { commit(item) }
                        Button {
                            store.removeItem(item, kind: kind)
                            draft[item.id] = nil
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(palette.quiet)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            HStack {
                TextField("", text: $newName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(palette.wash)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.line, lineWidth: 1)
                    )
                    .onSubmit { add() }
                Button {
                    add()
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(palette.action)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 300, height: 380)
        .background(palette.window)
        .onAppear {
            draft = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.name) })
        }
        .onChange(of: items) { _, rows in
            for item in rows where draft[item.id] == nil {
                draft[item.id] = item.name
            }
        }
        .onDisappear {
            commitAll()
        }
    }

    private func binding(for item: NamedListItem) -> Binding<String> {
        Binding(
            get: { draft[item.id] ?? item.name },
            set: { draft[item.id] = $0 }
        )
    }

    private func add() {
        store.addItem(newName, kind: kind)
        newName = ""
        draft = Dictionary(uniqueKeysWithValues: store.items(for: kind).map { ($0.id, $0.name) })
    }

    private func commit(_ item: NamedListItem) {
        if let name = draft[item.id] {
            store.renameItem(item, to: name, kind: kind)
        }
    }

    private func commitAll() {
        for item in store.items(for: kind) {
            commit(item)
        }
    }
}
