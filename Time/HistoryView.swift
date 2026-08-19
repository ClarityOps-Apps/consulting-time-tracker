import SwiftUI

struct DateRangeBar: View {
    @Binding var range: DateRangeKind
    @Binding var customStart: Date
    @Binding var customEnd: Date
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $range) {
                    ForEach(DateRangeKind.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180, alignment: .leading)

                Spacer()
                if let trailing {
                    trailing
                }
            }
            if range == .chooseDates {
                HStack {
                    DatePicker("", selection: $customStart, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    DatePicker("", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Spacer()
                }
            }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var store: TimeStore
    @State private var range: DateRangeKind = .thisWeek
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var byClientOpen = true

    private var filtered: [TimeEntry] {
        store.entries(in: range, customStart: customStart, customEnd: customEnd)
    }

    private var totalSeconds: Int {
        filtered.reduce(0) { $0 + $1.durationSeconds }
    }

    private var clientTotals: [ClientTotal] {
        ReportRollup.clients(from: filtered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.quiet)

            DateRangeBar(range: $range, customStart: $customStart, customEnd: $customEnd)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    byClientBlock
                    ForEach(filtered) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(historyDateLabel(entry.startedAt))
                                Spacer()
                                Text(DurationFormat.entry(entry.durationSeconds))
                                    .monospacedDigit()
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.font)

                            Text(entry.metaLine)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.quiet)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) {
                            Theme.line.frame(height: 1)
                        }
                    }
                }
            }

            HStack {
                Text(range.rawValue)
                Spacer()
                Text(DurationFormat.clock(totalSeconds))
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.quiet)
            .padding(.top, 8)
            .overlay(alignment: .top) {
                Theme.line.frame(height: 1)
            }
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 400, maxWidth: 400, minHeight: 420)
        .background(Theme.window)
    }

    private var byClientBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    byClientOpen.toggle()
                }
            } label: {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: byClientOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.quiet)
                            .frame(width: 12)
                        Text("By client")
                    }
                    Spacer()
                    Text(DurationFormat.clock(totalSeconds))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.font)
                .frame(minHeight: 26)
            }
            .buttonStyle(.plain)

            if byClientOpen {
                ForEach(clientTotals) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(DurationFormat.clock(row.seconds))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.font)
                    .padding(.leading, 18)
                    .frame(minHeight: 24)
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Theme.line.frame(height: 1)
        }
    }
}
