import SwiftUI

struct SignalASIAgentExecutionFooterView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var detailsExpanded = false

  var completed: Bool
  var duration: String
  var details: [String]
  var detailsTitle: String
  var timelineActions: [AgentExecutionLoopTimelineAction] = []
  var timelineActionTitle: (AgentExecutionLoopTimelineAction) -> String = { $0.rawValue }
  var timelineActionIcon: (AgentExecutionLoopTimelineAction) -> String = { _ in "ellipsis" }
  var timelineActionMenuTitle: String = ""
  var onTimelineAction: (AgentExecutionLoopTimelineAction) -> Void = { _ in }
  var canCancel: Bool = false
  var cancelTitle: String = ""
  var onCancel: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(processingSummary)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)

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
        executionControls
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASISurface.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  private var processingSummary: String {
    AgentTranscriptPresentationPolicy.processedSummary(
      completed: completed,
      duration: duration,
      processingFormat: t("signalasi.agent.trace.processing", "Working for %@"),
      processedFormat: t("signalasi.agent.trace.processed", "Worked for %@")
    )
  }

  private var resolvedCancelTitle: String {
    cancelTitle.ifBlank(t("signalasi.agent.task_control.cancel", "Cancel task"))
  }

  private var resolvedTimelineActionMenuTitle: String {
    timelineActionMenuTitle.ifBlank(t("signalasi.agent.task_control.title", "Task controls"))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  @ViewBuilder
  private var executionControls: some View {
    if usesAccessibilityDynamicType {
      VStack(spacing: 8) {
        cancelControl
        timelineControl
      }
    } else {
      HStack(spacing: 8) {
        cancelControl
        timelineControl
      }
    }
  }

  @ViewBuilder
  private var cancelControl: some View {
    if canCancel {
      Button(role: .destructive, action: onCancel) {
        Label(resolvedCancelTitle, systemImage: "xmark.circle")
          .font(.system(size: 10, weight: .semibold))
          .frame(maxWidth: usesAccessibilityDynamicType ? .infinity : nil, minHeight: 30)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel(Text(resolvedCancelTitle))
      .accessibilityIdentifier("ios.agent.execution-footer.cancel")
    }
  }

  @ViewBuilder
  private var timelineControl: some View {
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
      .menuStyle(.automatic)
      .accessibilityLabel(Text(resolvedTimelineActionMenuTitle))
      .accessibilityIdentifier("ios.agent.execution-footer.controls")
    }
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }
}
