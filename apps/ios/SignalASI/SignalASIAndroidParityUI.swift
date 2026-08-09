import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct AgentTranscriptScrollMetrics: Equatable {
  var contentMinY: CGFloat = 0
  var contentMaxY: CGFloat = 0
  var viewportHeight: CGFloat = 0
}

private struct AgentTranscriptScrollMetricsKey: PreferenceKey {
  static let defaultValue = AgentTranscriptScrollMetrics()

  static func reduce(
    value: inout AgentTranscriptScrollMetrics,
    nextValue: () -> AgentTranscriptScrollMetrics
  ) {
    value = nextValue()
  }
}

private extension View {
  func agentDeviceTouchTarget(_ policy: AgentDeviceInputTargetPolicy) -> some View {
    frame(
      minWidth: CGFloat(policy.minimumTouchTargetDp),
      minHeight: CGFloat(policy.minimumTouchTargetDp)
    )
    .contentShape(Rectangle())
  }
}

struct AgentHomeView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var draft = ""
  @State private var attachments: [SignalASIDraftAttachment] = []
  @State private var actionTrayPresented = false
  @State private var voiceTranscriptionPending = false
  @State private var transcriptAutoFollow = true
  @State private var transcriptShowLatestButton = false
  @State private var transcriptContentMinY: CGFloat = 0
  @State private var visibleAgentMessageLimit = 24
  @State private var olderTranscriptAnchor: UUID?
  @State private var retryingAgentMessageIDs: Set<UUID> = []
  @State private var retryingAgentTaskIDs: Set<String> = []
  @State private var fileImporterPresented = false
  @State private var cameraPickerPresented = false
  @State private var scanShortcutActive = false
  @State private var recentTasksShortcutActive = false
  @State private var attachmentError = ""
  @State private var selectedMessageForDetails: ChatMessage?
  @State private var composerFocusRequest = 0
  @State private var agentRuntimeAuditRecords: [AgentNativeToolAuditRecord] = []
  @State private var modelSelection = AgentModelSelection()
  @State private var voiceAttachmentSnapshot: [SignalASIDraftAttachment] = []
  @State private var runtimeArtifactPreview: SignalASIRuntimeArtifactPreview?
  @State private var runtimeArtifactDocument: SignalASIRuntimeArtifactDocument?
  @State private var runtimeArtifactExportPresented = false
  @State private var runtimeArtifactExportFilename = ""
  @State private var runtimeArtifactExportSourceURI = ""
  @State private var runtimeArtifactError = ""
  @State private var runtimeArtifactStatus = ""
  @State private var richActionStatus = ""
  @State private var recoveringAgentTaskIDs: Set<String> = []
  @State private var approvalActionsInFlight: Set<String> = []
  @State private var cancellingRemoteTaskIDs: Set<String> = []
  @State private var pendingHighRiskApprovalTask: AgentTaskRecord?

  private var contact: SignalASIContact {
    store.contact(id: "hermes") ?? SignalASIContact.hermes()
  }

  private var activeAgentSession: AgentConversation? {
    store.agentSession(id: store.activeAgentConversationId)
  }

  private var hasManualSelection: Bool {
    modelSelection.mode == .manual &&
      !modelSelection.targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var messages: [ChatMessage] {
    let allMessages = store.messages(for: contact.id)
    guard let session = activeAgentSession else {
      return allMessages
    }
    let scopedMessages = store.agentSessionMessages(session.id)
    guard scopedMessages.isEmpty else {
      return scopedMessages
    }
    // Keep legacy system messages visible until the first message is assigned to a session.
    return allMessages.filter {
      $0.conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private static let agentTranscriptPageSize = 24

  private var transcriptMessages: [ChatMessage] {
    guard messages.count > visibleAgentMessageLimit else { return messages }
    return Array(messages.suffix(visibleAgentMessageLimit))
  }

  private var hasOlderTranscriptMessages: Bool {
    messages.count > visibleAgentMessageLimit
  }

  private var waitingMessageIDs: Set<UUID> {
    AgentReplyWaitingIndicatorPolicy.waitingMessageIDs(
      messages: messages,
      pendingTurnIds: coordinator.pendingAgentReplyTurnIds
    )
  }

  private var unreadTotal: Int {
    store.visibleContacts.reduce(0) { total, contact in
      total + store.conversationSummary(for: contact.id).unreadCount
    }
  }

  private var nativeToolSummary: (total: Int, available: Int) {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return (tools.count, available)
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }

  private var activeAgentTasks: [AgentTaskRecord] {
    activeSessionTasks.filter { task in
      guard taskBelongsToActiveSession(task) else { return false }
      switch task.phase {
      case .observing, .planning, .waitingConfirmation, .executing, .verifying, .waitingResponse, .paused:
        return true
      case .cancelled, .blocked, .completed, .failed:
        return false
      }
    }
  }

  private var activeSessionTasks: [AgentTaskRecord] {
    let sessionID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionID.isEmpty else {
      return store.recentAgentTasks(limit: 24)
    }
    let scopedTasks = store.agentTasks(forSession: sessionID, limit: 24)
    return scopedTasks.isEmpty ? store.recentAgentTasks(limit: 24) : scopedTasks
  }

  private var recoverableAgentTasksFromOtherSessions: [AgentTaskRecord] {
    let activeSessionID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !activeSessionID.isEmpty else { return [] }
    let recoverablePhases: [AgentPhase] = [
      .observing,
      .planning,
      .waitingConfirmation,
      .executing,
      .verifying,
      .waitingResponse,
      .paused
    ]
    return store.recentAgentTasks(limit: 50)
      .filter { task in
        let sessionID = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        return !sessionID.isEmpty && sessionID != activeSessionID && recoverablePhases.contains(task.phase)
      }
      .prefix(3)
      .map { $0 }
  }

  private func taskBelongsToActiveSession(_ task: AgentTaskRecord) -> Bool {
    let activeSessionId = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let taskSessionId = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !activeSessionId.isEmpty else {
      return taskSessionId.isEmpty
    }
    // Empty task session IDs are legacy records created before session scoping.
    return taskSessionId.isEmpty || taskSessionId == activeSessionId
  }

  private var activeAgentPhase: AgentPhase? {
    activeAgentTasks.first?.phase
  }

  private var pendingConfirmationTask: AgentTaskRecord? {
    activeAgentTasks.first { task in
      task.phase == .waitingConfirmation && task.pendingAction != nil
    }
  }

  private var activeExecutionTask: AgentTaskRecord? {
    guard pendingConfirmationTask == nil else { return nil }
    return activeAgentTasks.first
  }

  private var activeRemoteAgentTask: AgentRemoteTaskStatusSnapshot? {
    guard let session = activeAgentSession else { return nil }
    return coordinator.remoteAgentTaskStatuses.values
      .filter { $0.conversationId == session.id && !$0.isTerminal }
      .max { $0.updatedAtMillis < $1.updatedAtMillis }
  }

  private var liveExecutionTargetLabel: String? {
    let candidates = [
      activeRemoteAgentTask?.target,
      activeExecutionTask?.targetTitle
    ]
    return candidates
      .map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
      .first { value in
        !value.isEmpty && !Self.genericExecutionTargetLabels.contains(value.lowercased())
      }
  }

  private static let genericExecutionTargetLabels: Set<String> = [
    "agent or model",
    "cloud models",
    "mobile executor",
    "selected resource",
    "signalasi",
    "agent"
  ]

  private var cancellableAgentTask: AgentTaskRecord? {
    activeAgentTasks.first(where: AgentTaskCenterPolicy.cancellable)
  }

  private var primaryAgentTask: AgentTaskRecord? {
    activeAgentTasks.first(where: AgentTaskCenterPolicy.resumable) ?? cancellableAgentTask
  }

  private var primaryActionResumesTask: Bool {
    primaryAgentTask?.phase == .paused
  }

  private var primaryActionApprovesTask: Bool {
    guard let task = primaryAgentTask,
          task.phase == .waitingConfirmation,
          let action = task.pendingAction else {
      return false
    }
    return action.risk.weight < AgentRisk.high.weight
  }

  private var blockedAgentTask: AgentTaskRecord? {
    let sessionId = activeAgentSession?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return activeSessionTasks.first { task in
      let taskSessionId = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      let belongsToSession = sessionId.isEmpty || taskSessionId.isEmpty || taskSessionId == sessionId
      return belongsToSession &&
        (task.blocked || task.phase == .blocked) &&
        AgentTaskCenterPolicy.isReusableGoal(task.goal)
    }
  }

  private static let voiceTranscriptionPendingViewId = "signalasi-voice-transcription-pending"
  private static let agentTranscriptCoordinateSpace = "signalasi-agent-transcript"

  private var deviceInputPolicy: AgentDeviceInputTargetPolicy {
    AgentDeviceProfileDetector.detect().inputTargetPolicy
  }

  private var waitingForAgentReply: Bool {
    guard let latest = messages.last,
          latest.isMine,
          !latest.isSystem else {
      return false
    }
    return latest.deliveryStatus != .failed && !waitingMessageIDs.contains(latest.id)
  }

  private static let replyWaitingViewId = "signalasi-agent-reply-waiting"

  private var agentVoiceSettings: VoiceSettings {
    var settings = store.voiceSettings
    settings.preferredLocaleIdentifier = store.languagePolicy.asrLocaleIdentifier
    settings.routingMode = .nativeAgent
    settings.targetContactId = contact.id
    return settings
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        header
        agentOutput
        agentComposer
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .background(
        NavigationLink(
          destination: AddContactView(
            autoOpenScanner: true,
            onAgentAdded: { agentIDs in
              scanShortcutActive = false
              focusScannedAgent(agentIDs.first)
            }
          ),
          isActive: $scanShortcutActive
        ) {
          EmptyView()
        }
        .hidden()
      )
      .background(
        NavigationLink(
          destination: SignalASIAgentRecentTasksView(),
          isActive: $recentTasksShortcutActive
        ) {
          EmptyView()
        }
        .hidden()
      )
      .onAppear {
        ensureActiveAgentSession()
        store.markContactRead(contact.id)
        refreshAgentRuntimeAuditRecords()
        modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
        coordinator.updateAgentScreenContext(agentScreenSnapshot.screen)
      }
      .onChange(of: agentScreenSnapshot) { snapshot in
        coordinator.updateAgentScreenContext(snapshot.screen)
      }
      .onChange(of: store.activeAgentConversationId) { _ in
        resetAgentSessionPresentation()
      }
      .onReceive(
        NotificationCenter.default.publisher(for: .signalASIDesktopPairingDidComplete)
      ) { notification in
        let agentIDs = notification.userInfo?["agentIDs"] as? [String] ?? []
        focusScannedAgents(agentIDs)
      }
      .onChange(of: coordinator.artifactDownloadCompletedRevision) { _ in
        runtimeArtifactStatus = t(
          "runtime_artifact.download_completed",
          "Artifact download completed and is ready on this device."
        )
      }
      .onChange(of: coordinator.artifactDownloadFailure) { failure in
        guard !failure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runtimeArtifactError = failure
      }
      .fileImporter(
        isPresented: $fileImporterPresented,
        allowedContentTypes: [.item],
        allowsMultipleSelection: true
      ) { result in
        switch result {
        case .success(let urls):
          urls.forEach(addAttachment)
        case .failure(let error):
          attachmentError = error.localizedDescription
        }
      }
      .fullScreenCover(isPresented: $cameraPickerPresented) {
        CameraAttachmentPickerView { attachment in
          appendAttachment(attachment)
        }
      }
      .sheet(item: $selectedMessageForDetails) { message in
        MessageDetailView(message: message, contact: contact)
      }
      .sheet(item: $runtimeArtifactPreview) { preview in
        SignalASIRuntimeArtifactPreviewView(preview: preview)
      }
      .fileExporter(
        isPresented: $runtimeArtifactExportPresented,
        document: runtimeArtifactDocument,
        contentType: .data,
        defaultFilename: runtimeArtifactExportFilename
      ) { result in
        if case .success(let url) = result,
           !runtimeArtifactExportSourceURI.isEmpty {
          try? AgentDesktopArtifactStore.shared.markSavedToDownloads(
            sourceURI: runtimeArtifactExportSourceURI,
            savedURI: url.absoluteString
          )
          runtimeArtifactExportSourceURI = ""
        } else if case .failure(let error) = result {
          runtimeArtifactExportSourceURI = ""
          runtimeArtifactError = error.localizedDescription
        }
      }
      .alert(
        t("runtime_artifact.error.title", "Artifact unavailable"),
        isPresented: Binding(
          get: { !runtimeArtifactError.isEmpty },
          set: { if !$0 { runtimeArtifactError = "" } }
        )
      ) {
        Button(t("signalasi.common.done", "Done"), role: .cancel) {
          runtimeArtifactError = ""
        }
      } message: {
        Text(runtimeArtifactError)
      }
      .alert(
        t("runtime_artifact.status.title", "Artifact"),
        isPresented: Binding(
          get: { !runtimeArtifactStatus.isEmpty },
          set: { if !$0 { runtimeArtifactStatus = "" } }
        )
      ) {
        Button(t("signalasi.common.done", "Done"), role: .cancel) {
          runtimeArtifactStatus = ""
        }
      } message: {
        Text(runtimeArtifactStatus)
      }
      .alert(
        t("signalasi.agent.action_status.title", "Agent action"),
        isPresented: Binding(
          get: { !richActionStatus.isEmpty },
          set: { if !$0 { richActionStatus = "" } }
        )
      ) {
        Button(t("signalasi.common.done", "Done"), role: .cancel) {
          richActionStatus = ""
        }
      } message: {
        Text(richActionStatus)
      }
      .alert(item: $pendingHighRiskApprovalTask) { task in
        let action = task.pendingAction
        let fallbackDescription = t("signalasi.agent.confirmation.untitled", "Phone action")
        let description = action.map {
          $0.description.ifBlank(fallbackDescription)
        } ?? fallbackDescription
        let target = action?.target.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = target.isEmpty ? description : "\(description)\n\(target)"
        return Alert(
          title: Text(t("signalasi.agent.high_risk_confirmation.title", "Confirm high-risk action")),
          message: Text(detail),
          primaryButton: .default(
            Text(t("signalasi.agent.high_risk_confirmation.execute", "Execute"))
          ) {
            approveHighRiskTask(task)
          },
          secondaryButton: .cancel(Text(t("signalasi.common.cancel", "Cancel")))
        )
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private var runtimeArtifactManagedRoots: [URL] {
    let root = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL()
    return [
      root,
      root.appendingPathComponent("runs", isDirectory: true),
      root.appendingPathComponent("runs/artifacts", isDirectory: true),
      root.appendingPathComponent("artifacts", isDirectory: true)
    ]
  }

  private func handleRichAction(_ action: AgentRichAction) {
    switch action.verb {
    case "decide_task_permission":
      handleLocalPermissionAction(action.value)
    case "decide_remote_task_permission":
      handleRemotePermissionAction(action.value)
    case "copy":
      let value = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else {
        richActionStatus = t("signalasi.agent.action_status.empty", "This action has no content.")
        return
      }
      UIPasteboard.general.string = value
      richActionStatus = t("signalasi.common.copied", "Copied")
    case "open_uri":
      openRichActionURI(action.value)
    case "set_input":
      prefillAgentScreenCommand(action.value)
    case "submit_prompt":
      submitRichPrompt(action.value)
    case "open_conversation":
      openRichConversation(action.value)
    case "recover_agent_task":
      recoverAgentTask(action.value)
    case "download_desktop_artifact":
      guard let payload = AgentDesktopArtifactRequestPayload.decode(action.value) else {
        runtimeArtifactError = t("runtime_artifact.error.invalid", "The artifact information is invalid.")
        return
      }
      if let file = AgentDesktopArtifactStore.shared.localFile(forArtifactURI: payload.artifactURI) {
        do {
          runtimeArtifactDocument = SignalASIRuntimeArtifactDocument(data: try Data(contentsOf: file))
          runtimeArtifactExportFilename = payload.displayName
          runtimeArtifactExportSourceURI = payload.artifactURI
          runtimeArtifactExportPresented = true
        } catch {
          runtimeArtifactError = error.localizedDescription
        }
      } else {
        let block = payload.richBlock
        Task { @MainActor in
          if await coordinator.requestDesktopArtifactDownload(block: block) {
            runtimeArtifactStatus = t(
              "runtime_artifact.download_requested",
              "The Desktop was asked to resend this artifact."
            )
          } else {
            runtimeArtifactError = coordinator.lastError.ifBlank(
              t(
                "runtime_artifact.download_failed",
                "The artifact could not be requested from the Desktop."
              )
            )
          }
        }
      }
    case "preview_runtime_artifact", "save_runtime_artifact":
      guard let payload = AgentRuntimeArtifactActionPayload.decode(action.value) else {
        runtimeArtifactError = t("runtime_artifact.error.invalid", "The artifact information is invalid.")
        return
      }
      do {
        let file = try AgentRuntimeArtifactUi.resolve(
          payload: payload,
          managedRoots: runtimeArtifactManagedRoots
        )
        if action.verb == "preview_runtime_artifact" {
          runtimeArtifactPreview = SignalASIRuntimeArtifactPreview(
            title: payload.displayName,
            content: try AgentRuntimeArtifactUi.preview(file: file)
          )
        } else {
          runtimeArtifactDocument = SignalASIRuntimeArtifactDocument(data: try Data(contentsOf: file))
          runtimeArtifactExportFilename = payload.displayName
          runtimeArtifactExportSourceURI = ""
          runtimeArtifactExportPresented = true
        }
      } catch {
        runtimeArtifactError = error.localizedDescription
      }
    default:
      richActionStatus = t(
        "signalasi.agent.action_status.unsupported",
        "This Agent action is not supported on iOS yet."
      )
    }
  }

  private func openRichActionURI(_ rawURI: String) {
    let value = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          ["http", "https", "mailto", "tel", "sms"].contains(scheme),
          (scheme == "http" || scheme == "https" ? url.host != nil : true) else {
      richActionStatus = t("signalasi.agent.action_status.invalid_uri", "This link cannot be opened on iOS.")
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      guard !opened else { return }
      DispatchQueue.main.async {
        richActionStatus = t("signalasi.agent.action_status.open_failed", "The link could not be opened.")
      }
    }
  }

  private func submitRichPrompt(_ rawPrompt: String) {
    let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
      richActionStatus = t("signalasi.agent.action_status.empty", "This action has no content.")
      return
    }
    draft = prompt
    attachments.removeAll()
    actionTrayPresented = false
    attachmentError = ""
    sendAgentMessage()
  }

  private func openRichConversation(_ rawConversationID: String) {
    let conversationID = rawConversationID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conversationID.isEmpty, store.switchAgentSession(conversationID) else {
      richActionStatus = t(
        "signalasi.agent.action_status.conversation_unavailable",
        "That Agent conversation is no longer available."
      )
      return
    }
    draft = ""
    attachments.removeAll()
    actionTrayPresented = false
    attachmentError = ""
  }

  @ViewBuilder
  private func recoverableAgentTaskBanner(_ task: AgentTaskRecord) -> some View {
    Button {
      openRecoverableAgentTask(task)
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: task.phase == .waitingConfirmation ? "exclamationmark.shield" : "arrow.clockwise.circle")
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(task.phase == .waitingConfirmation ? .orange : .signalASIAccent)
          .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 3) {
          Text(t("signalasi.agent.recovery.title", "Recoverable Agent task"))
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
          Text(task.goal.ifBlank(t("signalasi.agent_tasks.title", "Agent task")))
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
          Text(agentPhaseLabel(task.phase))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(task.phase == .waitingConfirmation ? .orange : .signalASIAccent)
        }
        Spacer(minLength: 8)
        Image(systemName: "arrow.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.signalASIAccent)
          .frame(width: 28, height: 28)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.signalASIInsightBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.signalASIInsightStroke, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(
        String(
          format: t(
            "signalasi.agent.recovery.accessibility",
            "Open recoverable Agent task: %@"
          ),
          task.goal.ifBlank(t("signalasi.agent_tasks.title", "Agent task"))
        )
      )
    )
  }

  private func openRecoverableAgentTask(_ task: AgentTaskRecord) {
    let sessionID = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionID.isEmpty else {
      recentTasksShortcutActive = true
      return
    }
    guard store.switchAgentSession(sessionID) else {
      recentTasksShortcutActive = true
      return
    }
    resetAgentSessionPresentation()
  }

  private func recoverAgentTask(_ rawPayload: String) {
    guard let payload = AgentFailureRecoveryPayload.decode(rawPayload) else {
      richActionStatus = t("signalasi.agent.action_status.invalid", "This Agent action is invalid.")
      return
    }
    let conversationID = payload.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let taskID = payload.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conversationID.isEmpty, !taskID.isEmpty else {
      richActionStatus = t("signalasi.agent.action_status.invalid", "This Agent action is invalid.")
      return
    }
    guard store.switchAgentSession(conversationID) else {
      richActionStatus = t(
        "signalasi.agent.action_status.conversation_unavailable",
        "That Agent conversation is no longer available."
      )
      return
    }
    guard !recoveringAgentTaskIDs.contains(taskID) else { return }
    recoveringAgentTaskIDs.insert(taskID)
    let resolvedLanguage = LanguagePolicySettings.resolve(store.languagePolicy.responseLanguage)
    let chinese = resolvedLanguage.lowercased().hasPrefix("zh")
    let instruction = AgentFailureRecoveryPolicy.instruction(payload: payload, chinese: chinese)
    richActionStatus = t("signalasi.agent.action_status.recovery_started", "Recovery request started.")
    Task { @MainActor in
      let sent = await coordinator.send(instruction, to: contact)
      recoveringAgentTaskIDs.remove(taskID)
      if !sent {
        richActionStatus = t(
          "signalasi.agent.action_status.recovery_failed",
          "The recovery request could not be sent."
        )
      }
    }
  }

  private func handleLocalPermissionAction(_ rawChoice: String) {
    guard let choice = AgentPermissionChoice.fromWireValue(rawChoice) else {
      richActionStatus = t("signalasi.agent.approval_status.invalid", "This Agent action is invalid.")
      return
    }
    guard let task = pendingConfirmationTask else {
      richActionStatus = t(
        "signalasi.agent.approval_status.unavailable",
        "This local approval is no longer available."
      )
      return
    }
    if choice == .denyAlways {
      coordinator.denyLocalNativeAction(taskId: task.taskId)
      richActionStatus = t("signalasi.agent.approval_status.denied", "The Agent action was denied.")
    } else {
      coordinator.approveLocalNativeAction(
        taskId: task.taskId,
        remember: choice != .allowOnce
      )
      richActionStatus = t("signalasi.agent.approval_status.approved", "The Agent action was approved.")
    }
  }

  private func handleRemotePermissionAction(_ rawDecision: String) {
    guard let decision = AgentRemoteApprovalDecision.decode(rawDecision) else {
      richActionStatus = t("signalasi.agent.approval_status.invalid", "This Agent action is invalid.")
      return
    }
    let activeConversationID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !activeConversationID.isEmpty,
          decision.conversationId == activeConversationID else {
      richActionStatus = t(
        "signalasi.agent.approval_status.unavailable",
        "This remote approval is not part of the active Agent conversation."
      )
      return
    }
    let operationKey = "\(decision.taskId):\(decision.approvalId):\(decision.actionHash)"
    guard approvalActionsInFlight.insert(operationKey).inserted else {
      richActionStatus = t(
        "signalasi.agent.approval_status.pending",
        "This approval request is already being sent."
      )
      return
    }
    richActionStatus = t("signalasi.agent.approval_status.sending", "Sending approval decision...")
    Task { @MainActor in
      let published = await coordinator.publishRemoteAgentApproval(decision)
      approvalActionsInFlight.remove(operationKey)
      richActionStatus = published
        ? t("signalasi.agent.approval_status.sent", "Approval decision sent.")
        : t("signalasi.agent.approval_status.failed", "The approval decision could not be sent.")
    }
  }

  private var agentOutput: some View {
    ScrollViewReader { proxy in
      GeometryReader { viewport in
        ZStack(alignment: .bottomTrailing) {
          ScrollView {
        LazyVStack(spacing: 10) {
          if let recoverableAgentTask = recoverableAgentTasksFromOtherSessions.first {
            recoverableAgentTaskBanner(recoverableAgentTask)
          }
          if hasOlderTranscriptMessages {
            SignalASIAgentLoadOlderButton(
              title: t("signalasi.agent.load_older", "Load earlier messages"),
              action: loadOlderTranscriptMessages
            )
          }
          if let pendingConfirmationTask {
            SignalASIAgentConfirmationCard(
              task: pendingConfirmationTask,
              onApproveOnce: {
                requestAgentTaskApproval(pendingConfirmationTask)
              },
              onApproveAlways: {
                requestAgentTaskApproval(pendingConfirmationTask, remember: true)
              },
              onDeny: {
                coordinator.denyLocalNativeAction(taskId: pendingConfirmationTask.taskId)
              }
            )
          }
          if let blockedAgentTask {
            SignalASIAgentBlockedTaskCard(
              title: t("signalasi.agent.blocked.title", "Agent task blocked"),
              goal: blockedAgentTask.goal,
              subtitle: t(
                "signalasi.agent.blocked.subtitle",
                "This task could not continue. Retry or re-plan the original goal."
              ),
              retryTitle: t("signalasi.common.retry", "Retry"),
              replanTitle: t("signalasi.agent.task_control.replan", "Re-plan task"),
              retryingTitle: t("signalasi.agent_tasks.retrying", "Retrying task..."),
              isRetrying: retryingAgentTaskIDs.contains(blockedAgentTask.taskId)
            ) {
              retryBlockedAgentTask(blockedAgentTask)
            } onReplan: {
              retryAgentTask(blockedAgentTask, mode: .replan)
            }
          }
          if messages.isEmpty &&
              !voiceTranscriptionPending &&
              pendingConfirmationTask == nil &&
              blockedAgentTask == nil &&
              activeExecutionTask == nil &&
              activeRemoteAgentTask == nil &&
              recoverableAgentTasksFromOtherSessions.isEmpty {
            SignalASIAgentEmptyStateView(
              title: t("signalasi.agent.empty.title", "How can I help?"),
              subtitle: t("signalasi.agent.empty.subtitle", "Enter a goal or hold to talk")
            )
          } else {
            if let activeRemoteAgentTask {
              SignalASIAgentExecutionStatusCard(
                executor: activeRemoteAgentTask.target,
                status: remoteAgentStatusLabel(activeRemoteAgentTask.status),
                location: activeRemoteAgentTask.location,
                step: remoteAgentStep(activeRemoteAgentTask),
                duration: executionDuration(
                  startedAtMillis: activeRemoteAgentTask.history.first?.updatedAtMillis
                    ?? activeRemoteAgentTask.updatedAtMillis,
                  updatedAtMillis: activeRemoteAgentTask.updatedAtMillis
                ),
                liveDurationStartMillis: activeRemoteAgentTask.history.first?.updatedAtMillis
                  ?? activeRemoteAgentTask.updatedAtMillis,
                liveDurationFormatter: { executionDuration(elapsedMillis: $0) },
                detailsTitle: t("signalasi.agent.execution.timeline", "Execution timeline"),
                details: activeRemoteAgentTask.history.map(remoteAgentTimelineLine),
                canResume: false,
                resumeTitle: "",
                canCancel: activeRemoteAgentTask.isCancellable &&
                  !cancellingRemoteTaskIDs.contains(activeRemoteAgentTask.id),
                cancelTitle: cancellingRemoteTaskIDs.contains(activeRemoteAgentTask.id)
                  ? t("signalasi.agent.remote_status.cancelling", "Cancelling...")
                  : t("signalasi.agent.remote_status.cancel", "Cancel task")
              ) {
                // Remote tasks resume through the Desktop's next status event.
              } onCancel: {
                cancelRemoteAgentTask(activeRemoteAgentTask)
              }
            }
            if let activeExecutionTask {
              SignalASIAgentExecutionStatusCard(
                executor: activeExecutionTask.targetTitle.ifBlank(t("signalasi.agent.status", "Agent")),
                status: agentPhaseLabel(activeExecutionTask.phase),
                location: agentExecutionLocationSummary(activeExecutionTask),
                step: agentExecutionStep(activeExecutionTask),
                duration: executionDuration(
                  startedAtMillis: activeExecutionTask.createdAtMillis,
                  updatedAtMillis: activeExecutionTask.updatedAtMillis
                ),
                liveDurationStartMillis: activeExecutionTask.createdAtMillis,
                liveDurationFormatter: { executionDuration(elapsedMillis: $0) },
                detailsTitle: t("signalasi.agent.execution.timeline", "Execution timeline"),
                details: activeExecutionTask.executionLog,
                canResume: false,
                resumeTitle: "",
                canCancel: false,
                cancelTitle: "",
                onResume: {},
                onCancel: {},
                timelineActions: agentTimelineActions(for: activeExecutionTask),
                timelineActionTitle: { agentTimelineActionTitle($0) },
                timelineActionIcon: { agentTimelineActionIcon($0) },
                onTimelineAction: { action in
                  runAgentTimelineAction(action, task: activeExecutionTask)
                }
              }
            }
            SignalASIAgentScreenContextCard(
              screen: agentScreenSnapshot.screen,
              sections: agentScreenSnapshot.sections,
              onCommand: prefillAgentScreenCommand,
              t: t
            )
            ForEach(transcriptMessages) { message in
              MessageBubble(
                message: message,
                onAction: handleRichAction,
                onFormSubmit: handleAgentRichForm
              )
                .id(message.id)
                .contextMenu {
                  Button {
                    selectedMessageForDetails = message
                  } label: {
                    Label(t("signalasi.message.details", "Details"), systemImage: "info.circle")
                  }
                  Button {
                    UIPasteboard.general.string = message.content
                  } label: {
                    Label(t("signalasi.common.copy", "Copy"), systemImage: "doc.on.doc")
                  }
                  Button(role: .destructive) {
                    store.deleteMessage(message.id, contactId: contact.id)
                  } label: {
                    Label(t("signalasi.message.delete", "Delete Message"), systemImage: "trash")
                  }
                }
              if waitingMessageIDs.contains(message.id) {
                AgentReplyWaitingIndicatorView()
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .id(AgentReplyWaitingIndicatorPolicy.viewID(for: message))
              }
              if message.isMine && message.deliveryStatus == .failed {
                SignalASIAgentRetryCard(
                  title: t("signalasi.agent.retry.title", "Agent request failed"),
                  subtitle: t(
                    "signalasi.agent.retry.subtitle",
                    "Retry the most recent Agent request."
                  ),
                  retryTitle: t("signalasi.common.retry", "Retry"),
                  retryingTitle: t("signalasi.agent_tasks.retrying", "Retrying task..."),
                  isRetrying: retryingAgentMessageIDs.contains(message.id)
                ) {
                  retryAgentMessage(message)
                }
              }
            }
            if voiceTranscriptionPending {
              SignalASIVoiceTranscriptionPendingView()
                .id(Self.voiceTranscriptionPendingViewId)
            }
            if waitingForAgentReply {
              SignalASIAgentReplyWaitingIndicator()
                .id(Self.replyWaitingViewId)
            }
            if shouldShowAgentRuntimePanel {
              agentRuntimePanel
                .padding(.top, 2)
                .transition(.opacity)
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(
          GeometryReader { content in
            Color.clear.preference(
              key: AgentTranscriptScrollMetricsKey.self,
              value: AgentTranscriptScrollMetrics(
                contentMinY: content.frame(in: .named(Self.agentTranscriptCoordinateSpace)).minY,
                contentMaxY: content.frame(in: .named(Self.agentTranscriptCoordinateSpace)).maxY,
                viewportHeight: viewport.size.height
              )
            )
          }
        )
      }
      .background(Color.signalASIPageBackground)
      .simultaneousGesture(
        DragGesture(minimumDistance: 12)
          .onEnded { value in
            guard hasOlderTranscriptMessages,
                  transcriptContentMinY >= -8,
                  value.translation.height >= 12,
                  abs(value.translation.height) >= abs(value.translation.width) else {
              return
            }
            loadOlderTranscriptMessages()
          }
      )
      .onChange(of: visibleAgentMessageLimit) { _ in
        guard let anchor = olderTranscriptAnchor else { return }
        DispatchQueue.main.async {
          withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
            proxy.scrollTo(anchor, anchor: .top)
          }
          olderTranscriptAnchor = nil
        }
      }
      .onChange(of: store.activeAgentConversationId) { _ in
        visibleAgentMessageLimit = Self.agentTranscriptPageSize
        olderTranscriptAnchor = nil
        transcriptAutoFollow = true
        transcriptShowLatestButton = false
        DispatchQueue.main.async {
          guard let last = messages.last else { return }
          withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
      .onAppear {
        transcriptAutoFollow = true
        transcriptShowLatestButton = false
        DispatchQueue.main.async {
          guard let last = messages.last else { return }
          proxy.scrollTo(last.id, anchor: .bottom)
        }
      }
      .onChange(of: messages.count) { _ in
        if voiceTranscriptionPending && !messages.isEmpty {
          voiceTranscriptionPending = false
        }
        if transcriptAutoFollow {
          if let last = messages.last, waitingMessageIDs.contains(last.id) {
            withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(
                AgentReplyWaitingIndicatorPolicy.viewID(for: last),
                anchor: .bottom
              )
            }
          } else if waitingForAgentReply {
            withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(Self.replyWaitingViewId, anchor: .bottom)
            }
          } else if let last = messages.last {
            withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        } else if !messages.isEmpty {
          transcriptShowLatestButton = true
        }
        store.markContactRead(contact.id)
        refreshAgentRuntimeAuditRecords()
      }
      .onChange(of: activeAgentPhase) { _ in
        refreshAgentRuntimeAuditRecords()
      }
      .onChange(of: waitingMessageIDs.count) { _ in
        guard let last = messages.last else { return }
        guard transcriptAutoFollow else {
          transcriptShowLatestButton = true
          return
        }
        withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
          proxy.scrollTo(
            waitingMessageIDs.contains(last.id)
              ? AgentReplyWaitingIndicatorPolicy.viewID(for: last)
              : last.id,
            anchor: .bottom
          )
        }
      }
      .onChange(of: voiceTranscriptionPending) { pending in
        guard pending else { return }
        transcriptAutoFollow = true
        transcriptShowLatestButton = false
        withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
          proxy.scrollTo(Self.voiceTranscriptionPendingViewId, anchor: .bottom)
        }
      }
      .onChange(of: waitingForAgentReply) { waiting in
        guard waiting else { return }
        guard transcriptAutoFollow else {
          transcriptShowLatestButton = true
          return
        }
        withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
          proxy.scrollTo(Self.replyWaitingViewId, anchor: .bottom)
        }
      }
      if transcriptShowLatestButton, let last = messages.last {
            SignalASIAgentLatestButton(
              title: t("signalasi.agent.latest", "Back to latest")
            ) {
              transcriptAutoFollow = true
              transcriptShowLatestButton = false
              withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
                proxy.scrollTo(last.id, anchor: .bottom)
              }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .coordinateSpace(name: Self.agentTranscriptCoordinateSpace)
        .onPreferenceChange(AgentTranscriptScrollMetricsKey.self) { metrics in
          transcriptContentMinY = metrics.contentMinY
          let nearBottom = metrics.contentMaxY <= metrics.viewportHeight + 56
          if nearBottom {
            transcriptAutoFollow = true
            transcriptShowLatestButton = false
          } else {
            transcriptAutoFollow = false
            transcriptShowLatestButton = true
          }
        }
      }
    }
  }

  private func loadOlderTranscriptMessages() {
    guard hasOlderTranscriptMessages else { return }
    olderTranscriptAnchor = transcriptMessages.first?.id
    visibleAgentMessageLimit += Self.agentTranscriptPageSize
  }

  private func retryAgentMessage(_ message: ChatMessage) {
    guard message.isMine,
          message.deliveryStatus == .failed,
          !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          retryingAgentMessageIDs.insert(message.id).inserted else {
      return
    }
    Task { @MainActor in
      _ = await coordinator.send(message.content, to: contact)
      retryingAgentMessageIDs.remove(message.id)
    }
  }

  private func resumeActiveAgentTask(_ task: AgentTaskRecord) {
    richActionStatus = coordinator.resumeLocalNativeAction(taskId: task.taskId)
      ? t("signalasi.agent.task_control.resumed", "Task resumed")
      : t("signalasi.agent.task_control.resume_failed", "This task could not be resumed")
  }

  private func agentTimelineActions(for task: AgentTaskRecord) -> [AgentExecutionLoopTimelineAction] {
    AgentExecutionLoopTimelinePolicy.actionsForPhase(task.phase).filter { action in
      switch action {
      case .pause:
        return AgentTaskCenterPolicy.pauseable(task)
      case .resume:
        return AgentTaskCenterPolicy.resumable(task)
      case .cancel:
        return AgentTaskCenterPolicy.cancellable(task)
      case .retry, .replan:
        return AgentTaskCenterPolicy.isReusableGoal(task.goal)
      }
    }
  }

  private func runAgentTimelineAction(
    _ action: AgentExecutionLoopTimelineAction,
    task: AgentTaskRecord
  ) {
    switch action {
    case .pause:
      richActionStatus = coordinator.pauseLocalNativeAction(taskId: task.taskId)
        ? t("signalasi.agent.task_control.paused", "Task paused")
        : t("signalasi.agent.task_control.pause_failed", "This task could not be paused")
    case .resume:
      resumeActiveAgentTask(task)
    case .cancel:
      cancelActiveAgentTask(task)
    case .retry:
      retryAgentTask(task, mode: .retry)
    case .replan:
      retryAgentTask(task, mode: .replan)
    }
  }

  private func agentTimelineActionTitle(_ action: AgentExecutionLoopTimelineAction) -> String {
    switch action {
    case .pause:
      return t("signalasi.agent.task_control.pause", "Pause task")
    case .resume:
      return t("signalasi.agent.resume_task", "Resume task")
    case .retry:
      return t("signalasi.common.retry", "Retry")
    case .replan:
      return t("signalasi.agent.task_control.replan", "Re-plan task")
    case .cancel:
      return t("signalasi.common.cancel_task", "Cancel task")
    }
  }

  private func agentTimelineActionIcon(_ action: AgentExecutionLoopTimelineAction) -> String {
    switch action {
    case .pause:
      return "pause.fill"
    case .resume:
      return "play.fill"
    case .retry:
      return "arrow.clockwise"
    case .replan:
      return "arrow.triangle.2.circlepath"
    case .cancel:
      return "xmark.circle"
    }
  }

  private func cancelActiveAgentTask(_ task: AgentTaskRecord) {
    coordinator.cancelLocalNativeAction(taskId: task.taskId)
    richActionStatus = t("signalasi.agent.task_control.cancelled", "Task cancelled")
  }

  private func handleAgentRichForm(_ block: AgentRichBlock, _ values: [String: String]) {
    let formID = block.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !formID.isEmpty else {
      richActionStatus = t("signalasi.agent.form.invalid", "This Agent form is invalid.")
      return
    }
    let payload: [String: Any] = [
      "form_id": formID,
      "task_id": block.metadata["task_id"] ?? activeAgentTasks.first?.taskId ?? "",
      "values": values
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
          let encoded = String(data: data, encoding: .utf8) else {
      richActionStatus = t("signalasi.agent.form.invalid", "This Agent form is invalid.")
      return
    }
    draft = "\(block.title.ifBlank(t("signalasi.agent.form.response", "Form response"))): \(encoded)"
    attachments.removeAll()
    actionTrayPresented = false
    attachmentError = ""
    sendAgentMessage()
    richActionStatus = t("signalasi.agent.form.submitted", "Form submitted to Agent.")
  }

  private func cancelRemoteAgentTask(_ snapshot: AgentRemoteTaskStatusSnapshot) {
    guard cancellingRemoteTaskIDs.insert(snapshot.id).inserted else { return }
    richActionStatus = t(
      "signalasi.agent.remote_status.cancelling",
      "Sending cancellation..."
    )
    Task { @MainActor in
      let sent = await coordinator.cancelRemoteAgentTask(snapshot)
      cancellingRemoteTaskIDs.remove(snapshot.id)
      richActionStatus = sent
        ? t("signalasi.agent.remote_status.cancel_sent", "Cancellation sent.")
        : t("signalasi.agent.remote_status.cancel_failed", "The cancellation could not be sent.")
    }
  }

  private func agentPhaseLabel(_ phase: AgentPhase) -> String {
    switch phase {
    case .observing:
      return t("agent_status_observing", "Observing the current screen")
    case .planning:
      return t("agent_status_planning", "Planning from the goal")
    case .waitingConfirmation:
      return t("agent_status_waiting_confirmation", "Waiting for confirmation")
    case .executing:
      return t("agent_status_executing", "Executing action")
    case .verifying:
      return t("agent_status_verifying", "Verifying result")
    case .waitingResponse:
      return t("agent_status_waiting_response", "Waiting for reply")
    case .paused:
      return t("agent_status_paused", "Task paused")
    case .cancelled:
      return t("agent_status_cancelled", "Task cancelled")
    case .blocked:
      return t("agent_status_blocked", "Action blocked")
    case .completed:
      return t("agent_status_completed", "Action completed")
    case .failed:
      return t("agent_status_failed", "Action failed")
    }
  }

  private func agentExecutionLocationSummary(_ task: AgentTaskRecord) -> String {
    let location = AgentExecutionPresentationPolicy.location(record: task)
    return [
      locationLabel(location.locationKind),
      runtimeLabel(location.runtimeKind),
      location.locationName
    ]
      .filter { !$0.isBlank }
      .joined(separator: " · ")
      .ifBlank(t("signalasi.agent.execution.unknown", "Execution location unavailable"))
  }

  private func agentExecutionStep(_ task: AgentTaskRecord) -> String {
    let pendingStep = task.pendingAction?.description ?? ""
    return pendingStep
      .ifBlank(task.executionLog.last ?? "")
      .ifBlank(agentPhaseLabel(task.phase))
  }

  private func remoteAgentStatusLabel(_ status: String) -> String {
    switch AgentRemoteTaskStatusPolicy.normalize(status) {
    case "accepted":
      return t("agent_task_status_accepted", "Accepted")
    case "queued":
      return t("agent_task_status_queued", "Queued")
    case "starting":
      return t("agent_task_status_starting", "Starting")
    case "recovering":
      return t("agent_task_status_recovering", "Recovering")
    case "running":
      return t("agent_task_status_running", "Running")
    case "waiting_input":
      return t("agent_task_status_waiting_input", "Waiting for input")
    case "waiting_approval":
      return t("agent_task_status_waiting_approval", "Waiting for approval")
    case "completed":
      return t("agent_task_status_completed", "Completed")
    case "failed":
      return t("agent_task_status_failed", "Failed")
    case "cancelled":
      return t("agent_task_status_cancelled", "Cancelled")
    case "timed_out":
      return t("agent_task_status_timed_out", "Timed out")
    case "not_found":
      return t("agent_task_status_not_found", "Task unavailable")
    case "cancelling":
      return t("agent_task_status_cancelling", "Cancelling")
    default:
      return status.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  private func remoteAgentStep(_ snapshot: AgentRemoteTaskStatusSnapshot) -> String {
    snapshot.currentStep
      .ifBlank(snapshot.detail)
      .ifBlank(remoteAgentStatusLabel(snapshot.status))
  }

  private func remoteAgentTimelineLine(_ event: AgentRemoteTaskStatusEvent) -> String {
    let label = remoteAgentStatusLabel(event.status)
    return event.currentStep
      .ifBlank(event.detail)
      .ifBlank(label)
  }

  private func executionDuration(startedAtMillis: Int64, updatedAtMillis: Int64) -> String {
    guard startedAtMillis > 0, updatedAtMillis >= startedAtMillis else { return "" }
    return executionDuration(elapsedMillis: updatedAtMillis - startedAtMillis)
  }

  private func executionDuration(elapsedMillis: Int64) -> String {
    let totalSeconds = max(0, elapsedMillis / 1_000)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    if minutes > 0 {
      return String(
        format: t(
          "signalasi.agent.execution.duration_minutes",
          "Duration %dm %ds"
        ),
        minutes,
        seconds
      )
    }
    return String(
      format: t("signalasi.agent.execution.duration_seconds", "Duration %ds"),
      seconds
    )
  }

  private func locationLabel(_ value: AgentExecutionLocationKind) -> String {
    switch value {
    case .phone:
      return t("signalasi.agent_execution.location.phone", "Phone")
    case .desktop:
      return t("signalasi.agent_execution.location.desktop", "Desktop")
    case .cloud:
      return t("signalasi.agent_execution.location.cloud", "Cloud")
    case .connectedDevice:
      return t("signalasi.agent_execution.location.device", "Connected device")
    case .unknown:
      return ""
    }
  }

  private func runtimeLabel(_ value: AgentExecutionRuntimeKind) -> String {
    switch value {
    case .phoneNative:
      return t("signalasi.agent_execution.runtime.phone_native", "Phone native")
    case .phoneLinux:
      return t("signalasi.agent_execution.runtime.phone_linux", "Phone Linux")
    case .phoneLocalModel:
      return t("signalasi.agent_execution.runtime.local_model", "Local model")
    case .phoneCloudAPI:
      return t("signalasi.agent_execution.runtime.cloud_api", "Cloud API")
    case .desktopAgent:
      return t("signalasi.agent_execution.runtime.desktop_agent", "Desktop Agent")
    case .desktopTool:
      return t("signalasi.agent_execution.runtime.desktop_tool", "Desktop tool")
    case .connectedDevice:
      return t("signalasi.agent_execution.runtime.connected_device", "Connected device")
    case .knowledge:
      return t("signalasi.agent_execution.runtime.knowledge", "Knowledge")
    case .unknown:
      return ""
    }
  }

  private func retryBlockedAgentTask(_ task: AgentTaskRecord) {
    guard (task.blocked || task.phase == .blocked),
          AgentTaskCenterPolicy.isReusableGoal(task.goal),
          retryingAgentTaskIDs.insert(task.taskId).inserted else {
      return
    }
    Task { @MainActor in
      if let destination = store.agentSessionDestination(id: task.sessionId) {
        _ = store.switchAgentSession(destination)
      } else {
        _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
      }
      _ = await coordinator.send(task.goal, to: contact)
      retryingAgentTaskIDs.remove(task.taskId)
    }
  }

  private enum AgentTaskRestartMode {
    case retry
    case replan
  }

  private func retryAgentTask(_ task: AgentTaskRecord, mode: AgentTaskRestartMode) {
    guard AgentTaskCenterPolicy.isReusableGoal(task.goal),
          retryingAgentTaskIDs.insert(task.taskId).inserted else {
      return
    }
    let request: String
    switch mode {
    case .retry:
      request = task.goal
    case .replan:
      request = String(
        format: t(
          "signalasi.agent.task_control.replan_prompt",
          "Re-plan and continue this Agent task: %@"
        ),
        task.goal
      )
    }
    richActionStatus = mode == .replan
      ? t("signalasi.agent.task_control.replanned", "Task re-planned")
      : t("signalasi.agent_tasks.retrying", "Retrying task...")
    Task { @MainActor in
      if let destination = store.agentSessionDestination(id: task.sessionId) {
        _ = store.switchAgentSession(destination)
      }
      let sent = await coordinator.send(request, to: contact)
      retryingAgentTaskIDs.remove(task.taskId)
      if !sent {
        richActionStatus = t(
          "signalasi.agent_tasks.retry_failed",
          "The task could not be sent"
        )
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      SignalASILogoView(size: 39, cornerRadius: 8)
      VStack(alignment: .center, spacing: 2) {
        Text("SignalASI")
          .font(.system(size: 14.5, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
        Text(t("signalasi.agent.brand.subtitle", "Superintelligent agent"))
          .font(.system(size: 10, weight: .regular))
          .foregroundColor(.signalASITextSecondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        NavigationLink(destination: SignalASIAgentSessionsView()) {
          Text(headerSessionTitle)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.signalASIAgentSessionTitle)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
        NavigationLink(
          destination: SignalASIAgentModelSelectionView {
            modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
          }
        ) {
          HStack(spacing: 3) {
            Image(systemName: "chevron.left")
              .font(.system(size: 8, weight: .bold))
            Text(headerModelStatusLabel)
              .lineLimit(1)
              .minimumScaleFactor(0.72)
          }
          .font(.system(size: 10, weight: .regular))
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
      }
      .frame(width: 128, minHeight: 44, alignment: .trailing)
      NavigationLink(destination: SettingsView()) {
        Image(systemName: "ellipsis.horizontal")
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(height: 76)
    .background(Color.signalASIPageBackground)
  }

  private var headerModelLabel: String {
    guard hasManualSelection else {
      if let liveExecutionTargetLabel {
        return liveExecutionTargetLabel
      }
      let sessionLabel = activeAgentSession?.selectedModelOrAgent
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let automaticLabel = t("signalasi.agent.model_selection.automatic", "Automatic")
      guard !sessionLabel.isEmpty,
            sessionLabel.caseInsensitiveCompare("automatic") != .orderedSame,
            sessionLabel.caseInsensitiveCompare(contact.displayName) != .orderedSame else {
        return automaticLabel
      }
      return sessionLabel
    }
    let automaticLabel = t("signalasi.agent.model_selection.automatic", "Automatic")
    let targetId = modelSelection.targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackLabel = modelSelection.displayName
      .ifBlank(modelSelection.modelId)
      .ifBlank(targetId)
      .ifBlank(automaticLabel)
    if modelSelection.targetId == "local-llm" {
      let profile = LocalModelRuntimeCatalog.find(modelSelection.modelId)
      return profile.displayName
        .ifBlank(modelSelection.displayName)
        .ifBlank(modelSelection.modelId)
        .ifBlank(fallbackLabel)
    }
    if let contact = store.contact(id: modelSelection.targetId),
       contact.type == "agent" {
      return modelSelection.displayName.ifBlank(contact.displayName).ifBlank(contact.id)
    }
    if let contact = store.contact(id: modelSelection.targetId),
       let model = contact.selectedCloudModel {
      return model.displayName
        .ifBlank(model.modelId)
        .ifBlank(modelSelection.displayName)
        .ifBlank(fallbackLabel)
    }
    return fallbackLabel
  }

  private var headerModelStatusLabel: String {
    let key: String
    let fallback: String
    if hasManualSelection {
      key = "signalasi.agent.header.routing.manual"
      fallback = "Manual · %@"
    } else {
      key = "signalasi.agent.header.routing.auto"
      fallback = "Automatic · %@"
    }
    return String(format: t(key, fallback), headerModelLabel)
  }

  private var headerSessionTitle: String {
    let fallback = t("signalasi.agent.session.new", "New session")
    guard let session = activeAgentSession else { return fallback }
    let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(fallback)
    let sourceTitle = session.createdByAgent
      ? String(
          format: t("signalasi.agent_session.created_by_agent", "SignalASI · %@"),
          title
        )
      : title
    if !session.mergedIntoConversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return sourceTitle + " · " + t("signalasi.agent_session.merged", "Merged")
    }
    if session.trackingPaused {
      return sourceTitle + " · " + t("signalasi.agent_session.tracking_paused", "Tracking paused")
    }
    return sourceTitle
  }

  private var agentComposer: some View {
    SignalASIAgentComposerView(
      draft: $draft,
      actionTrayPresented: $actionTrayPresented,
      voiceTranscriptionPending: $voiceTranscriptionPending,
      attachments: attachments,
      attachmentError: attachmentError,
      canSend: canSend,
      hasPendingPrimaryAction: primaryAgentTask != nil,
      pendingPrimaryActionResumesTask: primaryActionResumesTask,
      pendingPrimaryActionApprovesTask: primaryActionApprovesTask,
      deviceInputPolicy: deviceInputPolicy,
      voiceSettings: agentVoiceSettings,
      focusRequest: composerFocusRequest,
      onRemoveAttachment: { attachment in
        attachments.removeAll { $0.id == attachment.id }
      },
      onNewSession: createAgentConversation,
      onScan: {
        scanShortcutActive = true
      },
      onTakePhoto: openCameraAttachmentPicker,
      onAddFile: {
        fileImporterPresented = true
      },
      onSend: { sendAgentMessage() },
      onPendingPrimaryAction: handlePendingAgentTaskAction,
      onVoiceStart: beginAgentVoiceCapture,
      onVoiceCancelled: {
        voiceTranscriptionPending = false
        restoreAgentVoiceAttachments()
      },
      onVoiceTranscript: sendAgentVoiceTranscript,
      t: t
    )
  }

  private func handlePendingAgentTaskAction() {
    guard let task = primaryAgentTask else { return }
    if task.phase == .waitingConfirmation {
      if requestAgentTaskApproval(task) {
        richActionStatus = t(
          "signalasi.agent.approval_status.approved",
          "The Agent action was approved."
        )
      }
    } else if task.phase == .paused {
      _ = coordinator.resumeLocalNativeAction(taskId: task.taskId)
    } else {
      coordinator.cancelLocalNativeAction(taskId: task.taskId)
    }
  }

  @discardableResult
  private func requestAgentTaskApproval(_ task: AgentTaskRecord, remember: Bool = false) -> Bool {
    guard let action = task.pendingAction else { return false }
    if action.risk.weight >= AgentRisk.high.weight {
      pendingHighRiskApprovalTask = task
      return false
    }
    coordinator.approveLocalNativeAction(taskId: task.taskId, remember: remember)
    return true
  }

  private func approveHighRiskTask(_ task: AgentTaskRecord) {
    guard taskBelongsToActiveSession(task),
          let current = store.agentTask(id: task.taskId),
          current.phase == .waitingConfirmation,
          let action = current.pendingAction,
          action.risk.weight >= AgentRisk.high.weight else {
      pendingHighRiskApprovalTask = nil
      return
    }
    coordinator.approveLocalNativeAction(
      taskId: current.taskId,
      highRiskConfirmed: true
    )
    pendingHighRiskApprovalTask = nil
  }

  private var agentRuntimePanel: some View {
    SignalASIAgentRuntimePanelView(
      safetySettings: store.agentSafetySettings,
      modelPlannerSettings: store.modelPlannerSettings,
      taskBudget: store.agentTaskBudget,
      callableTargets: store.visibleContacts.count,
      currentGoal: draft,
      recentTasks: agentRuntimeTasks,
      nativeTools: AgentPhoneNativeToolCatalog.descriptors(),
      auditRecords: agentRuntimeAuditRecords,
      onCyclePermissionMode: cycleAgentPermissionMode,
      onToggleHighRiskGuard: {
        store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
      },
      onToggleMemoryCapture: {
        store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
      },
      onOpenRecentTasks: {
        recentTasksShortcutActive = true
      },
      t: t
    )
  }

  private var agentRuntimeTasks: [AgentTaskRecord] {
    let sessionID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionID.isEmpty else {
      return store.recentAgentTasks(limit: 12).filter(taskBelongsToActiveSession)
    }
    let scopedTasks = store.agentTasks(forSession: sessionID, limit: 12)
    if !scopedTasks.isEmpty {
      return scopedTasks
    }
    // Legacy task records may not have a session ID yet.
    return store.recentAgentTasks(limit: 12).filter(taskBelongsToActiveSession)
  }

  private var shouldShowAgentRuntimePanel: Bool {
    activeExecutionTask != nil ||
      activeRemoteAgentTask != nil ||
      !agentRuntimeTasks.isEmpty
  }

  private func sendAgentMessage(
    voiceAttachmentSnapshot: [SignalASIDraftAttachment]? = nil
  ) {
    coordinator.updateAgentScreenContext(agentScreenSnapshot.screen)
    let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let outgoingAttachments = AgentVoiceAttachmentSubmissionPolicy.select(
      goalOverride: voiceAttachmentSnapshot == nil ? nil : cleanDraft,
      composerAttachments: attachments,
      attachmentSnapshot: voiceAttachmentSnapshot
    )
    let text = cleanDraft.ifBlank(attachmentLabel(for: outgoingAttachments))
    let isVoiceSubmission = voiceAttachmentSnapshot != nil
    let agentGoal = cleanDraft.isEmpty && !outgoingAttachments.isEmpty
      ? t("agent_attachment_default_goal", "The user attached files without stating a task. Ask one concise question about what to do and offer four to six concrete actions suited to the file types. Mention only the file names; do not inspect, summarize, or return the attachments.")
      : ""
    let draftForRecovery = cleanDraft
    draft = ""
    if let voiceAttachmentSnapshot {
      let consumedIDs = Set(outgoingAttachments.map(\.id))
      attachments.removeAll { consumedIDs.contains($0.id) }
    } else {
      attachments.removeAll()
    }
    actionTrayPresented = false
    attachmentError = ""
    Task { @MainActor in
      let sent = await coordinator.send(
        text,
        to: contact,
        attachments: outgoingAttachments,
        agentGoalOverride: agentGoal
      )
      if !sent {
        if !draftForRecovery.isEmpty {
          draft = draftForRecovery
        }
        restoreAgentVoiceAttachments(outgoingAttachments)
        if isVoiceSubmission {
          voiceTranscriptionPending = false
        }
        attachmentError = coordinator.lastError
      }
    }
  }

  private func sendAgentVoiceTranscript(_ transcript: String) {
    let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let capturedAttachments = voiceAttachmentSnapshot
    voiceAttachmentSnapshot.removeAll()
    guard !cleanTranscript.isEmpty else {
      voiceTranscriptionPending = false
      restoreAgentVoiceAttachments(capturedAttachments)
      attachmentError = t("voice_no_speech", "No speech captured.")
      return
    }
    voiceTranscriptionPending = true
    draft = cleanTranscript
    sendAgentMessage(voiceAttachmentSnapshot: capturedAttachments)
  }

  private func beginAgentVoiceCapture() {
    voiceAttachmentSnapshot = attachments
    let capturedIDs = Set(attachments.map(\.id))
    attachments.removeAll { capturedIDs.contains($0.id) }
  }

  private func restoreAgentVoiceAttachments(_ captured: [SignalASIDraftAttachment]? = nil) {
    let values = captured ?? voiceAttachmentSnapshot
    guard !values.isEmpty else {
      voiceAttachmentSnapshot.removeAll()
      return
    }
    let existingIDs = Set(attachments.map(\.id))
    let restored = values.filter { !existingIDs.contains($0.id) }
    if !restored.isEmpty {
      attachments.insert(contentsOf: restored, at: 0)
    }
    voiceAttachmentSnapshot.removeAll()
  }

  private var agentScreenSnapshot: SignalASIAgentScreenContextSnapshot {
    SignalASIAgentScreenContextSnapshotBuilder.make(
      messages: messages,
      draft: draft,
      attachments: attachments,
      unreadTotal: unreadTotal,
      screenObservationAllowed: store.agentSafetySettings.screenObservationAllowed,
      t: t
    )
  }

  private func prefillAgentScreenCommand(_ command: String) {
    let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanCommand.isEmpty else { return }
    draft = cleanCommand
    actionTrayPresented = false
    attachmentError = ""
    composerFocusRequest += 1
  }

  private func cycleAgentPermissionMode() {
    let modes = AgentPermissionMode.allCases
    guard let index = modes.firstIndex(of: store.agentSafetySettings.permissionMode) else {
      store.updateAgentSafetySettings { $0.permissionMode = .askBeforeAction }
      return
    }
    store.updateAgentSafetySettings { $0.permissionMode = modes[(index + 1) % modes.count] }
  }

  private func refreshAgentRuntimeAuditRecords() {
    agentRuntimeAuditRecords = AgentNativeToolDefaultStores
      .makePersistentStores()
      .auditStore
      .list(limit: 12, toolId: "", status: nil)
  }

  private func resetAgentSessionPresentation() {
    draft = ""
    attachments.removeAll()
    voiceAttachmentSnapshot.removeAll()
    voiceTranscriptionPending = false
    actionTrayPresented = false
    attachmentError = ""
    selectedMessageForDetails = nil
    composerFocusRequest += 1
    visibleAgentMessageLimit = Self.agentTranscriptPageSize
    olderTranscriptAnchor = nil
    transcriptAutoFollow = true
    transcriptShowLatestButton = false
    retryingAgentMessageIDs.removeAll()
    retryingAgentTaskIDs.removeAll()
    runtimeArtifactPreview = nil
    runtimeArtifactDocument = nil
    runtimeArtifactExportPresented = false
    runtimeArtifactExportFilename = ""
    runtimeArtifactExportSourceURI = ""
    runtimeArtifactError = ""
    runtimeArtifactStatus = ""
    richActionStatus = ""
    recoveringAgentTaskIDs.removeAll()
    approvalActionsInFlight.removeAll()
    cancellingRemoteTaskIDs.removeAll()
    pendingHighRiskApprovalTask = nil
    modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
    refreshAgentRuntimeAuditRecords()
  }

  private func createAgentConversation() {
    _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
    resetAgentSessionPresentation()
  }

  private func focusScannedAgents(_ targetIDs: [String]) {
    let normalizedIDs = targetIDs
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !normalizedIDs.isEmpty else { return }

    Task { @MainActor in
      for delay in [UInt64(0), 300_000_000, 900_000_000, 1_800_000_000] {
        if delay > 0 {
          try? await Task.sleep(nanoseconds: delay)
        }
        for targetID in normalizedIDs {
          if focusScannedAgentIfAvailable(targetID) {
            return
          }
        }
      }
    }
  }

  private func focusScannedAgentIfAvailable(_ targetID: String) -> Bool {
    guard let target = store.contact(id: targetID),
          target.type == "agent",
          target.isCommunicable else {
      return false
    }
    let conversationId = store.activeAgentConversationId
    AgentModelSelectionSettings.selectManual(
      for: conversationId,
      targetId: target.id,
      modelId: target.selectedCloudModel?.modelId ?? "",
      displayName: target.displayName
    )
    modelSelection = AgentModelSelectionSettings.selection(for: conversationId)
    return true
  }

  private func focusScannedAgent(_ targetId: String?) {
    guard let targetId else { return }
    _ = focusScannedAgentIfAvailable(targetId)
  }

  private func ensureActiveAgentSession() {
    if let session = activeAgentSession {
      if session.status == .archived {
        _ = store.switchAgentSession(session.id)
      }
      return
    }
    _ = store.createAgentSession(title: t("signalasi.agent.session.new", "New session"))
  }

  private func openCameraAttachmentPicker() {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      attachmentError = t("agent_attachment_camera_unavailable", "Camera is unavailable")
      return
    }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      cameraPickerPresented = true
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          if granted {
            cameraPickerPresented = true
          } else {
            attachmentError = t("signalasi.scanner.camera_access_required", "Camera access is required to scan SignalASI QR codes.")
          }
        }
      }
    case .denied, .restricted:
      attachmentError = t("signalasi.scanner.camera_access_required", "Camera access is required to scan SignalASI QR codes.")
    @unknown default:
      cameraPickerPresented = true
    }
  }

  private func attachmentLabel(for values: [SignalASIDraftAttachment]) -> String {
    switch values.count {
    case 0:
      return ""
    case 1:
      return values[0].label
    default:
      return String(format: t("agent_attachment_count", "%d attachments"), values.count)
    }
  }

  private func addAttachment(url: URL) {
    do {
      let attachment = try SignalASIAttachmentPayloadBuilder.makeAttachment(from: url)
      appendAttachment(attachment)
    } catch {
      attachmentError = error.localizedDescription
    }
  }

  private func appendAttachment(_ attachment: SignalASIDraftAttachment) {
    guard SignalASIAttachmentPayloadBuilder.accepted(attachment, existing: attachments) else {
      attachmentError = t("agent_attachment_rejected", "Some attachments were skipped. You can add up to 10 files, 20 MB each.")
      return
    }
    attachments.append(attachment)
    attachmentError = ""
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentInsightBanner: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var unreadTotal: Int
  var runningTasks: Int
  var callableTargets: Int
  var executionPaused: Bool
  var nativeToolSummary: (total: Int, available: Int)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        SignalASILogoView(size: 34, cornerRadius: 7)
        VStack(alignment: .leading, spacing: 2) {
          Text("SignalASI Agent")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
          Text(summaryText)
            .font(.system(size: 12))
            .foregroundColor(.signalASIInsightText)
            .lineLimit(2)
        }
        Spacer()
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          AgentStatusChip(title: "iOS 15+", value: t("signalasi.status.ready", "Ready"))
          AgentStatusChip(title: t("signalasi.agent.status", "Agent"), value: agentStatusText)
          AgentStatusChip(title: t("cc_metric_native_tools", "Native tools"), value: nativeToolsText)
        }
      }
    }
    .padding(12)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var summaryText: String {
    if unreadTotal > 0 {
      return String(format: t("signalasi.agent.insight.unread", "You have %d unread agent messages."), unreadTotal)
    }
    if executionPaused {
      return t("agent_status_paused_subtitle", "Execution is paused. Resume when you are ready.")
    }
    return String(
      format: t("agent_running_tasks_targets_value", "Running tasks: %d / targets: %d"),
      runningTasks,
      callableTargets
    )
  }

  private var agentStatusText: String {
    executionPaused
      ? t("on_device_agent_status_paused", "Paused")
      : t("on_device_agent_status_running", "Running")
  }

  private var nativeToolsText: String {
    "\(nativeToolSummary.available)/\(nativeToolSummary.total)"
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentStatusChip: View {
  var title: String
  var value: String

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
        .foregroundColor(.signalASITextSecondary)
      Text(value)
        .fontWeight(.bold)
        .foregroundColor(.signalASITextPrimary)
    }
    .font(.system(size: 11))
    .lineLimit(1)
    .minimumScaleFactor(0.85)
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
