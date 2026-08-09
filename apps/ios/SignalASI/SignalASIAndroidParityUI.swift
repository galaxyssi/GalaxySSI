import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private func signalASIColor(light: UInt32, dark: UInt32) -> UIColor {
  UIColor { traits in
    signalASIColor(traits.userInterfaceStyle == .dark ? dark : light)
  }
}

private func signalASIColor(_ rgb: UInt32) -> UIColor {
  UIColor(
    red: CGFloat(Double((rgb >> 16) & 0xFF) / 255.0),
    green: CGFloat(Double((rgb >> 8) & 0xFF) / 255.0),
    blue: CGFloat(Double(rgb & 0xFF) / 255.0),
    alpha: 1.0
  )
}

extension Color {
  static var signalASIPageBackground: Color { Color(signalASIColor(light: 0xF6F7F8, dark: 0x15171B)) }
  static var signalASIBarBackground: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x202329)) }
  static var signalASISurface: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x252930)) }
  static var signalASISearchBackground: Color { Color(signalASIColor(light: 0xE5E5EA, dark: 0x2B3038)) }
  static var signalASITextPrimary: Color { Color(signalASIColor(light: 0x111111, dark: 0xF2F4F7)) }
  static var signalASITextSecondary: Color { Color(signalASIColor(light: 0x8E8E93, dark: 0xA5ABB6)) }
  static var signalASIAgentSessionTitle: Color { Color(signalASIColor(light: 0x505052, dark: 0xCCD0D7)) }
  static var signalASIAccent: Color { Color(signalASIColor(light: 0x14C66A, dark: 0x19D36B)) }
  static var signalASISentBubble: Color { Color(signalASIColor(light: 0x95EC69, dark: 0x2E8B57)) }
  static var signalASIIncomingBubble: Color { Color(signalASIColor(light: 0xFFFFFF, dark: 0x252930)) }
  static var signalASIButtonSoft: Color { Color(signalASIColor(light: 0xE9EAEC, dark: 0x363B44)) }
  static var signalASIInputStroke: Color { Color(signalASIColor(light: 0xC7C7CC, dark: 0x363B44)) }
  static var signalASIUnreadRed: Color { Color(signalASIColor(light: 0xFF3B30, dark: 0xFF5A5F)) }
  static var signalASISeparator: Color { Color(signalASIColor(light: 0xE5E5EA, dark: 0x343841)) }
  static var signalASIInsightBackground: Color { Color(signalASIColor(light: 0xF2F6FE, dark: 0x202A36)) }
  static var signalASIInsightStroke: Color { Color(signalASIColor(light: 0xD8E6FB, dark: 0x34475C)) }
  static var signalASIInsightText: Color { Color(signalASIColor(light: 0x315B86, dark: 0xB8D5F2)) }
  static var signalASIAgentRecordingLight: Color { Color(signalASIColor(light: 0xDFF8D8, dark: 0x1F4637)) }
  static var signalASIAgentRecordingMid: Color { Color(signalASIColor(light: 0xA6ED82, dark: 0x246F43)) }
  static var signalASIAgentRecordingDeep: Color { Color(signalASIColor(light: 0x65D45C, dark: 0x198D43)) }
  static var signalASIAgentVoiceCancel: Color { Color(signalASIColor(light: 0xFF3B30, dark: 0xFF5A5F)) }
}

struct SignalASILogoView: View {
  var size: CGFloat
  var cornerRadius: CGFloat = 9

  var body: some View {
    Image("SignalASILogo")
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

struct SignalASITopBar<Leading: View, Trailing: View>: View {
  var title: String
  let leading: Leading
  let trailing: Trailing

  init(
    title: String,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.leading = leading()
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 0) {
      leading
        .frame(width: 40, height: 56)
      Text(title)
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .frame(maxWidth: .infinity, minHeight: 56)
      trailing
        .frame(width: 40, height: 56)
    }
    .padding(.horizontal, 16)
    .frame(height: 56)
    .background(Color.signalASIBarBackground)
  }
}

struct SignalASIBackButton: View {
  @Environment(\.presentationMode) private var presentationMode

