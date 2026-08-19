import SwiftUI
import AppKit

struct Palette: Equatable {
    static let defaultFont = "203942"
    static let defaultAction = "F65D36"
    static let defaultQuiet = "447384"
    static let defaultWindow = "FEFEFE"
    static let defaultMinutes = "F65D36"

    var fontHex = defaultFont
    var actionHex = defaultAction
    var quietHex = defaultQuiet
    var windowHex = defaultWindow
    var minutesHex = defaultMinutes

    var font: Color { Color(rgbHex: fontHex) }
    var action: Color { Color(rgbHex: actionHex) }
    var quiet: Color { Color(rgbHex: quietHex) }
    var window: Color { Color(rgbHex: windowHex) }
    var minutes: Color { Color(rgbHex: minutesHex) }
    var wash: Color { Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255) }
    var line: Color { font.opacity(0.12) }
    var actionWash: Color { action.opacity(0.10) }

    var nsWindow: NSColor { NSColor(rgbHex: windowHex) }
}

enum Theme {
    static let defaults = Palette()
}

extension Color {
    init(rgbHex: String) {
        var hex = rgbHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var rgbHex: String {
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return "000000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

extension NSColor {
    convenience init(rgbHex: String) {
        var hex = rgbHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum DurationFormat {
    /// Clock and totals: always hours and minutes. "0h 00m", "1h 24m", "8h 34m".
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    /// History / nested rows: "45m" under an hour, otherwise "1h 24m" / "3h 00m".
    static func entry(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    /// Menu bar elapsed: H:MM ("1:24").
    static func menuBar(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours):\(String(format: "%02d", minutes))"
    }
}

struct ActionButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
            .contentShape(Rectangle())
            .background(color.opacity(configuration.isPressed ? 0.88 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SmallActionButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(color.opacity(configuration.isPressed ? 0.88 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct QuietField: ViewModifier {
    var palette: Palette

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13))
            .foregroundStyle(palette.font)
            .padding(.horizontal, 8)
            .frame(width: 148, height: 24, alignment: .leading)
            .background(palette.wash)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct LookCheckbox: View {
    @Binding var isOn: Bool
    var palette: Palette

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? palette.action : palette.window)
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isOn ? palette.action : palette.quiet, lineWidth: 1.5)
                    )
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

func historyDateLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE d MMM"
    return formatter.string(from: date)
}

func displayName(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "—" : trimmed
}

func statusClockImage() -> NSImage {
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size, flipped: true) { _ in
        let circle = NSBezierPath(ovalIn: NSRect(x: 2.6, y: 2.8, width: 10.8, height: 10.8))
        circle.lineWidth = 1.4
        NSColor.black.setStroke()
        circle.stroke()
        let hands = NSBezierPath()
        hands.move(to: NSPoint(x: 8, y: 5.6))
        hands.line(to: NSPoint(x: 8, y: 8.6))
        hands.line(to: NSPoint(x: 10, y: 9.8))
        hands.lineWidth = 1.4
        hands.lineCapStyle = .round
        hands.lineJoinStyle = .round
        hands.stroke()
        return true
    }
    image.isTemplate = true
    return image
}


struct DisclosureCaret: View {
    var open: Bool
    var color: Color

    var body: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 6, weight: .bold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(open ? 0 : -90))
            .frame(width: 12)
    }
}
