import IthilCore
import SwiftUI

/// The sidebar's "Up next" list: the next few events of visible subjects. The very next one is
/// highlighted in `AccentSoft` with its secondary line in amber ("in 10 min · 14:00 · Room B204").
/// Clicking a row shows its day in the main view and selects the event.
struct SidebarUpNextSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let upNext = model.upNext
        VStack(alignment: .leading, spacing: 2) {
            SidebarSectionLabel(title: "Up next")
            if upNext.isEmpty {
                Text("Nothing coming up")
                    .font(Typography.secondary)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 8)
            } else {
                ForEach(upNext) { occurrence in
                    SidebarUpNextRow(occurrence: occurrence, isNext: occurrence.id == upNext.first?.id)
                }
            }
        }
    }
}

private struct SidebarUpNextRow: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence
    let isNext: Bool
    @State private var isHovered = false

    var body: some View {
        let title = EventFormatting.displayTitle(occurrence.event)
        let parts = EventFormatting.upNextParts(occurrence, now: model.now, math: model.math)
        Button {
            open()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    SubjectDot(subject: model.subject(for: occurrence.event))
                    Text(title)
                        .font(Typography.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                Text(EventFormatting.joined(parts))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(isNext ? Color.accentText : Color.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.Padding.sidebarRow)
            .background {
                RoundedRectangle(cornerRadius: Metrics.Radius.listRow, style: .continuous)
                    .fill(rowFill)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(EventFormatting.spokenJoined([title] + parts))
        .accessibilityHint(Text("Shows the event in the calendar"))
    }

    private var rowFill: Color {
        if isNext { return Color.accentSoft }
        return isHovered ? Color.controlFill : Color.clear
    }

    private func open() {
        model.show(EventFormatting.displayDay(of: occurrence, timeZone: model.timeZone), span: nil)
        model.selectedOccurrenceID = occurrence.id
    }
}
