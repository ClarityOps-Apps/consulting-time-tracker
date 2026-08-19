import SwiftUI

struct WorkTypeEditor: View {
    @ObservedObject var store: TimeStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [Int64: String] = [:]
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work type")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.quiet)

            Text("Starter names. Add, rename, or remove. This list is yours.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.quiet)

            List {
                ForEach(store.workTypes) { item in
                    HStack {
                        TextField("Name", text: binding(for: item))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commit(item) }
                        Button {
                            store.removeWorkType(item)
                            draft[item.id] = nil
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                TextField("Add", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Add") { add() }
            }

            HStack {
                Spacer()
                Button("Done") {
                    commitAll()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300, height: 380)
        .background(Theme.window)
        .onAppear {
            draft = Dictionary(uniqueKeysWithValues: store.workTypes.map { ($0.id, $0.name) })
        }
        .onChange(of: store.workTypes) { _, items in
            for item in items where draft[item.id] == nil {
                draft[item.id] = item.name
            }
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
