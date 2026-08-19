import SwiftUI
import AppKit

enum Theme {
    static let font = Color(red: 32 / 255, green: 57 / 255, blue: 66 / 255)
    static let action = Color(red: 246 / 255, green: 93 / 255, blue: 54 / 255)
    static let quiet = Color(red: 68 / 255, green: 115 / 255, blue: 132 / 255)
    static let window = Color(red: 254 / 255, green: 254 / 255, blue: 254 / 255)
    static let wash = Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
    static let line = Color(red: 32 / 255, green: 57 / 255, blue: 66 / 255).opacity(0.12)

    static let nsWindow = NSColor(calibratedRed: 254 / 255, green: 254 / 255, blue: 254 / 255, alpha: 1)
}

enum DurationFormat {
    /// Clock and totals: always hours and minutes, never decimal hours. "0h 00m", "1h 24m".
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    /// History row duration: "45m" when under an hour, otherwise "1h 24m" / "3h 00m".
    static func entry(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    /// Menu bar: "1:24" / "0:00".
    static func menuBar(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours):\(String(format: "%02d", minutes))"
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
            .background(Theme.action.opacity(configuration.isPressed ? 0.88 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SmallActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Theme.action.opacity(configuration.isPressed ? 0.88 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct QuietField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13))
            .foregroundStyle(Theme.font)
            .padding(.horizontal, 8)
            .frame(width: 148, height: 24, alignment: .leading)
            .background(Theme.wash)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