  var body: some View {
    Button {
      presentationMode.wrappedValue.dismiss()
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
    }
  }
}

struct SignalASIAndroidIconButton: View {
  var systemName: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .frame(width: 40, height: 40)
    }
    .buttonStyle(.plain)
  }
}

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

  private var contact: SignalASIContact {
    store.contact(id: "hermes") ?? SignalASIContact.hermes()
  }

  private var activeAgentSession: AgentConversation? {
    store.agentSession(id: store.activeAgentConversationId)
  }

  private var callableTargets: [AgentCallableTarget] {
    AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
  }

  private var activeManualTarget: AgentCallableTarget? {
    guard modelSelection.mode == .manual else { return nil }
    let targetId = AgentCallableTargetCatalog.preferredTargetId(
      selection: modelSelection,
      targets: callableTargets
    )
    return callableTargets.first { $0.id == targetId }
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
    store.recentAgentTasks(limit: 24).filter { task in
      guard taskBelongsToActiveSession(task) else { return false }
      switch task.phase {
      case .observing, .planning, .waitingConfirmation, .executing, .verifying, .waitingResponse, .paused:
        return true
      case .cancelled, .blocked, .completed, .failed:
        return false
      }
    }
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

  private var cancellableAgentTask: AgentTaskRecord? {
    activeAgentTasks.first(where: AgentTaskCenterPolicy.cancellable)
  }

  private var primaryAgentTask: AgentTaskRecord? {
    activeAgentTasks.first(where: AgentTaskCenterPolicy.resumable) ?? cancellableAgentTask
  }

  private var primaryActionResumesTask: Bool {
    primaryAgentTask?.phase == .paused
  }

  private var blockedAgentTask: AgentTaskRecord? {
    let sessionId = activeAgentSession?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return store.recentAgentTasks(limit: 24).first { task in
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
      .onAppear {
        ensureActiveAgentSession()
        store.markContactRead(contact.id)
        refreshAgentRuntimeAuditRecords()
        modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
      }
      .onChange(of: store.activeAgentConversationId) { _ in
        modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
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
      } else if coordinator.requestDesktopArtifactDownload(payload) {
        runtimeArtifactStatus = t(
          "runtime_artifact.download_requested",
          "The Desktop was asked to resend this artifact."
        )
      } else {
        runtimeArtifactError = t(
          "runtime_artifact.download_failed",
          "The artifact could not be requested from the Desktop."
        )
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
          if hasOlderTranscriptMessages {
            Button {
              loadOlderTranscriptMessages()
            } label: {
              Label(
                t("signalasi.agent.load_older", "Load earlier messages"),
                systemImage: "arrow.up"
              )
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.signalASIInsightText)
              .frame(maxWidth: .infinity, minHeight: 40)
              .background(Color.signalASIInsightBackground)
              .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .stroke(Color.signalASIInsightStroke, lineWidth: 1)
              )
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("signalasi.agent.load_older", "Load earlier messages")))
          }
          if let pendingConfirmationTask {
            SignalASIAgentConfirmationCard(
              task: pendingConfirmationTask,
              onApproveOnce: {
                coordinator.approveLocalNativeAction(taskId: pendingConfirmationTask.taskId)
              },
              onApproveAlways: {
                coordinator.approveLocalNativeAction(
                  taskId: pendingConfirmationTask.taskId,
                  remember: true
                )
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
                "This task could not continue. Retry the original goal."
              ),
              retryTitle: t("signalasi.common.retry", "Retry"),
              retryingTitle: t("signalasi.agent_tasks.retrying", "Retrying task..."),
              isRetrying: retryingAgentTaskIDs.contains(blockedAgentTask.taskId)
            ) {
              retryBlockedAgentTask(blockedAgentTask)
            }
          }
          if messages.isEmpty &&
              !voiceTranscriptionPending &&
              pendingConfirmationTask == nil &&
              blockedAgentTask == nil &&
              activeExecutionTask == nil &&
              activeRemoteAgentTask == nil {
            VStack(spacing: 10) {
              SignalASILogoView(size: 48, cornerRadius: 10)
              Text(t("signalasi.agent.empty.title", "How can I help?"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
              Text(t("signalasi.agent.empty.subtitle", "Enter a goal or hold to talk"))
                .font(.system(size: 13))
                .foregroundColor(.signalASITextSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .accessibilityElement(children: .combine)
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
                detailsTitle: t("signalasi.agent.execution.timeline", "Execution timeline"),
                details: activeExecutionTask.executionLog,
                canResume: AgentTaskCenterPolicy.resumable(activeExecutionTask),
                resumeTitle: t("signalasi.agent.resume_task", "Resume task"),
                canCancel: AgentTaskCenterPolicy.cancellable(activeExecutionTask),
                cancelTitle: t("signalasi.common.cancel_task", "Cancel task")
              ) {
                resumeActiveAgentTask(activeExecutionTask)
              } onCancel: {
                cancelActiveAgentTask(activeExecutionTask)
              }
            }
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
            Button {
              transcriptAutoFollow = true
              transcriptShowLatestButton = false
              withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
                proxy.scrollTo(last.id, anchor: .bottom)
              }
            } label: {
              Label(
                t("signalasi.agent.latest", "Back to latest"),
                systemImage: "arrow.down"
              )
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
              .padding(.horizontal, 12)
              .frame(minHeight: 40)
              .background(Color.signalASIBarBackground)
              .overlay(
                Capsule(style: .continuous)
                  .stroke(Color.signalASIInputStroke, lineWidth: 0.8)
              )
              .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("signalasi.agent.latest", "Back to latest")))
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
    case .cancelled, .blocked, .completed, .failed:
      return phase.rawValue
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
    case "accepted", "queued", "starting", "recovering", "running":
      return t("signalasi.agent.remote_status.running", "Running")
    case "waiting_input":
      return t("signalasi.agent.remote_status.waiting_input", "Waiting for input")
    case "waiting_approval":
      return t("signalasi.agent.remote_status.waiting_approval", "Waiting for approval")
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
    let totalSeconds = max(0, (updatedAtMillis - startedAtMillis) / 1_000)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    if minutes > 0 {
      return t(
        "signalasi.agent.execution.duration_minutes",
        "Duration (minutes)m (seconds)s"
      )
    }
    return t("signalasi.agent.execution.duration_seconds", "Duration (seconds)s")
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
      _ = await coordinator.send(task.goal, to: contact)
      retryingAgentTaskIDs.remove(task.taskId)
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
    guard modelSelection.mode == .manual, activeManualTarget != nil else {
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
    if modelSelection.mode == .manual, activeManualTarget != nil {
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
      deviceInputPolicy: deviceInputPolicy,
      voiceSettings: agentVoiceSettings,
      focusRequest: composerFocusRequest,
      onRemoveAttachment: { attachment in
        attachments.removeAll { $0.id == attachment.id }
      },
      onNewSession: createAgentConversation,
      onTakePhoto: openCameraAttachmentPicker,
      onAddFile: {
        fileImporterPresented = true
      },
      onSend: { sendAgentMessage() },
      onPendingPrimaryAction: handlePendingAgentTaskAction,
      onVoiceStart: beginAgentVoiceCapture,
      onVoiceTranscript: sendAgentVoiceTranscript,
      t: t
    )
  }

  private func handlePendingAgentTaskAction() {
    guard let task = primaryAgentTask else { return }
    if task.phase == .paused {
      _ = coordinator.resumeLocalNativeAction(taskId: task.taskId)
    } else {
      coordinator.cancelLocalNativeAction(taskId: task.taskId)
    }
  }

  private var agentRuntimePanel: some View {
    SignalASIAgentRuntimePanelView(
      safetySettings: store.agentSafetySettings,
      modelPlannerSettings: store.modelPlannerSettings,
      taskBudget: store.agentTaskBudget,
      callableTargets: store.visibleContacts.count,
      currentGoal: draft,
      recentTasks: store.recentAgentTasks(limit: 12),
      nativeTools: AgentPhoneNativeToolCatalog.descriptors(),
      auditRecords: agentRuntimeAuditRecords,
      onCyclePermissionMode: cycleAgentPermissionMode,
      onToggleHighRiskGuard: {
        store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
      },
      onToggleMemoryCapture: {
        store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
      },
      t: t
    )
  }

  private func sendAgentMessage(
    voiceAttachmentSnapshot: [SignalASIDraftAttachment]? = nil
  ) {
    let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let outgoingAttachments = AgentVoiceAttachmentSubmissionPolicy.select(
      goalOverride: voiceAttachmentSnapshot == nil ? nil : cleanDraft,
      composerAttachments: attachments,
      attachmentSnapshot: voiceAttachmentSnapshot
    )
    let text = cleanDraft.ifBlank(attachmentLabel(for: outgoingAttachments))
    let agentGoal = cleanDraft.isEmpty && !outgoingAttachments.isEmpty
      ? t("agent_attachment_default_goal", "The user attached files without stating a task. Ask one concise question about what to do and offer four to six concrete actions suited to the file types. Mention only the file names; do not inspect, summarize, or return the attachments.")
      : ""
    draft = ""
    if let voiceAttachmentSnapshot {
      let consumedIDs = Set(outgoingAttachments.map(\.id))
      attachments.removeAll { consumedIDs.contains($0.id) }
    } else {
      attachments.removeAll()
    }
    actionTrayPresented = false
    attachmentError = ""
    Task {
      await coordinator.send(
        text,
        to: contact,
        attachments: outgoingAttachments,
        agentGoalOverride: agentGoal
      )
    }
  }

  private func sendAgentVoiceTranscript(_ transcript: String) {
    let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let capturedAttachments = voiceAttachmentSnapshot
    voiceAttachmentSnapshot.removeAll()
    guard !cleanTranscript.isEmpty else {
      attachmentError = t("voice_no_speech", "No speech captured.")
      return
    }
    draft = cleanTranscript
    sendAgentMessage(voiceAttachmentSnapshot: capturedAttachments)
  }

  private func beginAgentVoiceCapture() {
    voiceAttachmentSnapshot = attachments
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

  private func createAgentConversation() {
    _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
    draft = ""
    attachments.removeAll()
    actionTrayPresented = false
    attachmentError = ""
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

private struct SignalASIAgentBlockedTaskCard: View {
  var title: String
  var goal: String
  var subtitle: String
  var retryTitle: String
  var retryingTitle: String
  var isRetrying: Bool
  var onRetry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.octagon")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.orange)
          .frame(width: 20, height: 20)
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Spacer(minLength: 0)
      }
      Text(goal)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
      Text(subtitle)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: onRetry) {
        Label(
          isRetrying ? retryingTitle : retryTitle,
          systemImage: isRetrying ? "hourglass" : "arrow.clockwise"
        )
        .font(.system(size: 13, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 38)
      }
      .buttonStyle(.borderedProminent)
      .tint(.signalASIAccent)
      .disabled(isRetrying)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }
}

private struct SignalASIAgentRetryCard: View {
  var title: String
  var subtitle: String
  var retryTitle: String
  var retryingTitle: String
  var isRetrying: Bool
  var onRetry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.orange)
          .frame(width: 20, height: 20)
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Spacer(minLength: 0)
      }
      Text(subtitle)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: onRetry) {
        Label(
          isRetrying ? retryingTitle : retryTitle,
          systemImage: isRetrying ? "hourglass" : "arrow.clockwise"
        )
        .font(.system(size: 13, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 38)
      }
      .buttonStyle(.borderedProminent)
      .tint(.signalASIAccent)
      .disabled(isRetrying)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }
}

