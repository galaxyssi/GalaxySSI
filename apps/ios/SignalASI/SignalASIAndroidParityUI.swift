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
  @State private var fileImporterPresented = false
  @State private var cameraPickerPresented = false
  @State private var attachmentError = ""
  @State private var selectedMessageForDetails: ChatMessage?
  @State private var composerFocusRequest = 0
  @State private var agentRuntimeAuditRecords: [AgentNativeToolAuditRecord] = []

  private var contact: SignalASIContact {
    store.contact(id: "hermes") ?? SignalASIContact.hermes()
  }

  private var messages: [ChatMessage] {
    store.messages(for: contact.id)
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
      switch task.phase {
      case .observing, .planning, .waitingConfirmation, .executing, .verifying, .waitingResponse, .paused:
        return true
      case .cancelled, .blocked, .completed, .failed:
        return false
      }
    }
  }

  private var activeAgentPhase: AgentPhase? {
    activeAgentTasks.first?.phase
  }

  private var deviceInputPolicy: AgentDeviceInputTargetPolicy {
    AgentDeviceProfileDetector.detect().inputTargetPolicy
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
        agentOutput
        Divider()
          .background(Color.signalASISeparator)
        agentComposer
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .onAppear {
        store.markContactRead(contact.id)
        refreshAgentRuntimeAuditRecords()
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
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private var agentOutput: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 10) {
          agentRuntimePanel
          SignalASIAgentScreenContextCard(
            screen: agentScreenSnapshot.screen,
            sections: agentScreenSnapshot.sections,
            onCommand: prefillAgentScreenCommand,
            t: t
          )
          AgentProcessCard(
            activePhase: activeAgentPhase,
            executionPaused: store.agentSafetySettings.executionPaused
          )
          AgentInfoCard(
            currentApp: "SignalASI iOS",
            callableTargets: store.visibleContacts.count,
            runningTasks: activeAgentTasks.count,
            memorySnapshot: store.agentMemorySnapshot(),
            knowledgeStats: store.agentKnowledgeStats
          )
          if messages.isEmpty {
            AgentInsightBanner(
              unreadTotal: unreadTotal,
              runningTasks: activeAgentTasks.count,
              callableTargets: store.visibleContacts.count,
              executionPaused: store.agentSafetySettings.executionPaused,
              nativeToolSummary: nativeToolSummary
            )
          } else {
            ForEach(messages) { message in
              MessageBubble(message: message)
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
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 16)
      }
      .background(Color.signalASIPageBackground)
      .onChange(of: messages.count) { _ in
        if let last = messages.last {
          withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
        store.markContactRead(contact.id)
        refreshAgentRuntimeAuditRecords()
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
        Text(t("signalasi.agent.brand.subtitle", "Super Agent"))
          .font(.system(size: 10, weight: .regular))
          .foregroundColor(.signalASITextSecondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 4) {
        Text(t("signalasi.agent.session.new", "New session"))
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.signalASIAgentSessionTitle)
          .lineLimit(1)
        Text(unreadTotal > 0 ? String(format: t("signalasi.agent.unread", "%d unread"), unreadTotal) : t("signalasi.agent.tab.subtitle", "Phone-native super agent"))
          .font(.system(size: 10, weight: .regular))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
      }
      .frame(width: 96, alignment: .trailing)
      NavigationLink(destination: OnDeviceAgentPermissionsView()) {
        Image(systemName: "cpu")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .frame(width: 36, height: 44)
      }
      .buttonStyle(.plain)
      NavigationLink(destination: SettingsView()) {
        Image(systemName: "ellipsis")
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .frame(width: 36, height: 44)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(height: 76)
    .background(Color.signalASIPageBackground)
  }

  private var agentComposer: some View {
    SignalASIAgentComposerView(
      draft: $draft,
      actionTrayPresented: $actionTrayPresented,
      attachments: attachments,
      attachmentError: attachmentError,
      canSend: canSend,
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
      onSend: sendAgentMessage,
      onVoiceTranscript: sendAgentVoiceTranscript,
      t: t
    )
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

  private func sendAgentMessage() {
    let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let outgoingAttachments = attachments
    let text = cleanDraft.ifBlank(attachmentLabel(for: outgoingAttachments))
    let agentGoal = cleanDraft.isEmpty && !outgoingAttachments.isEmpty
      ? t("agent_attachment_default_goal", "The user attached files without stating a task. Ask one concise question about what to do and offer four to six concrete actions suited to the file types. Mention only the file names; do not inspect, summarize, or return the attachments.")
      : ""
    draft = ""
    attachments.removeAll()
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
    guard !cleanTranscript.isEmpty else {
      attachmentError = t("voice_no_speech", "No speech captured.")
      return
    }
    draft = cleanTranscript
    sendAgentMessage()
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
          leading: { Color.clear },
          trailing: { Color.clear }
        )
        ScrollView {
          VStack(spacing: 10) {
            SignalASIAndroidMenuLink(
              title: t("cc_profile_title", "My SignalASI"),
              subtitle: t("cc_profile_subtitle_ios", "Identity protected by the iOS security boundary"),
              systemImage: "person.crop.circle",
              tint: .signalASITextPrimary
            ) {
              SignalASIProfileIdentityView()
            }
            SignalASIAndroidMenuLink(
              title: t("settings_my_signalasi", "My SignalASI"),
              subtitle: t("cc_product_subtitle", "Agent operating system - This device online"),
              systemImage: "slider.horizontal.3",
              tint: .signalASIAccent
            ) {
              SignalASIControlCenterView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.ai_agent_title", "AI Agent"),
              subtitle: t("signalasi.discover.ai_agent_subtitle", "Explore powerful AI assistants"),
              systemImage: "cpu",
              tint: .signalASIAccent
            ) {
              SignalASIMyAgentsView()
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
              title: t("signalasi.discover.scan_title", "Scan"),
              subtitle: t("signalasi.discover.scan_subtitle", "Add contacts or devices"),
              systemImage: "qrcode.viewfinder",
              tint: .signalASIAccent
            ) {
              AddContactView(autoOpenScanner: true)
            }
            SignalASIAndroidMenuButton(
              title: t("signalasi.discover.my_qr_title", "My QR Code"),
              subtitle: t("signalasi.discover.my_qr_subtitle", "Show this device identity"),
              systemImage: "qrcode",
              tint: .signalASITextPrimary
            ) {
              myQRCodePresented = true
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.create_group_title", "Create Group"),
              subtitle: t("signalasi.discover.create_group_subtitle", "Secure multi-person communication"),
              systemImage: "person.3",
              tint: .signalASIAccent
            ) {
              SignalASICreateGroupView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.security_center_title", "Security Center"),
              subtitle: t("signalasi.discover.security_center_subtitle", "View security status and permissions"),
              systemImage: "checkmark.shield",
              tint: .signalASIAccent
            ) {
              SignalASISecurityCenterView()
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
              SignalASIGeneralSettingsView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.automation.title", "Automation"),
              subtitle: t("signalasi.automation.hero_subtitle", "Let AI actively handle fixed tasks"),
              systemImage: "clock",
              tint: .orange
            ) {
              SignalASIAutomationView()
            }
            SignalASIAndroidMenuLink(
              title: t("signalasi.discover.lab_title", "Lab"),
              subtitle: t("signalasi.discover.lab_subtitle", "Explore frontier features"),
              systemImage: "sparkles",
              tint: .purple
            ) {
              SignalASILocalModelLabView()
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
              title: t("signalasi.discover.device_center", "Device Center"),
              subtitle: t("signalasi.discover.device.subtitle", "Custom devices, Home Assistant and connectors"),
              systemImage: "antenna.radiowaves.left.and.right",
              tint: .signalASIAccent
            ) {
              DeviceManagementView()
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
