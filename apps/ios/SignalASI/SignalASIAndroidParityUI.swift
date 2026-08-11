import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AgentHomeView: View {
  var onNavigateToMainTab: ((SignalASIMainTab) -> Void)? = nil

  @Environment(\.signalASIInterfaceLanguage) var interfaceLanguage
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject var store: SignalASIStore
  @EnvironmentObject var coordinator: MessageCoordinator
  @ObservedObject private var voiceAgentRunRecovery = VoiceAgentRunRecoveryCoordinator.shared
  @State var draft = ""
  @State var attachments: [SignalASIDraftAttachment] = []
  @State var actionTrayPresented = false
  @State var voiceTranscriptionPending = false
  @State var transcriptAutoFollow = true
  @State var transcriptShowLatestButton = false
  @State var pendingAgentSwipeDirection = ""
  @State var agentSwipeRequest = 0
  @State var transcriptContentMinY: CGFloat = 0
  @State var transcriptTopLoadTriggered = false
  @State var visibleAgentMessageLimit = 24
  @State var olderTranscriptAnchor: UUID?
  @State var retryingAgentMessageIDs: Set<UUID> = []
  @State var retryingAgentTaskIDs: Set<String> = []
  @State var timelineActionTaskIDsInFlight: Set<String> = []
  @State var pendingPrimaryActionTaskID: String?
  @State var fileImporterPresented = false
  @State var cameraPickerPresented = false
  @State var scanShortcutActive = false
  @State var scanSelectionRequestID = UUID()
  @State var agentSessionsShortcutActive = false
  @State private var agentSettingsShortcutActive = false
  @State var agentPermissionsShortcutActive = false
  @State var agentModelSelectionShortcutActive = false
  @State var agentNativeToolsShortcutActive = false
  @State var agentMemoryShortcutActive = false
  @State var agentKnowledgeShortcutActive = false
  @State var agentScreenContextShortcutActive = false
  @State var agentInsightsShortcutActive = false
  @State private var chatListShortcutActive = false
  @State private var contactsShortcutActive = false
  @State private var discoverShortcutActive = false
  @State var scanStatus = ""
  @State var scanStatusIsError = false
  @State var recentTasksShortcutActive = false
  @State var recentTaskForDetails: AgentTaskRecord?
  @State var attachmentError = ""
  @State var selectedMessageForDetails: ChatMessage?
  @State var homeActionEditorSelection: SignalASIAgentRuntimeActionSelection?
  @State var composerFocusRequest = 0
  @State var agentRuntimeAuditRecords: [AgentNativeToolAuditRecord] = []
  @State var modelSelection = AgentModelSelection()
  @State var voiceAttachmentSnapshot: [SignalASIDraftAttachment] = []
  @State var voicePendingAttachments: [SignalASIDraftAttachment] = []
  @State var agentVoiceDraftSnapshot: AgentVoiceDraftSnapshot?
  @State var runtimeArtifactPreview: SignalASIRuntimeArtifactPreview?
  @State var runtimeArtifactDocument: SignalASIRuntimeArtifactDocument?
  @State var runtimeArtifactExportPresented = false
  @State var runtimeArtifactExportFilename = ""
  @State var runtimeArtifactExportSourceURI = ""
  @State var runtimeArtifactError = ""
  @State var runtimeArtifactStatus = ""
  @State private var publicPageExportDocument: SignalASIPublicPageHTMLExportDocument?
  @State private var publicPageExportPresented = false
  @State private var publicPageExportFilename = ""
  @State var richActionStatus = ""
  @State var recoveringAgentTaskIDs: Set<String> = []
  @State var approvalActionsInFlight: Set<String> = []
  @State var cancellingRemoteTaskIDs: Set<String> = []
  @State var cancellingVoiceRunIDs: Set<String> = []
  @State var pendingHighRiskApprovalTask: AgentTaskRecord?
  @State var homeTaskPendingDeletion: AgentTaskRecord?
  @State var agentClipboardContext = AgentClipboardContext()
  @State var agentDeviceStatusContext = AgentDeviceStatusContext()
  @State var agentScreenContextCapturedAtMillis =
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  @State var agentNotificationContext = AgentNotificationContext()

  var contact: SignalASIContact {
    store.contact(id: "hermes") ?? SignalASIContact.hermes()
  }

  var activeAgentSession: AgentConversation? {
    store.agentSession(id: store.activeAgentConversationId)
  }

  var hasManualSelection: Bool {
    modelSelection.mode == .manual &&
      !modelSelection.targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var manualRouteWarning: (title: String, subtitle: String)? {
    guard hasManualSelection else { return nil }
    let targetId = modelSelection.targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    if targetId == "local-llm" {
      let profile = LocalModelRuntimeCatalog.find(modelSelection.modelId)
      let enabled = LocalModelRuntimeSettings.isProfileEnabled(profile)
      let ready = enabled &&
        LocalModelInferenceRuntime.shared.ready(profile: profile)
      guard !ready else {
        return nil
      }
      if enabled && LocalModelWhisperResourceArbiter.shared.asrHasPriority() {
        return (
          t("signalasi.agent.route.voice_priority_title", "Voice input has priority"),
          t(
            "signalasi.agent.route.voice_priority",
            "Local Whisper is kept ready for instant voice input. Choose another route or finish voice input before using the local model."
          )
        )
      }
      return (
        t("signalasi.agent.route.unavailable_title", "Selected route unavailable"),
        t(
          "signalasi.agent.route.local_unavailable",
          "The selected on-device model is not enabled. Choose another route before sending."
        )
      )
    }

    let callableTargets = AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
    guard let target = callableTargets.first(where: { $0.id == targetId }),
          AgentConnectorRouteSelector.isDeliverable(target) else {
      return (
        t("signalasi.agent.route.unavailable_title", "Selected route unavailable"),
        t(
          "signalasi.agent.route.remote_unavailable",
          "The selected Agent or model is offline. Choose another route before sending."
        )
      )
    }
    return nil
  }

  var automaticRouteWarning: (title: String, subtitle: String)? {
    guard !hasManualSelection else { return nil }

    let hasReadyLocalModel = LocalModelRuntimeSettings.activeProfiles().contains { profile in
      LocalModelRuntimeSettings.isProfileEnabled(profile) &&
        LocalModelInferenceRuntime.shared.ready(profile: profile)
    }
    let hasReadyRemoteTarget = AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    ).contains { target in
      guard target.kind != .device,
            AgentConnectorRouteSelector.isDeliverable(target) else {
        return false
      }
      return target.capabilities.contains { capability in
        capability == .chat || capability == .reasoning || capability == .research
      }
    }
    // Native phone tools can execute deterministic device requests without a model.
    let hasReadyNativeTool = nativeToolSummary.available > 0
    guard !hasReadyLocalModel && !hasReadyRemoteTarget && !hasReadyNativeTool else {
      return nil
    }

    return (
      t("signalasi.agent.model_selection.no_models", "No ready models"),
      t(
        "signalasi.agent.model_selection.no_models_subtitle",
        "Configure a cloud model, install a local model, or connect an Agent in Settings."
      )
    )
  }

  var messages: [ChatMessage] {
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

  static let agentTranscriptPageSize = 24

  var transcriptMessages: [ChatMessage] {
    guard messages.count > visibleAgentMessageLimit else { return messages }
    return Array(messages.suffix(visibleAgentMessageLimit))
  }

  var hasOlderTranscriptMessages: Bool {
    messages.count > visibleAgentMessageLimit
  }

  var waitingMessageIDs: Set<UUID> {
    AgentReplyWaitingIndicatorPolicy.waitingMessageIDs(
      messages: transcriptMessages,
      pendingTurnIds: coordinator.pendingAgentReplyTurnIds
    )
  }

  var unboundWaitingTurnIDs: [String] {
    AgentReplyWaitingIndicatorPolicy.unboundTurnIDs(
      messages: transcriptMessages,
      pendingTurnIds: coordinator.pendingAgentReplyTurnIds
    )
  }

  var waitingIndicatorCount: Int {
    waitingMessageIDs.count + unboundWaitingTurnIDs.count
  }

  var latestWaitingIndicatorID: String? {
    if let last = transcriptMessages.last, waitingMessageIDs.contains(last.id) {
      return AgentReplyWaitingIndicatorPolicy.viewID(for: last)
    }
    return unboundWaitingTurnIDs.last.map { turnID in
      AgentReplyWaitingIndicatorPolicy.viewID(forTurnID: turnID)
    }
  }

  var unreadTotal: Int {
    store.visibleContacts.reduce(0) { total, contact in
      total + store.conversationSummary(for: contact.id).unreadCount
    }
  }

  var nativeToolSummary: (total: Int, available: Int) {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return (tools.count, available)
  }

  private var callableAgentTargets: [AgentCallableTarget] {
    AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
  }

  var availableCallableTargetCount: Int {
    callableAgentTargets.filter { AgentConnectorRouteSelector.isDeliverable($0) }.count
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }

  var activeAgentTasks: [AgentTaskRecord] {
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

  var recoverableAgentTasksFromOtherSessions: [AgentTaskRecord] {
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

  func taskBelongsToActiveSession(_ task: AgentTaskRecord) -> Bool {
    let activeSessionId = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let taskSessionId = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !activeSessionId.isEmpty else {
      return taskSessionId.isEmpty
    }
    // Empty task session IDs are legacy records created before session scoping.
    return taskSessionId.isEmpty || taskSessionId == activeSessionId
  }

  var activeAgentPhase: AgentPhase? {
    activeAgentTasks.first?.phase
  }

  var agentActionQueueItems: [SignalASIAgentActionQueueItem] {
    var seen = Set<String>()
    return activeAgentTasks.flatMap { task in
      let actions = task.pendingActions.isEmpty
        ? task.pendingAction.map { [$0] } ?? []
        : task.pendingActions
      return actions.compactMap { action in
        let actionID = action.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actionID.isEmpty, seen.insert("\(task.taskId)-\(actionID)").inserted else {
          return nil
        }
        return SignalASIAgentActionQueueItem(task: task, action: action)
      }
    }
  }

  var pendingConfirmationTask: AgentTaskRecord? {
    activeAgentTasks.first { task in
      task.phase == .waitingConfirmation && task.pendingAction != nil
    }
  }

  var activeExecutionTask: AgentTaskRecord? {
    guard pendingConfirmationTask == nil else { return nil }
    return activeAgentTasks.first
  }

  var activeRemoteAgentTask: AgentRemoteTaskStatusSnapshot? {
    guard let session = activeAgentSession else { return nil }
    return coordinator.remoteAgentTaskStatuses.values
      .filter {
        $0.conversationId == session.id &&
          !AgentRemoteTaskStatusPolicy.isTerminal($0.status)
      }
      .max { $0.updatedAtMillis < $1.updatedAtMillis }
  }

  var activeVoiceAgentRuns: [VoiceAgentRunSnapshot] {
    let sessionID = store.activeAgentConversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    return voiceAgentRunRecovery.activeSnapshots
      .filter { snapshot in
        guard !sessionID.isEmpty else { return true }
        return snapshot.conversationId == sessionID || snapshot.sessionId == sessionID
      }
      .sorted { lhs, rhs in
        if lhs.updatedAtMillis != rhs.updatedAtMillis {
          return lhs.updatedAtMillis > rhs.updatedAtMillis
        }
        return lhs.runId < rhs.runId
      }
      .prefix(3)
      .map { $0 }
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

  var primaryAgentTask: AgentTaskRecord? {
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

  private var primaryActionWaitingForResponse: Bool {
    primaryAgentTask?.phase == .waitingResponse
  }

  private var primaryActionNeedsHighRiskConfirmation: Bool {
    guard let task = primaryAgentTask,
          task.phase == .waitingConfirmation,
          let action = task.pendingAction else {
      return false
    }
    return action.risk.weight >= AgentRisk.high.weight
  }

  var blockedAgentTask: AgentTaskRecord? {
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
  var deviceInputPolicy: AgentDeviceInputTargetPolicy {
    AgentDeviceProfileDetector.detect().inputTargetPolicy
  }

  var waitingForAgentReply: Bool {
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
        if !messages.isEmpty || activeExecutionTask != nil || activeRemoteAgentTask != nil || !activeVoiceAgentRuns.isEmpty {
          SignalASIAgentHomeSafetyStrip(
            permissionMode: store.agentSafetySettings.permissionMode,
            highRiskGuard: store.agentSafetySettings.highRiskGuard,
            memoryCapture: store.agentSafetySettings.memoryCapture,
            executionPaused: store.agentSafetySettings.executionPaused,
            onCyclePermissionMode: cycleAgentPermissionMode,
            onToggleHighRiskGuard: {
              store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
            },
            onToggleMemoryCapture: {
              store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
            },
            onToggleExecutionPaused: {
              store.updateAgentSafetySettings { $0.executionPaused.toggle() }
            },
            t: t
          )
          .padding(.horizontal, 10)
          .padding(.top, 6)
        }
        agentOutput
        agentComposer
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .background(
        SignalASIAgentHomeNavigationRoutesView(
          recentTasksShortcutActive: $recentTasksShortcutActive,
          agentSessionsShortcutActive: $agentSessionsShortcutActive,
          agentSettingsShortcutActive: $agentSettingsShortcutActive,
          agentPermissionsShortcutActive: $agentPermissionsShortcutActive,
          agentModelSelectionShortcutActive: $agentModelSelectionShortcutActive,
          agentNativeToolsShortcutActive: $agentNativeToolsShortcutActive,
          agentMemoryShortcutActive: $agentMemoryShortcutActive,
          agentKnowledgeShortcutActive: $agentKnowledgeShortcutActive,
          agentScreenContextShortcutActive: $agentScreenContextShortcutActive,
          agentInsightsShortcutActive: $agentInsightsShortcutActive,
          chatListShortcutActive: $chatListShortcutActive,
          contactsShortcutActive: $contactsShortcutActive,
          discoverShortcutActive: $discoverShortcutActive,
          recentTaskForDetails: recentTaskForDetails,
          screen: agentScreenSnapshot.screen,
          screenSections: agentScreenSnapshot.sections,
          onModelSelectionChanged: {
            modelSelection = AgentModelSelectionSettings.selection(
              for: store.activeAgentConversationId
            )
          },
          onScreenCommand: prefillAgentScreenCommand,
          onRefreshScreen: refreshAgentScreenContext,
          t: t
        )
      )
      .onAppear {
        coordinator.resumePendingAgentDelivery()
        ensureActiveAgentSession()
        presentPendingPhonePublicPageExport()
        voiceAgentRunRecovery.start()
        store.markContactRead(contact.id)
        _ = coordinator.requestCapabilityManifestRefresh()
        refreshAgentRouteState()
        installComposerInputBridge()
        installAgentHomeTapBridge()
        installAgentHomeLongPressBridge()
        installAgentHomeBackBridge()
        installAgentHomeSwipeBridge()
      }
      .onDisappear {
        AgentIOSComposerInputBridge.shared.removeHandler()
        AgentIOSAgentHomeActionBridge.shared.removeTapHandler()
        AgentIOSAgentHomeActionBridge.shared.removeLongPressHandler()
        AgentIOSAgentHomeActionBridge.shared.removeBackHandler()
        AgentIOSAgentHomeSwipeBridge.shared.removeHandler()
      }
      .onChange(of: scenePhase) { phase in
        guard phase == .active else { return }
        coordinator.resumePendingAgentDelivery()
        _ = coordinator.requestCapabilityManifestRefresh()
        refreshAgentRouteState()
        coordinator.refreshAgentHomeState()
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
        guard !agentIDs.isEmpty else { return }
        scanStatus = t(
          "signalasi.agent.scan.selecting",
          "Agent added. Selecting it for this session..."
        )
        scanStatusIsError = false
        focusScannedAgents(agentIDs)
      }
      .onChange(of: coordinator.artifactDownloadCompletedRevision) { _ in
        let savedPath = coordinator.artifactDownloadSavedPath
        runtimeArtifactStatus = savedPath.isEmpty
          ? t(
            "runtime_artifact.download_completed",
            "Artifact download completed and is ready on this device."
          )
          : String(
            format: t(
              "runtime_artifact.download_saved",
              "Artifact downloaded to %@."
            ),
            savedPath
          )
      }
      .onChange(of: coordinator.artifactDownloadFailure) { failure in
        guard !failure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runtimeArtifactError = failure
      }
      .onChange(of: coordinator.pendingPhonePublicPageExport) { _ in
        presentPendingPhonePublicPageExport()
      }
      .signalASIAgentHomePresentationRoutes(
        scanShortcutActive: $scanShortcutActive,
        fileImporterPresented: $fileImporterPresented,
        cameraPickerPresented: $cameraPickerPresented,
        attachmentError: $attachmentError,
        selectedMessageForDetails: $selectedMessageForDetails,
        homeActionEditorSelection: $homeActionEditorSelection,
        runtimeArtifactPreview: $runtimeArtifactPreview,
        runtimeArtifactDocument: $runtimeArtifactDocument,
        runtimeArtifactExportPresented: $runtimeArtifactExportPresented,
        runtimeArtifactExportFilename: $runtimeArtifactExportFilename,
        runtimeArtifactError: $runtimeArtifactError,
        runtimeArtifactStatus: $runtimeArtifactStatus,
        richActionStatus: $richActionStatus,
        pendingHighRiskApprovalTask: $pendingHighRiskApprovalTask,
        homeTaskPendingDeletion: $homeTaskPendingDeletion,
        contact: contact,
        t: t,
        onAgentAdded: { agentIDs in
          scanStatus = t(
            "signalasi.agent.scan.selecting",
            "Agent added. Selecting it for this session..."
          )
          scanStatusIsError = false
          _ = coordinator.requestCapabilityManifestRefresh(force: true)
          focusScannedAgents(agentIDs)
        },
        onAddAttachment: addAttachment,
        onAppendAttachment: appendAttachment,
        onUpdatePendingAction: { taskId, actionId, description, input in
          coordinator.updatePendingLocalNativeAction(
            taskId: taskId,
            actionId: actionId,
            description: description,
            input: input
          )
        },
        onMovePendingAction: { taskId, actionId, offset in
          coordinator.movePendingLocalNativeAction(
            taskId: taskId,
            actionId: actionId,
            offset: offset
          )
        },
        onRemovePendingAction: { taskId, actionId in
          coordinator.removePendingLocalNativeAction(
            taskId: taskId,
            actionId: actionId
          )
        },
        onArtifactExport: { result in
          if case .success(let url) = result,
             !runtimeArtifactExportSourceURI.isEmpty {
            coordinator.markDesktopArtifactSaved(
              sourceURI: runtimeArtifactExportSourceURI,
              savedURI: url.absoluteString
            )
            runtimeArtifactExportSourceURI = ""
          } else if case .failure(let error) = result {
            runtimeArtifactExportSourceURI = ""
            runtimeArtifactError = error.localizedDescription
          }
        },
        onApproveHighRisk: approveHighRiskTask,
        onDeleteTask: { task in
          handleAgentRuntimeTaskAction(.delete, task: task)
        }
      )
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .fileExporter(
      isPresented: $publicPageExportPresented,
      document: publicPageExportDocument,
      contentType: .html,
      defaultFilename: publicPageExportFilename
    ) { result in
      if case .failure(let error) = result {
        runtimeArtifactError = error.localizedDescription
      }
    }
  }

  private func presentPendingPhonePublicPageExport() {
    guard let export = coordinator.consumePendingPhonePublicPageExport() else { return }
    publicPageExportDocument = SignalASIPublicPageHTMLExportDocument(data: export.data)
    publicPageExportFilename = export.displayName
    publicPageExportPresented = true
  }

  var runtimeArtifactManagedRoots: [URL] {
    let root = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL()
    return [
      root,
      root.appendingPathComponent("runs", isDirectory: true),
      root.appendingPathComponent("runs/artifacts", isDirectory: true),
      root.appendingPathComponent("artifacts", isDirectory: true)
    ]
  }

  func loadOlderTranscriptMessages() {
    guard hasOlderTranscriptMessages, olderTranscriptAnchor == nil else { return }
    transcriptTopLoadTriggered = transcriptContentMinY >= -8
    olderTranscriptAnchor = transcriptMessages.first?.id
    visibleAgentMessageLimit += Self.agentTranscriptPageSize
  }

  func agentTask(for message: ChatMessage) -> AgentTaskRecord? {
    let turnID = message.turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !turnID.isEmpty else { return nil }
    return store.agentTask(id: turnID)
  }

  func remoteAgentTask(for message: ChatMessage) -> AgentRemoteTaskStatusSnapshot? {
    let conversationID = message.conversationId.ifBlank(store.activeAgentConversationId)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conversationID.isEmpty else { return nil }
    let turnID = message.turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    let remoteMessageID = message.remoteMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    return coordinator.remoteAgentTaskStatuses.values
      .filter { snapshot in
        guard snapshot.conversationId == conversationID,
              !AgentRemoteTaskStatusPolicy.isTerminal(snapshot.status) else {
          return false
        }
        let turnMatches = !turnID.isEmpty &&
          (snapshot.taskId == turnID || snapshot.turnId == turnID)
        let sourceID = snapshot.sourceMessageId > 0
          ? String(snapshot.sourceMessageId)
          : ""
        let sourceMatches = !remoteMessageID.isEmpty &&
          (!sourceID.isEmpty &&
            (remoteMessageID == sourceID || remoteMessageID == "agent-stream-\(sourceID)"))
        return turnMatches || sourceMatches
      }
      .max { lhs, rhs in
        if lhs.updatedAtMillis != rhs.updatedAtMillis {
          return lhs.updatedAtMillis < rhs.updatedAtMillis
        }
        return lhs.id < rhs.id
      }
  }

  func voiceAgentRun(for message: ChatMessage) -> VoiceAgentRunSnapshot? {
    let conversationID = message.conversationId.ifBlank(store.activeAgentConversationId)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conversationID.isEmpty else { return nil }
    let turnID = message.turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    let remoteMessageID = message.remoteMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    return voiceAgentRunRecovery.activeSnapshots
      .filter { run in
        guard run.conversationId == conversationID else { return false }
        let turnMatches = !turnID.isEmpty &&
          (run.turnId == turnID || run.taskId == turnID)
        let sourceMatches = !remoteMessageID.isEmpty &&
          (run.sourceMessageId == remoteMessageID ||
            remoteMessageID == "agent-stream-\(run.sourceMessageId)")
        return turnMatches || sourceMatches
      }
      .max { lhs, rhs in
        if lhs.updatedAtMillis != rhs.updatedAtMillis {
          return lhs.updatedAtMillis < rhs.updatedAtMillis
        }
        return lhs.runId < rhs.runId
      }
  }


  func retryBlockedAgentTask(_ task: AgentTaskRecord) {
    guard task.blocked || task.phase == .blocked else { return }
    retryAgentTask(task, mode: .replan)
  }

  enum AgentTaskRestartMode {
    case retry
    case replan
  }

  func retryAgentTask(_ task: AgentTaskRecord, mode: AgentTaskRestartMode) {
    if mode == .retry,
       coordinator.retryFailedLocalNativeAction(taskId: task.taskId) {
      richActionStatus = t(
        "signalasi.agent.task_control.action_retrying",
        "Retrying the failed action..."
      )
      return
    }
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
      ? t("signalasi.agent.task_control.replanning", "Re-planning task...")
      : t("signalasi.agent_tasks.retrying", "Retrying task...")
    Task { @MainActor in
      if mode == .replan,
         await coordinator.replanLocalNativeAction(taskId: task.taskId) {
        retryingAgentTaskIDs.remove(task.taskId)
        richActionStatus = t("signalasi.agent.task_control.replanned", "Task re-planned")
        resumePendingAgentDeliveryAfterTaskAction()
        return
      }
      if let destination = store.agentSessionDestination(id: task.sessionId) {
        _ = store.switchAgentSession(destination)
      }
      let sent = await coordinator.send(request, to: contact)
      retryingAgentTaskIDs.remove(task.taskId)
      resumePendingAgentDeliveryAfterTaskAction()
      if !sent {
        richActionStatus = t(
          "signalasi.agent_tasks.retry_failed",
          "The task could not be sent"
        )
      }
    }
  }

  private var header: some View {
    let presentation = headerPresentation
    return SignalASIAgentHomeHeaderView(
      sessionTitle: presentation.sessionTitle,
      modelStatusLabel: presentation.modelStatusLabel,
      modelLogoLabel: presentation.modelLogoLabel,
      brandSubtitle: t("signalasi.agent.brand.subtitle", "Superintelligent agent"),
      modelSelectionDestination: SignalASIAgentModelSelectionView {
        modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
      },
      onOpenSettings: { openMainTab(.settings) }
    )
  }

  func openMainTab(_ tab: SignalASIMainTab) {
    if let onNavigateToMainTab {
      onNavigateToMainTab(tab)
      return
    }
    switch tab {
    case .settings:
      agentSettingsShortcutActive = true
    case .messages:
      chatListShortcutActive = true
    case .contacts:
      contactsShortcutActive = true
    case .discover:
      discoverShortcutActive = true
    case .voice, .agent:
      break
    }
  }

  var headerPresentation: SignalASIAgentHomeHeaderPresentation {
    SignalASIAgentHomeHeaderPresentation.make(
      session: activeAgentSession,
      contact: contact,
      selection: modelSelection,
      liveExecutionTargetLabel: liveExecutionTargetLabel,
      contacts: store.contacts,
      language: interfaceLanguage
    )
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
      pendingPrimaryActionWaitingForResponse: primaryActionWaitingForResponse,
      pendingPrimaryActionNeedsHighRiskConfirmation: primaryActionNeedsHighRiskConfirmation,
      primaryActionInFlight: pendingPrimaryActionTaskID != nil,
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
        voicePendingAttachments.removeAll()
        agentVoiceDraftSnapshot = nil
        restoreAgentVoiceAttachments()
      },
      onVoiceTranscript: sendAgentVoiceTranscript,
      t: t
    )
  }

  func prefillAgentScreenCommand(_ command: String) {
    let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanCommand.isEmpty else { return }
    draft = cleanCommand
    actionTrayPresented = false
    attachmentError = ""
    composerFocusRequest += 1
  }

  func cycleAgentPermissionMode() {
    let modes = AgentPermissionMode.allCases
    guard let index = modes.firstIndex(of: store.agentSafetySettings.permissionMode) else {
      store.updateAgentSafetySettings { $0.permissionMode = .askBeforeAction }
      return
    }
    store.updateAgentSafetySettings { $0.permissionMode = modes[(index + 1) % modes.count] }
  }

  func cycleAgentTaskExecutionMode() {
    let modes = AgentTaskExecutionMode.allCases
    guard let index = modes.firstIndex(of: store.agentSafetySettings.taskExecutionMode) else {
      store.updateAgentSafetySettings { $0.taskExecutionMode = .autoComplete }
      return
    }
    store.updateAgentSafetySettings { $0.taskExecutionMode = modes[(index + 1) % modes.count] }
  }

  func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  func mergedSourceLabel(for message: ChatMessage) -> String? {
    let sourceId = message.sourceConversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sourceId.isEmpty else { return nil }
    let sourceTitle = message.sourceConversationTitle
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(String(sourceId.prefix(12)))
    return String(
      format: t(
        "signalasi.agent.session.merged_from",
        "Merged from session: %@"
      ),
      sourceTitle
    )
  }
}
