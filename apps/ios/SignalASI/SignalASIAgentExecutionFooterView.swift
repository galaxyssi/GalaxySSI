import SwiftUI

struct SignalASIAgentExecutionFooterView: View {
  @State private var detailsExpanded = false

  var executor: String
  var status: String
  var location: String
  var step: String
  var duration: String
  var details: [String]
  var detailsTitle: String
  var timelineActions: [AgentExecutionLoopTimelineAction] = []
  var timelineActionTitle: (AgentExecutionLoopTimelineAction) -> String = { $0.rawValue }
  var timelineActionIcon: (AgentExecutionLoopTimelineAction) -> String = { _ in "ellipsis" }
  var timelineActionMenuTitle: String = "Task controls"
  var onTimelineAction: (AgentExecutionLoopTimelineAction) -> Void = { _ in }
  var canCancel: Bool = false
  var cancelTitle: String = "Cancel task"
  var onCancel: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 7) {
        SignalASIAgentRouteLogo(label: executor, size: 16)
        Text(executor)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text(status)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.signalASIAccent)
          .lineLimit(1)
      }

      Text(metadataLine)
        .font(.system(size: 10))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      if !details.isEmpty {
        Button {
          detailsExpanded.toggle()
        } label: {
          Label(
            detailsTitle,
            systemImage: detailsExpanded ? "chevron.up" : "chevron.down"
          )
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.signalASIInsightText)
        }
        .buttonStyle(.plain)

        if detailsExpanded {
          VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(details.suffix(4).enumerated()), id: \.offset) { _, detail in
              Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.signalASITextSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.leading, 4)
        }
      }
      if canCancel || !timelineActions.isEmpty {
        HStack(spacing: 8) {
          if canCancel {
            Button(role: .destructive, action: onCancel) {
              Label(cancelTitle, systemImage: "xmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .frame(minHeight: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text(cancelTitle))
          }
          if !timelineActions.isEmpty {
            Menu {
              ForEach(timelineActions) { action in
                Button {
                  onTimelineAction(action)
                } label: {
                  Label(timelineActionTitle(action), systemImage: timelineActionIcon(action))
                }
              }
            } label: {
              Label("", systemImage: "ellipsis.circle")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 42, height: 30)
            }
            .menuStyle(.borderedButton)
            .accessibilityLabel(Text(timelineActionMenuTitle))
          }
        }
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASISurface.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  private var metadataLine: String {
    [location, step, duration]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }
}
