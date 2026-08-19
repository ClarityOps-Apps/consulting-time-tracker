import SwiftUI

struct DateRangeBar: View {
    @ObservedObject var store: TimeStore
    var showSave = false
    var onSave: (() -> Void)? = nil
    @State private var menuOpen = false

    private var palette: Palette { store.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                rangeButton
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
        .zIndex(8)
    }

    private var rangeButton: some View {
        Button {
            menuOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(store.dateRange.rawValue)
                    .foregroundStyle(palette.font)
                Text("▾")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.quiet)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(palette.wash)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if menuOpen {
                rangeMenu
                    .offset(y: 30)
            }
        }
    }

    private var rangeMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(DateRangeKind.allCases) { item in
                if item == .chooseDates {
                    palette.line
                        .frame(height: 1)
                        .padding(.vertical, 4)
                }
                Button {
                    store.dateRange = item
                    menuOpen = false
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: store.dateRange == item ? .bold : .regular))
                        .foregroundStyle(store.dateRange == item ? palette.action : palette.font)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(store.dateRange == item ? palette.actionWash : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 160)
        .padding(.vertical, 4)
        .background(palette.window)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
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

            HStack {
                Text(store.dateRange.rawValue)
                Spacer()
                Text(DurationFormat.clock(totalSeconds))
                    .monospacedDigit()
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
                        Text(byClientOpen ? "▾" : "▸")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.quiet)
                            .frame(width: 12)
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
