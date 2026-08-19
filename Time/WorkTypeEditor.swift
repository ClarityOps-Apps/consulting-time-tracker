import SwiftUI

struct WorkTypeEditor: View {
    @ObservedObject var store: TimeStore
    var onDone: () -> Void
    @State private var draft: [Int64: String] = [:]
    @State private var newName = ""

    private var palette: Palette { store.palette }

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
                ForEach(store.workTypes) { item in
                    HStack {
                        TextField("", text: binding(for: item))
                            .textFieldStyle(.plain)
                            .onSubmit { commit(item) }
                        Button {
                            store.removeWorkType(item)
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
            draft = Dictionary(uniqueKeysWithValues: store.workTypes.map { ($0.id, $0.name) })
        }
        .onChange(of: store.workTypes) { _, items in
            for item in items where draft[item.id] == nil {
                draft[item.id] = item.name
            }
        }
        .onDisappear {
            commitAll()
        }
    }

    private func binding(for item: WorkTypeItem) -> Binding<String> {
        Binding(
            get: { draft[item.id] ?? item.name },
            set: { draft[item.id] = $0 }
        )
    }

    private func add() {
        store.addWorkType(newName)
        newName = ""
        draft = Dictionary(uniqueKeysWithValues: store.workTypes.map { ($0.id, $0.name) })
    }

    private func commit(_ item: WorkTypeItem) {
        if let name = draft[item.id] {
            store.renameWorkType(item, to: name)
        }
    }

    private func commitAll() {
        for item in store.workTypes {
            commit(item)
        }
    }
}