private struct SignalASIAgentExecutionStatusCard: View {
  @State private var detailsExpanded = false
  var executor: String
  var status: String
  var location: String
  var step: String
  var duration: String = ""
  var detailsTitle: String = ""
  var details: [String] = []
  var canResume: Bool
  var resumeTitle: String
  var canCancel: Bool
  var cancelTitle: String
  var onResume: () -> Void
  var onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Circle()
          .fill(Color.signalASIAccent)
          .frame(width: 8, height: 8)
        Text(executor)
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        Spacer(minLength: 6)
        Text(location)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.signalASIAccent)
          .lineLimit(1)
      }
      Text(status)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(2)
      Text(step)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      if !duration.isEmpty {
        Text(duration)
          .font(.system(size: 11))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
      }
      if !details.isEmpty {
        Button {
          detailsExpanded.toggle()
        } label: {
          Label(
            detailsTitle.ifBlank("Details"),
            systemImage: detailsExpanded ? "chevron.up" : "chevron.down"
          )
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.signalASIInsightText)
        }
        .buttonStyle(.plain)
        if detailsExpanded {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(details.suffix(8).enumerated()), id: \.offset) { _, detail in
              HStack(alignment: .top, spacing: 6) {
                Circle()
                  .fill(Color.signalASIInsightText)
                  .frame(width: 4, height: 4)
                  .padding(.top, 5)
                Text(detail)
                  .font(.system(size: 11))
                  .foregroundColor(.signalASITextSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .padding(.leading, 4)
        }
      }
      if canResume || canCancel {
        HStack(spacing: 8) {
          if canResume {
            Button(action: onResume) {
              Label(resumeTitle, systemImage: "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
          }
          if canCancel {
            Button(role: .destructive, action: onCancel) {
              Label(cancelTitle, systemImage: "xmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }
}

private struct AgentProcessCard: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var activePhase: AgentPhase?
  var executionPaused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(t("agent_section_process", "Process"))
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
      AgentProcessStepRow(
        number: 1,
        title: t("agent_step_observe", "Read current screen structure"),
        status: statusText(stepStatus(for: .observeScreen)),
        statusValue: stepStatus(for: .observeScreen)
      )
      AgentProcessStepRow(
        number: 2,
        title: t("agent_step_analyze", "Analyze user goal"),
        status: statusText(stepStatus(for: .analyzeGoal)),
        statusValue: stepStatus(for: .analyzeGoal)
      )
      AgentProcessStepRow(
        number: 3,
        title: t("agent_step_plan", "Build executable plan"),
        status: statusText(stepStatus(for: .buildPlan)),
        statusValue: stepStatus(for: .buildPlan)
      )
      AgentProcessStepRow(
        number: 4,
        title: t("agent_step_act", "Confirm before action"),
        status: statusText(stepStatus(for: .confirmAndAct)),
        statusValue: stepStatus(for: .confirmAndAct)
      )
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func stepStatus(for kind: AgentStepKind) -> AgentStepStatus {
    if executionPaused {
      return kind == .confirmAndAct ? .current : .done
    }
    switch activePhase {
    case .some(.observing):
      return kind == .observeScreen ? .current : (kind == .confirmAndAct ? .safe : .waiting)
    case .some(.planning):
      if kind == .observeScreen { return .done }
      return kind == .analyzeGoal ? .current : (kind == .confirmAndAct ? .safe : .waiting)
    case .some(.waitingConfirmation), .some(.executing), .some(.verifying), .some(.waitingResponse), .some(.paused):
      return kind == .confirmAndAct ? .current : .done
    case .some(.completed):
      return .done
    case .some(.cancelled), .some(.blocked), .some(.failed):
      return kind == .confirmAndAct ? .safe : .done
    case .none:
      return kind == .observeScreen ? .current : (kind == .confirmAndAct ? .safe : .waiting)
    }
  }

  private func statusText(_ status: AgentStepStatus) -> String {
    switch status {
    case .current:
      return t("agent_step_status_current", "Current")
    case .done:
      return t("agent_step_status_done", "Done")
    case .waiting:
      return t("agent_step_status_waiting", "Waiting")
    case .safe:
      return t("agent_step_status_safe", "Safe")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentProcessStepRow: View {
  var number: Int
  var title: String
  var status: String
  var statusValue: AgentStepStatus

  private var isCurrent: Bool { statusValue == .current }
  private var isDone: Bool { statusValue == .done }
  private var tint: Color {
    switch statusValue {
    case .current, .done:
      return .signalASIAccent
    case .safe:
      return .signalASITextSecondary
    case .waiting:
      return .signalASITextSecondary
    }
  }

  var body: some View {
    HStack(spacing: 10) {
      Circle()
        .fill(isCurrent ? Color.signalASIAccent : (isDone ? Color.signalASIAccent.opacity(0.14) : Color.signalASISurface))
        .overlay(
          Circle()
            .stroke(isCurrent || isDone ? Color.signalASIAccent : Color.signalASISeparator, lineWidth: 1)
        )
        .overlay(
          Text("\(number)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(isCurrent ? .white : tint)
        )
        .frame(width: 24, height: 24)
      Text(title)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
      Spacer(minLength: 8)
      Text(status)
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(tint)
        .lineLimit(1)
    }
    .padding(.horizontal, 14)
    .frame(minHeight: 50)
    .background(Color.signalASIInsightBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentInfoCard: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var currentApp: String
  var callableTargets: Int
  var runningTasks: Int
  var memorySnapshot: AgentMemorySnapshot
  var knowledgeStats: AgentKnowledgeStats

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(t("agent_section_info", "Info"))
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
      VStack(spacing: 0) {
        infoValueRow(String(format: t("agent_current_app_value", "Current app: %@"), currentApp))
        separator
        infoValueRow(String(format: t("agent_callable_targets_value", "Callable targets: %d"), callableTargets))
        separator
        infoValueRow(String(format: t("agent_running_tasks_value", "Running tasks: %d"), runningTasks))
        separator
        NavigationLink(destination: SignalASIAgentMemoryView()) {
          infoNavigationRow(
            String(format: t("agent_memory_value", "Memory: %d / conflicts: %d"), memorySnapshot.activeCount, memorySnapshot.conflicts.count),
            systemImage: "brain"
          )
        }
        .buttonStyle(.plain)
        separator
        NavigationLink(destination: SignalASIAgentKnowledgeView()) {
          infoNavigationRow(
            String(format: t("agent_knowledge_value", "Knowledge: %d items / %d sources / %d hits"), knowledgeStats.itemCount, knowledgeStats.sourceCount, 0),
            systemImage: "books.vertical"
          )
        }
        .buttonStyle(.plain)
      }
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .font(.system(size: 13))
    .foregroundColor(.signalASIInsightText)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.signalASISeparator)
      .frame(height: 0.5)
      .padding(.leading, 14)
  }

  private func infoValueRow(_ value: String) -> some View {
    Text(value)
      .font(.system(size: 13))
      .foregroundColor(.signalASITextPrimary)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      .padding(.horizontal, 14)
  }

  private func infoNavigationRow(_ value: String, systemImage: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.signalASIAccent)
        .frame(width: 18)
      Text(value)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.signalASITextSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 42)
    .padding(.horizontal, 14)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct DiscoverView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var myQRCodePresented = false

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        SignalASITopBar(
          title: t("signalasi.discover.title", "Discover"),
          leading: { SignalASIBackButton() },
          trailing: { Color.clear }
        )
        ScrollView {
          VStack(spacing: 10) {
            SignalASIAndroidMenuGroup {
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.ai_agent_title", "AI Agent"),
                subtitle: t("signalasi.discover.ai_agent_subtitle", "Explore powerful AI assistants"),
                systemImage: "cpu",
                assetImageName: "DiscoverAiAgent",
                tint: .signalASIAccent
              ) {
                SignalASIMyAgentsView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.add_cloud_model", "Add Cloud Model"),
                subtitle: t(
                  "signalasi.discover.add_cloud_model_subtitle",
                  "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"
                ),
                systemImage: "cloud.fill",
                assetImageName: "DiscoverAiAgent",
                tint: .signalASIInsightText
              ) {
                CloudModelProviderSelectionView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.device_center", "Device Center"),
                subtitle: t("signalasi.discover.device.subtitle", "Manage and control your devices"),
                systemImage: "antenna.radiowaves.left.and.right",
                assetImageName: "DiscoverDevice",
                tint: .signalASIAccent
              ) {
                DeviceManagementView()
              }
            }
            SignalASIAndroidMenuGroup {
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.automation.title", "Automation"),
                subtitle: t("signalasi.automation.hero_subtitle", "Create and manage automated tasks"),
                systemImage: "clock",
                assetImageName: "DiscoverAutomation",
                tint: .orange
              ) {
                SignalASIAutomationView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.security_center_title", "Security Center"),
                subtitle: t("signalasi.discover.security_center_subtitle", "View security status and permissions"),
                systemImage: "checkmark.shield",
                assetImageName: "DiscoverSecurity",
                tint: .signalASIAccent
              ) {
                SignalASISecurityCenterView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.lab_title", "Lab"),
                subtitle: t("signalasi.discover.lab_subtitle", "Explore frontier features"),
                systemImage: "sparkles",
                assetImageName: "DiscoverLab",
                tint: .purple
              ) {
                SignalASILocalModelLabView()
              }
            }
            SignalASIAndroidMenuGroup {
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.scan_title", "Scan"),
                subtitle: t("signalasi.discover.scan_subtitle", "Add contacts or devices"),
                systemImage: "qrcode.viewfinder",
                assetImageName: "DiscoverScan",
                tint: .signalASIAccent
              ) {
                AddContactView(autoOpenScanner: true)
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuButton(
                title: t("signalasi.discover.my_qr_title", "My QR Code"),
                subtitle: t("signalasi.discover.my_qr_subtitle", "Show this device identity"),
                systemImage: "qrcode",
                assetImageName: "DiscoverScan",
                tint: .signalASITextPrimary
              ) {
                myQRCodePresented = true
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("signalasi.discover.create_group_title", "Create Group"),
                subtitle: t("signalasi.discover.create_group_subtitle", "Secure multi-person communication"),
                systemImage: "person.3",
                assetImageName: "DiscoverGroup",
                tint: .signalASIAccent
              ) {
                SignalASICreateGroupView()
              }
            }
            SignalASIAndroidMenuGroup {
              SignalASIAndroidGroupedMenuLink(
                title: t("cc_profile_title", "My SignalASI"),
                subtitle: t("cc_profile_subtitle_ios", "Identity protected by the iOS security boundary"),
                systemImage: "person.crop.circle",
                assetImageName: "DiscoverProfile",
                tint: .signalASITextPrimary
              ) {
                SignalASIProfileIdentityView()
              }
              SignalASIAndroidMenuDivider()
              SignalASIAndroidGroupedMenuLink(
                title: t("settings_my_signalasi", "My SignalASI"),
                subtitle: t("cc_product_subtitle", "Agent operating system - This device online"),
                systemImage: "slider.horizontal.3",
                assetImageName: "DiscoverSignalASI",
                tint: .signalASIAccent
              ) {
                SignalASIControlCenterView()
              }
            }
            SignalASIAndroidMenuLink(
              title: t("cc_learning_title", "Learning & Skill Evolution"),
              subtitle: t("cc_learning_subtitle", "Learn from successful tasks; generated content requires review"),
              systemImage: "sparkles.rectangle.stack",
              tint: .purple
            ) {
              SignalASILearningSkillEvolutionView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_agent_core_title", "Agent Core"),
              subtitle: t("cc_agent_core_subtitle", "Planning, tool use, replanning, and recovery"),
              systemImage: "cpu",
              tint: .signalASIAccent
            ) {
              SignalASIAgentCoreView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_permissions_title", "Permissions & Audit"),
              subtitle: t("cc_recent_operations_subtitle", "Review native tools, Agent actions, and confirmation decisions"),
              systemImage: "hand.raised",
              tint: .orange
            ) {
              SignalASIPermissionsAuditView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_app_services_page_title", "Apps & Services"),
              subtitle: t("cc_app_services_subtitle", "App modules, media, contacts, providers, and notifications"),
              systemImage: "square.grid.2x2",
              tint: .signalASIInsightText
            ) {
              SignalASIAppServicesView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
              subtitle: t("cc_privacy_dashboard_subtitle", "See what data leaves this phone and where it is processed"),
              systemImage: "lock.doc",
              tint: .signalASIInsightText
            ) {
              SignalASIPrivacyDashboardView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_data_title", "Data & Backup"),
              subtitle: t("cc_data_subtitle", "Encrypted export, restore, storage, and cache"),
              systemImage: "externaldrive",
              tint: .signalASIInsightText
            ) {
              SignalASIDataBackupView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_execution_policy_title", "Execution Policy"),
              subtitle: t("cc_permission_mode_banner_subtitle", "This setting is enforced by the local safety policy before every action."),
              systemImage: "checkmark.shield",
              tint: .orange
            ) {
              SignalASIExecutionPolicyView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_system_status_title", "System Status"),
              subtitle: systemStatusSubtitle,
              systemImage: systemStatusIcon,
              tint: systemStatusTint
            ) {
              SignalASISystemStatusView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.pairing", "Pairing"),
              subtitle: t("signalasi.discover.pairing.subtitle", "Scan QR codes and connect SignalASI Desktop"),
              systemImage: "qrcode.viewfinder",
              tint: .signalASIAccent
            ) {
              PairingView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.agent_memory.telemetry_title", "Agent Memory"),
              subtitle: t("signalasi.agent_memory.telemetry_subtitle", "iOS resident memory sampled across active Agent tasks"),
              systemImage: "memorychip",
              tint: .purple
            ) {
              SignalASIAgentMemoryTelemetryView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.voice", "Voice"),
              subtitle: t("signalasi.discover.voice.subtitle", "Wake, transcription and local voice models"),
              systemImage: "waveform",
              tint: .signalASIInsightText
            ) {
              SignalASIVoiceControlCenterView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_app_tools_title", "Apps & Tools"),
              subtitle: t("cc_apps_subtitle", "Messaging, calendar, browser, files, and adapters"),
              systemImage: "rectangle.3.group",
              tint: .blue
            ) {
              SignalASIAppToolsView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_general_page_title", "General"),
              subtitle: t("signalasi.general_settings.subtitle", "Language, appearance, text size, notifications, and app information"),
              systemImage: "gearshape",
              tint: .signalASIInsightText
            ) {
              SignalASIGeneralControlCenterView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_runtime_title", "On-device Linux Runtime"),
              subtitle: t("cc_runtime_subtitle", "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"),
              systemImage: "terminal",
              tint: .teal
            ) {
              SignalASIOnDeviceRuntimeView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_nodes_title", "Agents, Models & Nodes"),
              subtitle: t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"),
              systemImage: "link.circle",
              tint: .signalASIInsightText
            ) {
              SignalASIAgentsModelsNodesView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_smart_spaces_title", "Smart Spaces"),
              subtitle: t("cc_spaces_subtitle", "Home Assistant and custom devices"),
              systemImage: "house",
              tint: .purple
            ) {
              SignalASISmartSpacesView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_resource_routing_title", "Models & Resource Routing"),
              subtitle: t("cc_resource_routing_subtitle", "Choose by quality, latency, privacy, cost, and availability"),
              systemImage: "point.3.connected.trianglepath.dotted",
              tint: .blue
            ) {
              SignalASIResourceRoutingView()
            }
            SignalASIAndroidMenuLink(
              title: t("cc_phone_title", "Phone Capabilities"),
              subtitle: phoneCapabilitiesSummary,
              systemImage: "iphone",
              tint: nativeToolSummary.available > 0 ? .signalASIAccent : .orange
            ) {
              SignalASIPhoneCapabilitiesView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.model_planner", "Model Planner"),
              subtitle: t("signalasi.discover.planner.subtitle", "Agent planning, budget and model routing"),
              systemImage: "slider.horizontal.3",
              tint: .signalASIInsightText
            ) {
              AgentModelPlannerSettingsView()
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .sheet(isPresented: $myQRCodePresented) {
        MyContactQRCodeView()
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private var nativeToolSummary: (total: Int, available: Int, needingAttention: Int) {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return (tools.count, available, max(tools.count - available, 0))
  }

  private var phoneCapabilitiesSummary: String {
    String(
      format: t("cc_phone_subtitle", "%d native tools - %d need attention"),
      nativeToolSummary.available,
      nativeToolSummary.needingAttention
    )
  }

  private var systemStatusIcon: String {
    systemStatusNeedsAttention ? "exclamationmark.triangle" : "checkmark.shield"
  }

  private var systemStatusTint: Color {
    systemStatusNeedsAttention ? .orange : .signalASIAccent
  }

  private var systemStatusSubtitle: String {
    systemStatusNeedsAttention
      ? t("cc_services_need_attention_subtitle", "Unavailable resources are excluded from automatic routing")
      : t("cc_all_services_normal_subtitle", "Local execution, routing, messaging, and security are available")
  }

  private var systemStatusNeedsAttention: Bool {
    store.agentSafetySettings.executionPaused ||
      !systemStatusLinkReady ||
      systemStatusAvailableResourceCount == 0
  }

  private var systemStatusLinkReady: Bool {
    store.serverLinks.contains(where: \.paired) &&
      SignalASILinkTransportDiagnostics.snapshot().failureCount == 0
  }

  private var systemStatusAvailableResourceCount: Int {
    store.cloudModelContacts.count +
      store.serverLinks.filter(\.paired).count +
      store.customDeviceConnectors.filter(\.enabled).count
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

private struct SignalASIAndroidMenuGroup<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIAndroidGroupedMenuLink<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String?
  var tint: Color
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    assetImageName: String? = nil,
    tint: Color,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.assetImageName = assetImageName
    self.tint = tint
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      SignalASIAndroidGroupedMenuRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        assetImageName: assetImageName,
        tint: tint
      )
    }
    .buttonStyle(.plain)
  }
}

private struct SignalASIAndroidGroupedMenuButton: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String? = nil
  var tint: Color
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      SignalASIAndroidGroupedMenuRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        assetImageName: assetImageName,
        tint: tint
      )
    }
    .buttonStyle(.plain)
  }
}

private struct SignalASIAndroidGroupedMenuRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var assetImageName: String?
  var tint: Color

  var body: some View {
    HStack(spacing: 12) {
      SignalASIAndroidMenuIcon(systemImage: systemImage, assetImageName: assetImageName, tint: tint)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
  }
}

private struct SignalASIAndroidMenuIcon: View {
  var systemImage: String
  var assetImageName: String?
  var tint: Color

  var body: some View {
    ZStack {
      if let assetImageName {
        Image(assetImageName)
          .resizable()
          .renderingMode(.original)
          .scaledToFit()
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
    }
    .frame(width: 42, height: 42)
  }
}

private struct SignalASIAndroidMenuDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.signalASISeparator)
      .frame(height: 0.5)
      .padding(.leading, 66)
  }
}

private struct SignalASIAndroidMenuLink<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.16))
          Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tint)
        }
        .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

private struct SignalASIAndroidMenuButton: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.16))
          Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tint)
        }
        .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
