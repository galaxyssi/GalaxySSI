import Foundation
import SwiftUI

struct GalaxySSIAgentInteractiveProgressView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var detailsPresented = false

  var presentation: AgentInteractiveProgressPresentation
  var timelineActions: [AgentExecutionLoopTimelineAction]
  var timelineActionTitle: (AgentExecutionLoopTimelineAction) -> String
  var timelineActionIcon: (AgentExecutionLoopTimelineAction) -> String
  var t: (String, String) -> String
  var canCancel: Bool
  var onTimelineAction: (AgentExecutionLoopTimelineAction) -> Void
  var onCancel: () -> Void
  var onChangeAgent: () -> Void

  var body: some View {
    Button {
      detailsPresented = true
    } label: {
      HStack(spacing: 9) {
        progressIndicator
          .frame(width: 20, height: 20)
        Text(compactCounter)
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .foregroundColor(.galaxySSITextSecondary)
          .frame(minWidth: 26, alignment: .leading)
        Text(presentation.summary)
          .font(.system(size: 13))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
      .padding(.horizontal, 10)
      .frame(minHeight: 42)
      .background(Color.galaxySSISurface.opacity(0.78))
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(
        String(
          format: t("galaxyssi.agent.plan_progress.accessibility", "%@, step %@"),
          presentation.summary,
          compactCounter
        )
      )
    )
    .accessibilityHint(Text(t("galaxyssi.agent.plan_progress.open", "Show execution process")))
    .accessibilityIdentifier("ios.agent.plan-progress.compact")
    .sheet(isPresented: $detailsPresented) {
      detailsSheet
    }
  }

  @ViewBuilder
  private var progressIndicator: some View {
    if presentation.running {
      ProgressView()
        .progressViewStyle(.circular)
        .tint(.galaxySSIInsightText)
        .scaleEffect(0.72)
    } else if presentation.steps.contains(where: { $0.state == .failed }) {
      Image(systemName: "exclamationmark.circle")
        .foregroundColor(.red)
    } else {
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
    }
  }

  private var detailsSheet: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          headline
          Divider()
            .padding(.vertical, 12)
          stepList
          if !presentation.recentActivity.isEmpty {
            recentActivity
          }
          controls
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationTitle(t("galaxyssi.agent.plan_progress.title", "Execution process"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(t("galaxyssi.common.done", "Done")) {
            detailsPresented = false
          }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  private var headline: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 9) {
        progressIndicator
          .frame(width: 20, height: 20)
        Text(presentation.summary)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Text(currentBatchCounter)
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
          .foregroundColor(.galaxySSITextSecondary)
      }
      Text(
        presentation.running
          ? t("galaxyssi.agent.plan_progress.live", "Updating live")
          : t("galaxyssi.agent.plan_progress.finished", "Execution finished")
      )
      .font(.system(size: 11))
      .foregroundColor(.galaxySSITextSecondary)
      if !presentation.agentLabel.isEmpty {
        Text(presentation.agentLabel)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.galaxySSIInsightText)
          .lineLimit(1)
      }
    }
    .padding(.top, 16)
  }

  private var stepList: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(presentation.batches) { batch in
        if presentation.batches.count > 1 || batch.planRevision > 1 {
          batchHeader(batch)
        }
        ForEach(batch.steps) { step in
          HStack(alignment: .top, spacing: 10) {
            stepIndicator(step.state)
              .frame(width: 18, height: 18)
              .padding(.top, 1)
            Text(step.text)
              .font(.system(size: 13))
              .foregroundColor(
                step.state == .pending || step.state == .superseded
                  ? .galaxySSITextSecondary
                  : .galaxySSITextPrimary
              )
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(stepStateTitle(step.state))
              .font(.system(size: 10, weight: .medium))
              .foregroundColor(.galaxySSITextSecondary)
              .lineLimit(1)
          }
          .padding(.vertical, 11)
          if step.id != batch.steps.last?.id {
            Divider().padding(.leading, 28)
          }
        }
      }
    }
    .padding(.top, 8)
  }

  private func batchHeader(_ batch: AgentInteractiveProgressBatch) -> some View {
    HStack(spacing: 8) {
      Text(
        String(
          format: t("galaxyssi.agent.plan_progress.revision", "Plan revision %d"),
          batch.planRevision
        )
      )
      if !batch.current {
        Text(t("galaxyssi.agent.plan_progress.revised", "Adjusted"))
      }
      Spacer(minLength: 0)
    }
    .font(.system(size: 10.5, weight: .medium))
    .foregroundColor(.galaxySSITextSecondary)
    .padding(.top, 11)
    .padding(.bottom, 3)
  }

  private var recentActivity: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(t("galaxyssi.agent.plan_progress.current_activity", "Current activity"))
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
      ForEach(Array(presentation.recentActivity.enumerated()), id: \.offset) { _, activity in
        HStack(alignment: .top, spacing: 8) {
          Circle()
            .fill(Color.galaxySSITextSecondary)
            .frame(width: 4, height: 4)
            .padding(.top, 6)
          Text(activity)
            .font(.system(size: 11))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSISurface.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .padding(.top, 10)
  }

  @ViewBuilder
  private var controls: some View {
    let pauseAction = timelineActions.first { $0 == .pause || $0 == .resume }
    let replanAction = timelineActions.first { $0 == .replan }
    if presentation.running || canCancel {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(spacing: 8) {
            controlButtons(pauseAction: pauseAction, replanAction: replanAction)
          }
        } else {
          HStack(spacing: 8) {
            controlButtons(pauseAction: pauseAction, replanAction: replanAction)
          }
        }
      }
      .padding(.top, 14)
    }
  }

  @ViewBuilder
  private func controlButtons(
    pauseAction: AgentExecutionLoopTimelineAction?,
    replanAction: AgentExecutionLoopTimelineAction?
  ) -> some View {
    if let pauseAction {
      progressControl(
        title: timelineActionTitle(pauseAction),
        icon: timelineActionIcon(pauseAction)
      ) {
        onTimelineAction(pauseAction)
      }
    }
    if let replanAction {
      progressControl(
        title: timelineActionTitle(replanAction),
        icon: timelineActionIcon(replanAction)
      ) {
        onTimelineAction(replanAction)
      }
    }
    progressControl(
      title: t("galaxyssi.agent.plan_progress.change_agent", "Change Agent"),
      icon: "person.2"
    ) {
      detailsPresented = false
      onChangeAgent()
    }
    if canCancel {
      Button(role: .destructive) {
        detailsPresented = false
        onCancel()
      } label: {
        Label(t("galaxyssi.agent.task_control.cancel", "Cancel task"), systemImage: "xmark.circle")
          .font(.system(size: 11, weight: .semibold))
          .frame(maxWidth: .infinity, minHeight: 34)
      }
      .buttonStyle(.bordered)
    }
  }

  private func progressControl(
    title: String,
    icon: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon)
        .font(.system(size: 11, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 34)
    }
    .buttonStyle(.bordered)
  }

  @ViewBuilder
  private func stepIndicator(_ state: AgentInteractiveProgressStepState) -> some View {
    switch state {
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundColor(.green)
    case .active:
      ProgressView()
        .progressViewStyle(.circular)
        .tint(.galaxySSIInsightText)
        .scaleEffect(0.7)
    case .failed:
      Image(systemName: "exclamationmark.circle")
        .foregroundColor(.red)
    case .superseded:
      Image(systemName: "arrow.triangle.2.circlepath.circle")
        .foregroundColor(.galaxySSITextSecondary)
    case .pending:
      Image(systemName: "circle")
        .foregroundColor(.galaxySSITextSecondary)
    }
  }

  private func stepStateTitle(_ state: AgentInteractiveProgressStepState) -> String {
    switch state {
    case .pending:
      return t("galaxyssi.agent.plan_progress.pending", "Pending")
    case .active:
      return t("galaxyssi.agent.plan_progress.running", "Running")
    case .completed:
      return t("galaxyssi.agent.plan_progress.complete", "Complete")
    case .superseded:
      return t("galaxyssi.agent.plan_progress.revised", "Adjusted")
    case .failed:
      return t("galaxyssi.agent.plan_progress.failed", "Failed")
    }
  }

  private var compactCounter: String {
    guard presentation.planRevision > 1 else { return presentation.counter }
    return String(
      format: t("galaxyssi.agent.plan_progress.revision_counter", "R%d · %d/%d"),
      presentation.planRevision,
      presentation.currentStep,
      presentation.totalSteps
    )
  }

  private var currentBatchCounter: String {
    String(
      format: t("galaxyssi.agent.plan_progress.current_batch_count", "Current batch %d / %d"),
      presentation.currentStep,
      presentation.totalSteps
    )
  }
}
