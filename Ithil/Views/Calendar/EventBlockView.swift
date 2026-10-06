import IthilCore
import SwiftUI

/// One timed event in the Day or Week grid: the subject fill and border (radius 6), the title in the
/// subject's readable color on up to two lines, and the time range when the block is tall enough. Past
/// events are dimmed and the selected one gets the amber ring and glow. Click, double-click, Return and
/// VoiceOver come from `eventInteraction`.
struct EventBlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    let item: DayLayout.Item
    let arrowEdge: Edge
    /// Whether this block opens Quick Add's editor for its occurrence: only one segment of an event drawn
    /// across several days does, the first one on screen.
    let handlesPendingEditor: Bool

    var body: some View {
        let occurrence = item.occurrence
        let subject = model.subject(for: occurrence.event)
        let isSelected = model.selectedOccurrenceID == occurrence.id
        let density = EventBlockDensity(height: TimeGridGeometry.height(of: item) - TimeGridGeometry.blockGap)
        EventBlockLabel(occurrence: occurrence, subject: subject, density: density)
            .background {
                EventShapeBackground(subject: subject, isSelected: isSelected)
            }
            .opacity(CalendarEventStyle.opacity(for: occurrence, now: model.now, contrast: contrast))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.Radius.eventBlock, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(EventFormatting.accessibilityLabel(occurrence, timeZone: model.timeZone))
            .accessibilityAddTraits(CalendarEventStyle.traits(isSelected: isSelected))
            .eventInteraction(occurrence: occurrence, arrowEdge: arrowEdge, handlesPendingEditor: handlesPendingEditor)
    }
}

/// How much an event block has room for.
private enum EventBlockDensity {
    /// The title on one line (blocks shorter than about 45 minutes).
    case compact
    /// The title on one line, then the time range.
    case regular
    /// The title on up to two lines, then the time range (about 75 minutes and longer).
    case roomy

    init(height: CGFloat) {
        if height < 34 {
            self = .compact
        } else if height < 50 {
            self = .regular
        } else {
            self = .roomy
        }
    }
}

/// The text of a block. Phase 4 adds the paperclip and file count after the time range.
private struct EventBlockLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let occurrence: Occurrence
    let subject: Subject?
    let density: EventBlockDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(EventFormatting.displayTitle(occurrence.event))
                .font(Typography.eventTitle)
                .foregroundStyle(SubjectStyle.text(for: subject, scheme: colorScheme))
                .lineLimit(density == .roomy ? 2 : 1)
                .truncationMode(.tail)
            if density != .compact {
                Text(EventFormatting.timeRange(occurrence, timeZone: model.timeZone))
                    .font(Typography.eventTime)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, density == .compact ? 1 : 3)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}
