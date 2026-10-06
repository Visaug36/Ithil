import IthilCore
import SwiftUI

/// The Quick Add panel's content: a crescent and the input, a preview of the event Return would add, and
/// a footer with the matched subject and the key hints.
struct QuickAddView: View {
    @Bindable var session: QuickAddSession

    var body: some View {
        let draft = session.draft
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.panel, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                QuickAddTextField(
                    text: $session.text, highlightedRanges: draft?.highlightedRanges ?? [],
                    placeholder: String(localized: "Add an event, like “physics quiz thursday 10am”"),
                    onSubmit: { session.submit(openingEditor: false) }, onCancel: { session.cancel() })
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
            QuickAddPreviewRow(draft: draft)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            QuickAddFooter(draft: draft)
        }
        .frame(width: 520)
        .background(Color.backgroundRaised, in: shape)
        .overlay {
            shape.strokeBorder(Color.separatorLine, lineWidth: 1)
        }
        .clipShape(shape)
    }
}

/// The event Return would add: subject dot, title (or "New Event") over its day and time, and capsules
/// for the subject and the alert.
private struct QuickAddPreviewRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let draft: QuickAddDraft?

    var body: some View {
        let subject = model.library.subject(withID: draft?.subjectID)
        HStack(spacing: 10) {
            SubjectDot(subject: subject, size: 9)
            VStack(alignment: .leading, spacing: 2) {
                title
                subtitle
            }
            Spacer(minLength: 8)
            if let subject {
                Text(subject.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SubjectStyle.text(for: subject, scheme: colorScheme))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SubjectStyle.fill(for: subject, scheme: colorScheme), in: Capsule())
            }
            if let alert = draft?.alert {
                Label(EventFormatting.alert(alert), systemImage: "bell")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.controlFill, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var title: some View {
        let typed = draft?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if typed.isEmpty {
            Text("New Event")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        } else {
            Text(typed)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var subtitle: some View {
        if let draft {
            Text(dayAndTime(of: draft))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        } else {
            Text("Type what it is, the day and the time.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
    }

    /// "Thursday, 8 October · 10:00 – 11:00", as the calendar will show the event.
    private func dayAndTime(of draft: QuickAddDraft) -> String {
        let event = Event(title: draft.title, timing: draft.timing)
        let expander = OccurrenceExpander(displayTimeZone: model.timeZone)
        guard let occurrence = expander.occurrence(of: event, on: draft.timing.startDate) else { return "" }
        return EventFormatting.dayAndTime(occurrence, timeZone: model.timeZone)
    }
}

/// "Subject matched from “physics”" on the left, "↩ Add  ⌘↩ Add and edit  esc Close" on the right.
private struct QuickAddFooter: View {
    @Environment(AppModel.self) private var model
    let draft: QuickAddDraft?

    var body: some View {
        HStack(spacing: 14) {
            if let keyword = draft?.matchedKeyword {
                Text("Subject matched from “\(keyword)”")
            } else if !model.canEdit {
                Text("Open your calendar in Ithil to add events.")
            }
            Spacer(minLength: 8)
            Text("↩ Add")
            Text("⌘↩ Add and edit")
            Text("esc Close")
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.textTertiary)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.separatorLine)
                .frame(height: 1)
        }
    }
}
