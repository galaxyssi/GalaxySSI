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
  @ObservedObject var voiceAgentRunRecovery = VoiceAgentRunRecoveryCoordinator.shared
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
  @State var photoPickerPresented = false
  @State var cameraPickerPresented = false
  @State var scanShortcutActive = false
  @State var scanSelectionRequestID = UUID()
  @State var pendingScannedAgentIDs: [String] = []
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
  @State var publicPageExportPresented = false
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
  @State var pendingVoiceRiskConfirmation: AgentHomeVoiceRiskConfirmation?

  var contact: SignalASIContact {
    store.contact(id: "hermes") ?? SignalASIContact.hermes()
  }

  var activeAgentSession: AgentConversation? {
    store.agentSession(id: store.activeAgentConversationId)
  }

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
            taskExecutionMode: store.agentSafetySettings.taskExecutionMode,
            executionPaused: store.agentSafetySettings.executionPaused,
            onCyclePermissionMode: cycleAgentPermissionMode,
            onToggleHighRiskGuard: {
              store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
            },
            onToggleMemoryCapture: {
              store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
            },
            onCycleTaskExecutionMode: cycleAgentTaskExecutionMode,
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
        retryPendingScannedAgentSelection()
        coordinator.refreshAgentHomeState()
      }
      .onChange(of: agentScreenSnapshot) { snapshot in
        coordinator.updateAgentScreenContext(snapshot.screen)
      }
      .onChange(of: store.activeAgentConversationId) { _ in
        resetAgentSessionPresentation()
        refreshAgentRouteState()
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
      .onReceive(
        NotificationCenter.default.publisher(for: .signalASIAgentRoutingDidUpdate)
      ) { _ in
        refreshAgentRouteState()
        retryPendingScannedAgentSelection()
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
        photoPickerPresented: $photoPickerPresented,
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
    .alert(item: $pendingVoiceRiskConfirmation) { confirmation in
      Alert(
        title: Text(t("signalasi.voice.risk_confirmation_title", "Confirm voice command")),
        message: Text(String(
          format: t(
            "signalasi.voice.risk_confirmation_message",
            "Review this %@ risk command before execution:\n\n%@"
          ),
          voiceRiskLabel(confirmation.risk),
          confirmation.transcript
        )),
        primaryButton: .default(Text(t("signalasi.voice.risk_confirmation_execute", "Execute"))) {
          executeAgentVoiceRiskConfirmation(confirmation)
        },
        secondaryButton: .cancel(Text(t("signalasi.voice.risk_confirmation_edit", "Edit"))) {
          editAgentVoiceRiskConfirmation(confirmation)
        }
      )
    }
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
      voiceNavigationLabel: t("signalasi.agent.open_voice", "Open voice"),
      settingsNavigationLabel: t("signalasi.tab.settings", "Settings"),
      modelSelectionDestination: SignalASIAgentModelSelectionView {
        modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
      },
      onOpenSettings: {
        actionTrayPresented = false
        agentSettingsShortcutActive = true
      },
      onOpenVoice: { openMainTab(.voice) }
    )
  }

  func openMainTab(_ tab: SignalASIMainTab) {
    if tab != .agent {
      // Android dismisses transient Agent composer UI before switching pages.
      actionTrayPresented = false
      voiceTranscriptionPending = false
    }
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
      hasPendingPrimaryAction: primaryActionResumesTask ||
        primaryActionApprovesTask ||
        primaryActionNeedsHighRiskConfirmation,
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
      onOpenSessions: {
        actionTrayPresented = false
        agentSessionsShortcutActive = true
      },
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
    switch cleanCommand.lowercased() {
    case "type text into agent goal input":
      actionTrayPresented = false
      attachmentError = ""
      composerFocusRequest += 1
      refreshAgentScreenContext()
      return
    case "paste clipboard":
      let clipboardText = UIPasteboard.general.string ?? ""
      guard !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        attachmentError = t("signalasi.agent.input.clipboard_empty", "Clipboard is empty.")
        return
      }
      draft = clipboardText
      actionTrayPresented = false
      attachmentError = ""
      composerFocusRequest += 1
      refreshAgentScreenContext()
      return
    case "swipe up", "swipe down":
      pendingAgentSwipeDirection = cleanCommand.lowercased() == "swipe up" ? "up" : "down"
      agentSwipeRequest += 1
      actionTrayPresented = false
      attachmentError = ""
      return
    default:
      break
    }
    if let targetID = agentHomeControlID(for: cleanCommand),
       activateAgentHomeControl(targetID) {
      actionTrayPresented = false
      attachmentError = ""
      refreshAgentScreenContext()
      return
    }
    draft = cleanCommand
    actionTrayPresented = false
    attachmentError = ""
    composerFocusRequest += 1
  }

  private func agentHomeControlID(for command: String) -> String? {
    switch command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "new session": return "new-session"
    case "show agent sessions": return "sessions"
    case "scan agent qr code": return "scan"
    case "take a photo": return "take-photo"
    case "attach photos": return "add-photos"
    case "attach a file": return "add-file"
    case "choose agent model": return "model-selection"
    case "show native tools": return "native-tools"
    case "open agent memory": return "memory"
    case "open agent knowledge": return "knowledge"
    case "show screen context": return "screen-context"
    case "refresh screen context": return "refresh-screen-context"
    case "show new agent insights": return "insights"
    case "show recent agent tasks": return "recent-tasks"
    case "cycle agent permission mode": return "permission-mode"
    case "cycle agent task execution mode": return "task-execution-mode"
    case "toggle agent high-risk guard": return "high-risk-guard"
    case "toggle agent memory capture": return "memory-capture"
    case "toggle agent execution pause": return "execution-paused"
    case "open permissions": return "permissions"
    case "open agent": return "agent"
    case "open messages": return "messages"
    case "open contacts": return "contacts"
    case "open discover": return "discover"
    case "open settings": return "settings"
    default: return nil
    }
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
