import SwiftUI

struct DateRangeBar: View {
    @ObservedObject var store: TimeStore
    var showSave = false
    var onSave: (() -> Void)? = nil

    private var palette: Palette { store.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                ZStack(alignment: .leading) {
                    HStack {
                        Text(store.dateRange.rawValue)
                            .foregroundStyle(palette.font)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(palette.font)
                    }
                    .modifier(QuietField(palette: palette))
                    Picker("", selection: $store.dateRange) {
                        ForEach(DateRangeKind.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .labelsHidden()
                    .opacity(0.02)
                }
                Spacer()
                if showSave {
                    Button("Save CSV") { onSave?() }
                        .buttonStyle(SmallActionButtonStyle(color: palette.action))
                }
            }
            if store.dateRange == .chooseDates {
                HStack {
                    DatePicker("", selection: $store.customStart, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    DatePicker("", selection: $store.customEnd, displayedComponents: .date)
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
    @State private var byClientOpen = true

    private var palette: Palette { store.palette }

    private var filtered: [TimeEntry] {
        store.filteredEntries()
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
                .foregroundStyle(palette.quiet)

            DateRangeBar(store: store)
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
                            .foregroundStyle(palette.font)

                            Text(entry.metaLine)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.quiet)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) {
                            palette.line.frame(height: 1)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text(store.dateRange.rawValue)
                Text(DurationFormat.clock(totalSeconds))
                    .monospacedDigit()
                Spacer()
                Button("Time") { store.openTime() }
                    .buttonStyle(.plain)
                Button("Report") { store.openReport() }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 11))
            .foregroundStyle(palette.quiet)
            .padding(.top, 8)
            .overlay(alignment: .top) {
                palette.line.frame(height: 1)
            }
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 400, maxWidth: 400, minHeight: 420)
        .background(palette.window)
        .tint(palette.action)
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
                        DisclosureCaret(open: byClientOpen, color: palette.font)
                        Text("By client")
                    }
                    Spacer()
                    Text(DurationFormat.clock(totalSeconds))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.font)
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
                    .foregroundStyle(palette.font)
                    .padding(.leading, 18)
                    .frame(minHeight: 24)
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            palette.line.frame(height: 1)
        }
    }
}
