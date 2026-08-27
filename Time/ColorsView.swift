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
        }
        .padding(16)
        .frame(width: 280)
        .background(store.palette.window)
        .onChange(of: store.palette) { _, _ in
            store.persistPalette()
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
