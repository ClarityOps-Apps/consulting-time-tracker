import SwiftUI

struct HarvestView: View {
    @ObservedObject var store: TimeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Harvest")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.palette.quiet)

            if store.harvestConnected {
                Text("Connected")
                    .font(.system(size: 13))
                    .foregroundStyle(store.palette.font)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                HStack(spacing: 8) {
                    Button("Disconnect") {
                        store.disconnectHarvest()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.palette.quiet)
                    .disabled(store.harvestBusy)
                    Button("Pull") {
                        store.pullHarvest()
                    }
                    .buttonStyle(SmallActionButtonStyle(color: store.palette.action))
                    .disabled(store.harvestBusy)
                    Button("Send") {
                        store.sendHarvest()
                    }
                    .buttonStyle(SmallActionButtonStyle(color: store.palette.action))
                    .disabled(store.harvestBusy)
                }
            } else {
                Text("Token from id.getharvest.com/developers")
                    .font(.system(size: 12))
                    .foregroundStyle(store.palette.quiet)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                labeledField("Account ID", text: $store.harvestAccountID, secure: false)
                    .padding(.bottom, 8)
                labeledField("Personal access token", text: $store.harvestToken, secure: true)
                    .padding(.bottom, 14)
                Button("Connect") {
                    store.connectHarvest()
                }
                .buttonStyle(SmallActionButtonStyle(color: store.palette.action))
                .disabled(store.harvestBusy)
            }

            if !store.harvestNote.isEmpty {
                Text(store.harvestNote)
                    .font(.system(size: 12))
                    .foregroundStyle(store.palette.quiet)
                    .padding(.top, 12)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(store.palette.window)
    }

    private func labeledField(_ name: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(store.palette.font)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(store.palette.font)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(store.palette.wash)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(store.palette.line, lineWidth: 1)
            )
            .disabled(store.harvestBusy)
        }
    }
}
