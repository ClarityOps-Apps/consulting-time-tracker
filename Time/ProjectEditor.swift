import SwiftUI

struct ProjectEditor: View {
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
                ForEach(store.visibleProjects) { item in
                    HStack {
                        TextField("", text: binding(for: item))
                            .textFieldStyle(.plain)
                            .onSubmit { commit(item) }
                        Button("Archive") {
                            commit(item)
                            store.archiveProject(item)
                            draft[item.id] = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.quiet)
                    }
                }

                if !store.archivedProjects.isEmpty {
                    ForEach(store.archivedProjects) { item in
                        HStack {
                            TextField("", text: binding(for: item))
                                .textFieldStyle(.plain)
                                .onSubmit { commit(item) }
                            Button("Unhide") {
                                commit(item)
                                store.unhideProject(item)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.quiet)
                        }
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
            draft = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0.name) })
        }
        .onChange(of: store.projects) { _, items in
            for item in items where draft[item.id] == nil {
                draft[item.id] = item.name
            }
        }
        .onDisappear {
            commitAll()
        }
    }

    private func binding(for item: ProjectItem) -> Binding<String> {
        Binding(
            get: { draft[item.id] ?? item.name },
            set: { draft[item.id] = $0 }
        )
    }

    private func add() {
        store.addProject(newName)
        newName = ""
        draft = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0.name) })
    }

    private func commit(_ item: ProjectItem) {
        if let name = draft[item.id] {
            store.renameProject(item, to: name)
        }
    }

    private func commitAll() {
        for item in store.projects {
            commit(item)
        }
    }
}
