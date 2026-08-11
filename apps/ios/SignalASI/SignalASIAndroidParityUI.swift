import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AgentHomeView: View {
  var onNavigateToMainTab: ((SignalASIMainTab) -> Void)? = nil

  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject var store: SignalASIStore
  @EnvironmentObject var coordinator: MessageCoordinator
  @ObservedObject private var voiceAgentRunRecovery = VoiceAgentRunRecoveryCoordinator.shared
  @State var draft = ""
  @State var attachments: [SignalASIDraftAttachment] = []
  @State var actionTrayPresented = false
  @State var voiceTranscriptionPending = false
  @State private var transcriptAutoFollow = true
  @State private var transcriptShowLatestButton = false
  @State var pendingAgentSwipeDirection = ""
  @State var agentSwipeRequest = 0
  @State private var transcriptContentMinY: CGFloat = 0
  @State private var transcriptTopLoadTriggered = false
  @State private var visibleAgentMessageLimit = 24
  @State private var olderTranscriptAnchor: UUID?
  @State var retryingAgentMessageIDs: Set<UUID> = []
  @State private var retryingAgentTaskIDs: Set<String> = []
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
  @State private var agentRuntimeAuditRecords: [AgentNativeToolAuditRecord] = []
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

  private var hasManualSelection: Bool {
    modelSelection.mode == .manual &&
      !modelSelection.targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var manualRouteWarning: (title: String, subtitle: String)? {
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

  private var automaticRouteWarning: (title: String, subtitle: String)? {
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

  private var transcriptMessages: [ChatMessage] {
    guard messages.count > visibleAgentMessageLimit else { return messages }
    return Array(messages.suffix(visibleAgentMessageLimit))
  }

  private var hasOlderTranscriptMessages: Bool {
    messages.count > visibleAgentMessageLimit
  }

  private var waitingMessageIDs: Set<UUID> {
    AgentReplyWaitingIndicatorPolicy.waitingMessageIDs(
      messages: transcriptMessages,
      pendingTurnIds: coordinator.pendingAgentReplyTurnIds
    )
  }

  private var unboundWaitingTurnIDs: [String] {
    AgentReplyWaitingIndicatorPolicy.unboundTurnIDs(
      messages: transcriptMessages,
      pendingTurnIds: coordinator.pendingAgentReplyTurnIds
    )
  }

  private var waitingIndicatorCount: Int {
    waitingMessageIDs.count + unboundWaitingTurnIDs.count
  }

  private var latestWaitingIndicatorID: String? {
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

  private var nativeToolSummary: (total: Int, available: Int) {
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

  private var availableCallableTargetCount: Int {
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

  private var activeAgentPhase: AgentPhase? {
    activeAgentTasks.first?.phase
  }

  private var agentActionQueueItems: [SignalASIAgentActionQueueItem] {
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

  private var activeExecutionTask: AgentTaskRecord? {
    guard pendingConfirmationTask == nil else { return nil }
    return activeAgentTasks.first
  }

  private var activeRemoteAgentTask: AgentRemoteTaskStatusSnapshot? {
    guard let session = activeAgentSession else { return nil }
    return coordinator.remoteAgentTaskStatuses.values
      .filter {
        $0.conversationId == session.id &&
          !AgentRemoteTaskStatusPolicy.isTerminal($0.status)
      }
      .max { $0.updatedAtMillis < $1.updatedAtMillis }
  }

  private var activeVoiceAgentRuns: [VoiceAgentRunSnapshot] {
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

  private var agentOutput: some View {
    SignalASIAgentHomeTranscriptView(
      visibleMessageLimit: $visibleAgentMessageLimit,
      olderTranscriptAnchor: $olderTranscriptAnchor,
      transcriptTopLoadTriggered: $transcriptTopLoadTriggered,
      transcriptAutoFollow: $transcriptAutoFollow,
      transcriptShowLatestButton: $transcriptShowLatestButton,
      transcriptContentMinY: $transcriptContentMinY,
      agentSwipeRequest: agentSwipeRequest,
      pendingAgentSwipeDirection: $pendingAgentSwipeDirection,
      activeAgentConversationID: store.activeAgentConversationId,
      messages: messages,
      transcriptMessages: transcriptMessages,
      hasOlderTranscriptMessages: hasOlderTranscriptMessages,
      latestWaitingIndicatorID: latestWaitingIndicatorID,
      waitingIndicatorCount: waitingIndicatorCount,
      voiceTranscriptionPending: voiceTranscriptionPending,
      voicePendingAttachments: voicePendingAttachments,
      waitingForAgentReply: waitingForAgentReply,
      activeAgentPhase: activeAgentPhase,
      activeAgentTasks: activeAgentTasks,
      pageSize: Self.agentTranscriptPageSize,
      reduceMotion: deviceInputPolicy.reduceMotion,
      voiceTranscriptionPendingViewID: Self.voiceTranscriptionPendingViewId,
      replyWaitingViewID: Self.replyWaitingViewId,
      latestButtonTitle: t("signalasi.agent.latest", "Back to latest"),
      onLoadOlderTranscriptMessages: loadOlderTranscriptMessages,
      onMessagesChanged: {
        if voiceTranscriptionPending && !messages.isEmpty {
          voiceTranscriptionPending = false
        }
        store.markContactRead(contact.id)
        refreshAgentRuntimeAuditRecords()
      },
      onExecutionStateChanged: refreshAgentRuntimeAuditRecords
    ) {
      LazyVStack(spacing: 5) {
          SignalASIAgentHomeExecutionAlertsView(
            scanStatus: scanStatus,
            scanStatusIsError: scanStatusIsError,
            activeVoiceAgentRuns: activeVoiceAgentRuns,
            cancellableVoiceAgentRuns: activeVoiceAgentRuns.filter {
              voiceRunRemoteTask($0)?.isCancellable == true
            },
            cancellingVoiceRunIDs: cancellingVoiceRunIDs,
            manualRouteWarning: manualRouteWarning,
            automaticRouteWarning: automaticRouteWarning,
            hasOlderTranscriptMessages: hasOlderTranscriptMessages,
            pendingConfirmationTask: pendingConfirmationTask,
            blockedAgentTask: blockedAgentTask,
            retryingAgentTaskIDs: retryingAgentTaskIDs,
            t: t,
            onRetryScan: {
              scanStatus = ""
              scanShortcutActive = true
            },
            onDismissScan: { scanStatus = "" },
            onCancelVoiceRun: cancelVoiceAgentRun,
            onOpenModelSelection: {
              modelSelection = AgentModelSelectionSettings.selection(
                for: store.activeAgentConversationId
              )
            },
            onLoadOlderTranscriptMessages: loadOlderTranscriptMessages,
            onApproveOnce: { task in
              requestAgentTaskApproval(task)
            },
            onApproveAlways: { task in
              requestAgentTaskApproval(task, remember: true)
            },
            onDeny: { task in
              coordinator.denyLocalNativeAction(taskId: task.taskId)
            },
            onRetryBlockedTask: retryBlockedAgentTask,
            onReplanBlockedTask: { task in
              retryAgentTask(task, mode: .replan)
            }
          )
          if let recoverableAgentTask = recoverableAgentTasksFromOtherSessions.first {
            recoverableAgentTaskBanner(recoverableAgentTask)
          }
          if messages.isEmpty &&
              !voiceTranscriptionPending &&
              pendingConfirmationTask == nil &&
              blockedAgentTask == nil &&
              activeExecutionTask == nil &&
              activeRemoteAgentTask == nil &&
              activeVoiceAgentRuns.isEmpty &&
              recoverableAgentTasksFromOtherSessions.isEmpty {
            SignalASIAgentHomeEmptyStatePanel(
              title: t("signalasi.agent.empty.title", "How can I help?"),
              subtitle: t("signalasi.agent.empty.subtitle", "Enter a goal or hold to talk"),
              runningTasks: activeAgentTasks.count,
              callableTargets: availableCallableTargetCount,
              nativeToolSummary: nativeToolSummary,
              nativeTools: AgentPhoneNativeToolCatalog.descriptors(),
              screenObservationAllowed: store.agentSafetySettings.screenObservationAllowed,
              executionPaused: store.agentSafetySettings.executionPaused,
              currentApp: agentScreenSnapshot.screen.foregroundApp
                .ifBlank(agentScreenSnapshot.screen.pageTitle)
                .ifBlank("SignalASI"),
              memorySnapshot: store.agentMemorySnapshot(),
              knowledgeStats: store.agentKnowledgeStats,
              knowledgeHitCount: store.agentKnowledgeAccessAudit.count,
              screen: agentScreenSnapshot.screen,
              screenSections: agentScreenSnapshot.sections,
              recentTaskCount: store.recentAgentTasks(limit: 200).count,
              recentTasks: store.recentAgentTasks(limit: 3),
              permissionMode: store.agentSafetySettings.permissionMode,
              highRiskGuard: store.agentSafetySettings.highRiskGuard,
              memoryCapture: store.agentSafetySettings.memoryCapture,
              routeTitle: headerPresentation.modelLogoLabel,
              routeSubtitle: hasManualSelection
                ? t("signalasi.agent.route.manual", "Manual route")
                : t("signalasi.agent.route.automatic", "Automatic route"),
              routeStatus: manualRouteWarning == nil && automaticRouteWarning == nil
                ? t("signalasi.status.ready", "Ready")
                : t("signalasi.agent.model_selection.choose", "Choose"),
              routeReady: manualRouteWarning == nil && automaticRouteWarning == nil,
              t: t,
              onNewSession: createAgentConversation,
              onOpenSessions: {
                recentTaskForDetails = nil
                agentSessionsShortcutActive = true
              },
              onScan: {
                scanShortcutActive = true
              },
              onTakePhoto: openCameraAttachmentPicker,
              onAddFile: {
                fileImporterPresented = true
              },
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
              onOpenRecentTasks: {
                recentTaskForDetails = nil
                recentTasksShortcutActive = true
              },
              onOpenRecentTask: { task in
                recentTaskForDetails = task
                recentTasksShortcutActive = true
              },
              onTaskAction: handleHomeTaskAction,
              onModelSelectionChanged: refreshAgentRouteState,
              onOpenRouteSelection: {
                agentModelSelectionShortcutActive = true
              },
              onScreenCommand: prefillAgentScreenCommand,
              onRefreshScreenContext: refreshAgentScreenContext
            )
            AgentProcessCard(
              activePhase: activeAgentPhase,
              executionPaused: store.agentSafetySettings.executionPaused
            )
          } else {
            SignalASIAgentExecutionOverviewView(
              activeRemoteAgentTask: activeRemoteAgentTask,
              activeExecutionTask: activeExecutionTask,
              actionQueueItems: agentActionQueueItems,
              activePhase: activeAgentPhase,
              executionPaused: store.agentSafetySettings.executionPaused,
              screen: agentScreenSnapshot.screen,
              screenSections: agentScreenSnapshot.sections,
              t: t,
              remoteStatusLabel: remoteAgentStatusLabel,
              remoteStep: remoteAgentStep,
              remoteTimelineLine: remoteAgentTimelineLine,
              phaseLabel: agentPhaseLabel,
              executionLocationSummary: agentExecutionLocationSummary,
              executionStep: agentExecutionStep,
              executionDuration: { startedAtMillis, updatedAtMillis in
                executionDuration(
                  startedAtMillis: startedAtMillis,
                  updatedAtMillis: updatedAtMillis
                )
              },
              liveExecutionDuration: { elapsedMillis in
                executionDuration(elapsedMillis: elapsedMillis)
              },
              timelineActions: { task in agentTimelineActions(for: task) },
              timelineActionTitle: agentTimelineActionTitle,
              timelineActionIcon: agentTimelineActionIcon,
              isRemoteTaskCancelling: { taskID in
                cancellingRemoteTaskIDs.contains(taskID)
              },
              remoteCancellationTitle: { isCancelling in
                isCancelling
                  ? t("signalasi.agent.remote_status.cancelling", "Cancelling...")
                  : t("signalasi.agent.remote_status.cancel", "Cancel task")
              },
              onCancelRemoteTask: cancelRemoteAgentTask,
              onCancelExecutionTask: cancelActiveAgentTask,
              onTimelineAction: { action, task in
                runAgentTimelineAction(action, task: task)
              },
              onEditAction: { item in
                homeActionEditorSelection = SignalASIAgentRuntimeActionSelection(
                  task: item.task,
                  action: item.action
                )
              },
              onScreenCommand: prefillAgentScreenCommand,
              onRefreshScreen: refreshAgentScreenContext
            )
            SignalASIAgentTranscriptMessagesView(
              messages: transcriptMessages,
              waitingMessageIDs: waitingMessageIDs,
              retryingMessageIDs: retryingAgentMessageIDs,
              t: t,
              mergedSourceLabel: { mergedSourceLabel(for: $0) },
              agentTask: { agentTask(for: $0) },
              remoteAgentTask: { remoteAgentTask(for: $0) },
              voiceAgentRun: { voiceAgentRun(for: $0) },
              agentPhaseLabel: agentPhaseLabel,
              agentExecutionLocationSummary: agentExecutionLocationSummary,
              agentExecutionStep: agentExecutionStep,
              remoteAgentStatusLabel: remoteAgentStatusLabel,
              remoteAgentStep: remoteAgentStep,
              remoteAgentTimelineLine: remoteAgentTimelineLine,
              executionDuration: { startedAtMillis, updatedAtMillis in
                executionDuration(
                  startedAtMillis: startedAtMillis,
                  updatedAtMillis: updatedAtMillis
                )
              },
              timelineActions: { task in agentTimelineActions(for: task) },
              timelineActionTitle: agentTimelineActionTitle,
              timelineActionIcon: agentTimelineActionIcon,
              isRemoteTaskCancelling: { taskID in
                cancellingRemoteTaskIDs.contains(taskID)
              },
              isVoiceRunCancelling: { runID in
                cancellingVoiceRunIDs.contains(runID)
              },
              onRichAction: { message, action in
                handleRichAction(action, from: message)
              },
              onFormSubmit: handleAgentRichForm,
              onCancelAgentTask: cancelActiveAgentTask,
              onCancelRemoteTask: cancelRemoteAgentTask,
              onCancelVoiceRun: cancelVoiceAgentRun,
              onTimelineAction: { action, task in
                runAgentTimelineAction(action, task: task)
              },
              onMessageDetails: { message in
                selectedMessageForDetails = message
              },
              onCopyMessage: { message in
                UIPasteboard.general.string = message.content
              },
              onCancelMessageTask: cancelActiveAgentTask,
              onCancelMessageRemoteTask: cancelRemoteAgentTask,
              onCancelMessageVoiceRun: cancelVoiceAgentRun,
              onDeleteMessage: { message in
                store.deleteMessage(message.id, contactId: contact.id)
              },
              onRetryMessage: retryAgentMessage
            )
            ForEach(unboundWaitingTurnIDs, id: \.self) { turnID in
              AgentReplyWaitingIndicatorView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(AgentReplyWaitingIndicatorPolicy.viewID(forTurnID: turnID))
            }
            if voiceTranscriptionPending {
              if !voicePendingAttachments.isEmpty {
                SignalASIAgentVoiceAttachmentSummaryView(
                  attachments: voicePendingAttachments,
                  t: t
                )
              }
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
      }
    )
  }

  private func loadOlderTranscriptMessages() {
    guard hasOlderTranscriptMessages, olderTranscriptAnchor == nil else { return }
    transcriptTopLoadTriggered = transcriptContentMinY >= -8
    olderTranscriptAnchor = transcriptMessages.first?.id
    visibleAgentMessageLimit += Self.agentTranscriptPageSize
  }

  private func agentTask(for message: ChatMessage) -> AgentTaskRecord? {
    let turnID = message.turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !turnID.isEmpty else { return nil }
    return store.agentTask(id: turnID)
  }

  private func remoteAgentTask(for message: ChatMessage) -> AgentRemoteTaskStatusSnapshot? {
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

  private func voiceAgentRun(for message: ChatMessage) -> VoiceAgentRunSnapshot? {
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

  func agentPhaseLabel(_ phase: AgentPhase) -> String {
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

  private func agentPhaseTint(_ phase: AgentPhase) -> Color {
    switch phase {
    case .blocked, .failed:
      return .red
    case .cancelled, .paused:
      return .signalASITextSecondary
    case .observing, .planning, .waitingConfirmation, .executing, .verifying,
         .waitingResponse, .completed:
      return .signalASIAccent
    }
  }

  private func agentExecutionLocationSummary(_ task: AgentTaskRecord) -> String {
    let location = AgentExecutionPresentationPolicy.location(record: task)
    let summary = [
      locationLabel(location.locationKind),
      runtimeLabel(location.runtimeKind),
      location.locationName
    ]
      .filter { !$0.isBlank }
      .joined(separator: " · ")
      .ifBlank(t("signalasi.agent.execution.unknown", "Execution location unavailable"))
    return summary.replacingOccurrences(of: " \u{8DEF} ", with: " \u{00B7} ")
  }

  private func agentExecutionStep(_ task: AgentTaskRecord) -> String {
    let pendingStep = task.pendingAction?.description ?? ""
    return pendingStep
      .ifBlank(task.executionLog.last ?? "")
      .ifBlank(agentPhaseLabel(task.phase))
  }

  private func remoteAgentStatusLabel(_ status: String) -> String {
    SignalASIRemoteTaskStatusPresentation.title(status, language: interfaceLanguage)
  }

  private func remoteAgentStatusTint(_ status: String) -> Color {
    SignalASIRemoteTaskStatusPresentation.tint(status)
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

  private var headerPresentation: SignalASIAgentHomeHeaderPresentation {
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

  private var agentRuntimePanel: some View {
    SignalASIAgentRuntimePanelView(
      safetySettings: store.agentSafetySettings,
      taskExecutionMode: store.agentSafetySettings.taskExecutionMode,
      modelPlannerSettings: store.modelPlannerSettings,
      taskBudget: store.agentTaskBudget,
      callableTargets: availableCallableTargetCount,
      currentGoal: draft,
      currentApp: agentScreenSnapshot.screen.foregroundApp
        .ifBlank(agentScreenSnapshot.screen.pageTitle)
        .ifBlank("SignalASI iOS"),
      memorySnapshot: store.agentMemorySnapshot(),
      knowledgeStats: store.agentKnowledgeStats,
      knowledgeHitCount: store.agentKnowledgeAccessAudit.count,
      recentTasks: agentRuntimeTasks,
      nativeTools: AgentPhoneNativeToolCatalog.descriptors(),
      auditRecords: agentRuntimeAuditRecords,
      onCyclePermissionMode: cycleAgentPermissionMode,
      onCycleTaskExecutionMode: cycleAgentTaskExecutionMode,
      onToggleHighRiskGuard: {
        store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
      },
      onToggleMemoryCapture: {
        store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
      },
      onToggleExecutionPaused: {
        store.updateAgentSafetySettings { $0.executionPaused.toggle() }
      },
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
      onTaskAction: handleAgentRuntimeTaskAction,
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

  func sendAgentMessage(
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
      voicePendingAttachments.removeAll()
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

  private func cycleAgentTaskExecutionMode() {
    let modes = AgentTaskExecutionMode.allCases
    guard let index = modes.firstIndex(of: store.agentSafetySettings.taskExecutionMode) else {
      store.updateAgentSafetySettings { $0.taskExecutionMode = .autoComplete }
      return
    }
    store.updateAgentSafetySettings { $0.taskExecutionMode = modes[(index + 1) % modes.count] }
  }

  private func refreshAgentRuntimeAuditRecords() {
    agentRuntimeAuditRecords = AgentNativeToolDefaultStores
      .makePersistentStores()
      .auditStore
      .list(limit: 12, toolId: "", status: nil)
  }

  private func refreshAgentRouteState() {
    modelSelection = AgentModelSelectionSettings.selection(
      for: store.activeAgentConversationId
    )
    refreshAgentRuntimeAuditRecords()
    refreshAgentScreenContext()
  }

  func resetAgentSessionPresentation() {
    agentScreenContextCapturedAtMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    draft = ""
    attachments.removeAll()
    voiceAttachmentSnapshot.removeAll()
    voicePendingAttachments.removeAll()
    agentVoiceDraftSnapshot = nil
    voiceTranscriptionPending = false
    actionTrayPresented = false
    attachmentError = ""
    selectedMessageForDetails = nil
    composerFocusRequest += 1
    visibleAgentMessageLimit = Self.agentTranscriptPageSize
    olderTranscriptAnchor = nil
    transcriptTopLoadTriggered = false
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
    cancellingVoiceRunIDs.removeAll()
    pendingHighRiskApprovalTask = nil
    modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
    refreshAgentRuntimeAuditRecords()
  }

  func createAgentConversation() {
    _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
    resetAgentSessionPresentation()
  }

  func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private func mergedSourceLabel(for message: ChatMessage) -> String? {
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
