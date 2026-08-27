import SwiftUI

struct ColorsView: View {
    @ObservedObject var store: TimeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Colors")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.palette.quiet)

            Text("Other people change these to match their own look.")
                .font(.system(size: 12))
                .foregroundStyle(store.palette.quiet)
                .padding(.top, 8)
                .padding(.bottom, 14)

            well("Font", hex: store.palette.fontHex, color: $store.palette.fontHex, lined: false)
            well("Action", hex: store.palette.actionHex, color: $store.palette.actionHex)
            well("Quiet", hex: store.palette.quietHex, color: $store.palette.quietHex)
            well("Window", hex: store.palette.windowHex, color: $store.palette.windowHex)
            well("Minutes", hex: store.palette.minutesHex, color: $store.palette.minutesHex)

            harvestBlock
                .padding(.top, 16)
        }
        .padding(16)
        .frame(width: 280)
        .background(store.palette.window)
        .onChange(of: store.palette) { _, _ in
            store.persistPalette()
        }
    }

    private var harvestBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Harvest")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(store.palette.quiet)

            if store.harvestConnected {
                Text("Connected")
                    .font(.system(size: 13))
                    .foregroundStyle(store.palette.font)
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
                }
            } else {
                Text("Token from id.getharvest.com/developers")
                    .font(.system(size: 12))
                    .foregroundStyle(store.palette.quiet)
                labeledField("Account ID", text: $store.harvestAccountID, secure: false)
                labeledField("Personal access token", text: $store.harvestToken, secure: true)
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
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            store.palette.line.frame(height: 1)
        }
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

    private func well(_ name: String, hex: String, color: Binding<String>, lined: Bool = true) -> some View {
        HStack(spacing: 12) {
            ColorPicker("", selection: Binding(
                get: { Color(rgbHex: color.wrappedValue) },
                set: { color.wrappedValue = $0.rgbHex }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.palette.font)
                Text("#\(hex)")
                    .font(.system(size: 11))
                    .foregroundStyle(store.palette.quiet)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            if lined {
                store.palette.line.frame(height: 1)
            }
        }
    }
}
