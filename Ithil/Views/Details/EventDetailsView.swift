import IthilCore
import SwiftUI

/// The event details popover: subject, title in New York 22 pt, day and time, then location, alert and
/// repeat rows (only those that apply), the notes, and Delete / Edit.
///
/// It shows the occurrence as it is in the library now, so edits made elsewhere appear at once. Delete
/// asks first (and which occurrences, for a repeating event), then calls `onClose`; Edit calls `onEdit`.
struct EventDetailsView: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence
    let onEdit: () -> Void
    let onClose: () -> Void
    @State private var showsDeleteConfirmation = false

    var body: some View {
        let current = model.occurrence(id: occurrence.id) ?? occurrence
        let context = EventChangeContext(occurrence: current, timeZone: model.timeZone)
        VStack(alignment: .leading, spacing: 14) {
            EventDetailsHeader(occurrence: current)
            EventDetailsInfo(event: current.event)
            if !current.event.notes.isEmpty {
                Text(current.event.notes)
                    .font(Typography.body)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text("Notes"))
                    .accessibilityValue(Text(current.event.notes))
            }
            Rectangle()
                .fill(Color.separatorLine)
                .frame(height: 1)
                .accessibilityHidden(true)
            footer
        }
        .padding(Metrics.Padding.popover)
        .frame(width: 320, alignment: .leading)
        .background(Color.backgroundRaised)
        .onDeleteCommand {
            requestDelete()
        }
        .confirmsEventChange(.delete, isPresented: $showsDeleteConfirmation, context: context) { scope in
            model.delete(current, scope: scope)
            onClose()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                requestDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .help("Delete Event")
            Spacer(minLength: 8)
            Button("Edit", action: onEdit)
                .keyboardShortcut(.defaultAction)
                .help("Edit Event")
        }
        .disabled(!model.canEdit)
    }

    private func requestDelete() {
        guard model.canEdit else { return }
        showsDeleteConfirmation = true
    }
}

/// The subject label (dot + name in the subject's color, 11 pt), the title and "Tuesday, 6 October ·
/// 14:00 – 15:30".
private struct EventDetailsHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let occurrence: Occurrence

    var body: some View {
        let subject = model.subject(for: occurrence.event)
        VStack(alignment: .leading, spacing: 4) {
            if let subject {
                HStack(spacing: 6) {
                    SubjectDot(subject: subject, size: 7)
                    Text(subject.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SubjectStyle.text(for: subject, scheme: colorScheme))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Subject: \(subject.name)"))
            }
            Text(EventFormatting.displayTitle(occurrence.event))
                .font(Typography.detailTitle)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            Text(EventFormatting.dayAndTime(occurrence, timeZone: model.timeZone))
                .font(Typography.secondary)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// `mappin` location, `bell` alert and `repeat` rule rows, each only when the event has one.
private struct EventDetailsInfo: View {
    @Environment(AppModel.self) private var model
    let event: Event

    var body: some View {
        let location = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let recurrence = EventFormatting.recurrence(event, timeZone: model.timeZone)
        if !location.isEmpty || event.alert != nil || recurrence != nil {
            VStack(alignment: .leading, spacing: 7) {
                if !location.isEmpty {
                    EventDetailsRow(systemImage: "mappin", label: "Location", value: location)
                }
                if let alert = event.alert {
                    EventDetailsRow(systemImage: "bell", label: "Alert", value: EventFormatting.alert(alert))
                }
                if let recurrence {
                    EventDetailsRow(systemImage: "repeat", label: "Repeats", value: recurrence)
                }
            }
        }
    }
}

private struct EventDetailsRow: View {
    let systemImage: String
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(value)
                .font(Typography.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}
