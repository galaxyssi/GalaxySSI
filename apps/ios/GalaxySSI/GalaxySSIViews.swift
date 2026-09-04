import AVFoundation
import BackgroundTasks
import CoreImage
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

private let galaxySSIStartupLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "com.galaxyssi.chat.ios",
  category: "startup"
)

enum GalaxySSIRuntimePlaintextProtection {
  private static let transientPrefixes = [
    "agent_audio_",
    "galaxyssi_tts_",
    "voice_",
    "voice_cmd_"
  ]
  private static let transientDirectories: Set<String> = [
    "debug-agent-inputs",
    "decrypted",
    "diagnostics",
    "plaintext-previews",
    "peer-voice-drafts",
    "peer-voice-recordings"
  ]
  private static let nestedTransientDirectories = ["galaxyssi/visible-capture"]
  private static let boundaryLock = NSLock()
  private static var boundaryActive = false

  static var sensitiveDiagnosticsEnabled: Bool {
#if DEBUG
    true
#else
    false
#endif
  }

  static func enterRuntimeBoundary(
    notificationCenter: NotificationCenter = .default,
    fileManager: FileManager = .default
  ) {
    guard setBoundaryActive(true) else { return }
    GalaxySSIRichMediaPlaybackCoordinator.shared.pauseForRuntimeBoundary()
    GalaxySSIPeerImageThumbnailRepository.shared.clearMemoryCache()
    notificationCenter.post(name: .galaxySSIRuntimePlaintextWillClear, object: nil)
    clearKnownTemporaryFiles(fileManager: fileManager)
  }

  static func leaveRuntimeBoundary(notificationCenter: NotificationCenter = .default) {
    guard setBoundaryActive(false) else { return }
    notificationCenter.post(name: .galaxySSIRuntimePlaintextDidRestore, object: nil)
  }

  static func clearKnownTemporaryFiles(
    fileManager: FileManager = .default,
    roots: [URL]? = nil
  ) {
    let cleanupRoots = roots ?? [fileManager.temporaryDirectory] +
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
    for root in cleanupRoots.map(\.standardizedFileURL) {
      for directory in transientDirectories {
        try? fileManager.removeItem(at: root.appendingPathComponent(directory, isDirectory: true))
      }
      for directory in nestedTransientDirectories {
        try? fileManager.removeItem(at: root.appendingPathComponent(directory, isDirectory: true))
      }
      guard let children = try? fileManager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      ) else { continue }
      for child in children {
        let values = try? child.resourceValues(forKeys: [.isRegularFileKey])
        if values?.isRegularFile == true,
           transientPrefixes.contains(where: { child.lastPathComponent.hasPrefix($0) }) {
          try? fileManager.removeItem(at: child)
        }
      }
    }
  }

  private static func setBoundaryActive(_ active: Bool) -> Bool {
    boundaryLock.lock()
    defer { boundaryLock.unlock() }
    guard boundaryActive != active else { return false }
    boundaryActive = active
    return true
  }
}

extension Data {
  mutating func wipeSensitive() {
    guard !isEmpty else { return }
    resetBytes(in: startIndex..<endIndex)
    removeAll(keepingCapacity: false)
  }
}

extension Array where Element == Int16 {
  mutating func wipeSensitive() {
    for index in indices {
      self[index] = 0
    }
    removeAll(keepingCapacity: false)
  }
}

extension Notification.Name {
  static let galaxySSIOpenContact = Notification.Name("galaxyssi.open_contact")
  static let galaxySSIRuntimePlaintextWillClear = Notification.Name(
    "galaxyssi.runtime_plaintext_will_clear"
  )
  static let galaxySSIRuntimePlaintextDidRestore = Notification.Name(
    "galaxyssi.runtime_plaintext_did_restore"
  )
}

final class GalaxySSIAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    galaxySSIStartupLogger.notice("UIApplication finished launching")
    GalaxySSIAttachmentAtRestCipher.removeLegacyPlaintextRoots()
    GalaxySSIRuntimePlaintextProtection.clearKnownTemporaryFiles()
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard GalaxySSIContactNotificationPresentationPolicy.shouldPresent(
      userInfo: notification.request.content.userInfo,
      applicationIsActive: UIApplication.shared.applicationState == .active
    ) else {
      completionHandler([])
      return
    }
    completionHandler([.banner, .sound, .badge])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let contactId = (response.notification.request.content.userInfo[
      GalaxySSIContactNotificationPresentationPolicy.contactIdKey
    ] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !contactId.isEmpty {
      UserDefaults.standard.set(contactId, forKey: "galaxyssi.pending_open_contact")
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .galaxySSIOpenContact,
          object: nil,
          userInfo: ["contactId": contactId]
        )
      }
    }
    completionHandler()
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if identifier == AgentIOSDefaultDownloadProvider.backgroundSessionIdentifier {
      AgentIOSDefaultDownloadProvider.shared.handleBackgroundEvents(
        identifier: identifier,
        completionHandler: completionHandler
      )
    } else if identifier == LocalModelArtifactDownloadCoordinator.backgroundSessionIdentifier {
      LocalModelArtifactDownloadCoordinator.handleBackgroundEvents(
        identifier: identifier,
        completionHandler: completionHandler
      )
    } else {
      completionHandler()
    }
  }
}

@MainActor
final class GalaxySSIStartupRuntime {
  let store: GalaxySSIStore
  let coordinator: MessageCoordinator
  let agentStartupRecovery: AgentStartupRecoveryCoordinator
  let voiceAgentRunRecovery: VoiceAgentRunRecoveryCoordinator
  let workflowTriggerCoordinator: AgentWorkflowTriggerCoordinator
  let backgroundScheduler: AgentProactiveBackgroundScheduler

  init() {
    galaxySSIStartupLogger.notice("GalaxySSI runtime restoration started")
    let store = GalaxySSIStore()
    let coordinator = MessageCoordinator(store: store)
    self.store = store
    self.coordinator = coordinator
    self.agentStartupRecovery = AgentStartupRecoveryCoordinator()
    self.voiceAgentRunRecovery = .shared
    self.workflowTriggerCoordinator = AgentWorkflowTriggerCoordinator(coordinator: coordinator)
    self.backgroundScheduler = AgentProactiveBackgroundScheduler(store: store, coordinator: coordinator)
    galaxySSIStartupLogger.notice("GalaxySSI runtime restoration finished")
  }
}

@MainActor
final class GalaxySSIStartupHandoff: ObservableObject {
  @Published private(set) var runtime: GalaxySSIStartupRuntime?
  private var started = false
  private var scenePhase: ScenePhase = .active

  func start() {
    guard !started else { return }
    started = true
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: Self.minimumVisibleNanoseconds)
      guard let self, !Task.isCancelled else { return }
      let runtime = GalaxySSIStartupRuntime()
      self.runtime = runtime
      applyScenePhase(to: runtime.store)
    }
  }

  func handleScenePhase(_ phase: ScenePhase) {
    scenePhase = phase
    guard let store = runtime?.store else { return }
    applyScenePhase(to: store)
  }

  private func applyScenePhase(to store: GalaxySSIStore) {
    if scenePhase == .active {
      store.restoreRuntimePlaintextAfterForeground()
      GalaxySSIRuntimePlaintextProtection.leaveRuntimeBoundary()
    } else {
      store.clearRuntimePlaintextForBackground()
      GalaxySSIRuntimePlaintextProtection.enterRuntimeBoundary()
    }
  }

  static let minimumVisibleNanoseconds: UInt64 = 300_000_000
}

@main
struct GalaxySSIApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @UIApplicationDelegateAdaptor(GalaxySSIAppDelegate.self) private var appDelegate
  @StateObject private var startup = GalaxySSIStartupHandoff()

  var body: some Scene {
    WindowGroup {
      Group {
        if let runtime = startup.runtime {
          GalaxySSIRuntimeRoot(runtime: runtime)
        } else {
          GalaxySSIStartupHandoffView()
        }
      }
      .onAppear(perform: startup.start)
      .onChange(of: scenePhase, perform: startup.handleScenePhase)
    }
  }
}

private struct GalaxySSIRuntimeRoot: View {
  let runtime: GalaxySSIStartupRuntime

  var body: some View {
    RootView()
      .environmentObject(runtime.store)
      .environmentObject(runtime.coordinator)
      .environmentObject(runtime.agentStartupRecovery)
      .environmentObject(runtime.voiceAgentRunRecovery)
      .galaxySSITextScale(runtime.store.displaySettings)
      .onAppear {
        galaxySSIStartupLogger.notice("RootView appeared")
        runtime.coordinator.start()
        runtime.agentStartupRecovery.start(store: runtime.store)
        runtime.voiceAgentRunRecovery.start()
        runtime.workflowTriggerCoordinator.start()
        runtime.backgroundScheduler.start()
        requestNotificationPermissionIfNeeded()
      }
  }

  private func requestNotificationPermissionIfNeeded() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      Task { @MainActor in
        _ = await NotificationService.requestAuthorization()
      }
    }
  }
}

private struct GalaxySSIStartupHandoffView: View {
  @State private var animated = false

  var body: some View {
    ZStack {
      Color.galaxySSIPageBackground.ignoresSafeArea()
      VStack(spacing: 18) {
        GalaxySSILogoView(size: 76, cornerRadius: 16)
          .scaleEffect(animated ? 1 : 0.94)
          .opacity(animated ? 1 : 0.72)
        ProgressView()
          .progressViewStyle(CircularProgressViewStyle(tint: .galaxySSIAccent))
          .accessibilityLabel(Text(GalaxySSILocalization.string(
            "galaxyssi.startup.loading",
            fallback: "Loading GalaxySSI",
            language: Locale.preferredLanguages.first ?? "en"
          )))
      }
    }
    .onAppear {
      withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
        animated = true
      }
    }
  }
}

struct RootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var systemLocaleRevision = 0

  private var interfaceLanguage: String {
    // Re-evaluate automatic language after iOS reports a locale or time change.
    _ = systemLocaleRevision
    return LanguagePolicySettings.resolveInterface(store.languagePolicy.interfaceLanguage)
  }

  var body: some View {
    ZStack {
      GalaxySSIMainTabView()
        .accentColor(.galaxySSIAccent)
        .galaxySSIInterfaceLanguage(interfaceLanguage)
        .id(interfaceLanguage)
      if scenePhase != .active {
        Color.galaxySSIPageBackground
          .ignoresSafeArea()
          .accessibilityHidden(true)
      }
    }
      .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
        systemLocaleRevision &+= 1
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
        systemLocaleRevision &+= 1
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
        systemLocaleRevision &+= 1
      }
      .task {
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled else { return }
        await GalaxySSINavigationContentPrewarm.prepare(store: store)
      }
  }
}

private extension View {
  @ViewBuilder
  func galaxySSITextScale(_ settings: AppDisplaySettings) -> some View {
    if let size = settings.textScale.dynamicTypeSize {
      dynamicTypeSize(size)
    } else {
      self
    }
  }

}

private extension AppTextScaleMode {
  var dynamicTypeSize: DynamicTypeSize? {
    switch self {
    case .system:
      return nil
    case .standard:
      return .large
    case .comfortable:
      return .xLarge
    case .large:
      return .xxLarge
    case .extraLarge:
      return .xxxLarge
    }
  }
}

private struct GalaxySSIConversationVoiceRiskConfirmation: Identifiable {
  let id = UUID()
  var transcript: String
  var risk: VoiceCommandRisk
  var correctionReview: VoiceTranscriptCorrectionReview?
  var sessionId: String
}

struct ConversationView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var draft = ""
  @State private var attachments: [GalaxySSIDraftAttachment] = []
  @State private var attachmentMenuPresented = false
  @State private var fileImporterPresented = false
  @State private var cameraPickerPresented = false
  @State private var cameraTargetContactId = ""
  @State private var attachmentError = ""
  @State private var composerTextModeActive = false
  @State private var retryingMessageIDs: Set<UUID> = []
  @State private var transcribingVoiceMessageIDs: Set<UUID> = []
  @State private var peerVoiceTranscriptionError = ""
  @State private var cloudModelSwitchPresented = false
  @State private var runtimeArtifactPreview: GalaxySSIRuntimeArtifactPreview?
  @State private var runtimeArtifactDocument: GalaxySSIRuntimeArtifactDocument?
  @State private var runtimeArtifactExportPresented = false
  @State private var runtimeArtifactExportFilename = ""
  @State private var runtimeArtifactError = ""
  @State private var agentSessionsShortcutActive = false
  @State private var scanShortcutActive = false
  @State private var visibleMessageCount = 100
  @State private var loadingOlderMessages = false
  @State private var messageHistoryHasMore = true
  @State private var initialMessageScrollCompleted = false
  @State private var messageWindowContactId = ""
  @State private var pendingVoiceRiskConfirmation: GalaxySSIConversationVoiceRiskConfirmation?
  @State private var visibilityToken = UUID()
  var contactId: String
  var onNavigateToMainTab: ((GalaxySSIMainTab) -> Void)? = nil

  private var contact: GalaxySSIContact {
    store.contact(id: contactId) ?? GalaxySSIContact.hermes()
  }

  private var deviceInputPolicy: AgentDeviceInputTargetPolicy {
    AgentDeviceProfileDetector.detect().inputTargetPolicy
  }

  private var isSystemNoticeContact: Bool {
    contact.id == "system"
  }

  private var displayedMessages: [ChatMessage] {
    let all = store.messages(for: contact.id)
    guard isAgentSessionContact,
          let active = store.agentSession(id: store.activeAgentConversationId),
          active.status == .active,
          active.mergedIntoConversationId.isBlank else {
      return all
    }
    return all.filter { $0.conversationId == active.id }
  }

  private var renderedMessages: [ChatMessage] {
    Array(displayedMessages.suffix(min(visibleMessageCount, displayedMessages.count)))
  }

  private var waitingMessageIDs: Set<UUID> {
    AgentReplyWaitingIndicatorPolicy.waitingMessageIDs(
      messages: displayedMessages,
      pendingTurnIds: coordinator.pendingAgentReplyTurnIds
    )
  }

  private var contactStatusText: String {
    if isSystemNoticeContact {
      return t("chat_system_notice", "System Notifications")
    }
    if contact.isDesktopDeviceContact && !coordinator.transportConnected {
      return t("galaxyssi.peer.transport_offline", "GalaxySSI Link offline")
    }
    let setupDetail = contact.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines)
    switch contact.deliveryMode {
    case .cloudAPI:
      return contact.selectedCloudModel?.modelId ?? contact.cloudProvider.ifBlank(t("galaxyssi.status.cloud_model", "Cloud model"))
    case .link, .pcConnector:
      return contact.isCommunicable
        ? t("chat_link_encrypted", "GalaxySSI Link encrypted")
        : setupDetail.ifBlank(t("galaxyssi.status.waiting_pairing", "Waiting for Desktop pairing"))
    case .local:
      return setupDetail.ifBlank(t("galaxyssi.status.local", "Local"))
    }
  }

  private var peerSendPending: Bool {
    coordinator.pendingPeerSendContactIds.contains(contact.id)
  }

  private var contactStatusIsOnline: Bool {
    contact.isCommunicable &&
      (!contact.isDesktopDeviceContact || coordinator.transportConnected)
  }

  private var cloudModelHeaderText: String {
    if let selected = contact.selectedCloudModel {
      return selected.displayName.ifBlank(selected.modelId)
    }
    return contact.cloudProvider.ifBlank(t("galaxyssi.status.cloud_model", "Cloud model"))
  }

  var body: some View {
    let firstRenderedMessageID = renderedMessages.first?.id
    VStack(spacing: 0) {
      conversationHeader
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(Array(renderedMessages.enumerated()), id: \.element.id) { index, message in
              conversationMessageRow(
                index: index,
                message: message,
                firstRenderedMessageID: firstRenderedMessageID,
                proxy: proxy
              )
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 14)
          .padding(.bottom, 10)
        }
        .background(Color.galaxySSIPageBackground)
        .onAppear {
          resetMessageWindowIfNeeded()
          guard !initialMessageScrollCompleted else { return }
          let initialPosition = GalaxySSIChatMessageViewportPolicy.initialPosition(
            systemNotifications: isSystemNoticeContact
          )
          let initialMessage = initialPosition == .first
            ? renderedMessages.first
            : renderedMessages.last
          guard let initialMessage else { return }
          DispatchQueue.main.async {
            proxy.scrollTo(
              initialMessage.id,
              anchor: initialPosition == .first ? .top : .bottom
            )
            initialMessageScrollCompleted = true
          }
        }
        .onChange(of: displayedMessages.count) { _ in
          if !initialMessageScrollCompleted,
             let first = renderedMessages.first,
             isSystemNoticeContact {
            proxy.scrollTo(first.id, anchor: .top)
            initialMessageScrollCompleted = true
          } else if GalaxySSIChatMessageViewportPolicy.followsLatest(
            systemNotifications: isSystemNoticeContact
          ), let last = renderedMessages.last {
            withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
          store.markContactRead(contact.id)
        }
        .onChange(of: waitingMessageIDs.count) { _ in
          guard GalaxySSIChatMessageViewportPolicy.followsLatest(
            systemNotifications: isSystemNoticeContact
          ) else { return }
          guard let last = displayedMessages.last else { return }
          let animation: Animation? = deviceInputPolicy.reduceMotion ? nil : .default
          withAnimation(animation) {
            if waitingMessageIDs.contains(last.id) {
              proxy.scrollTo(
                AgentReplyWaitingIndicatorPolicy.viewID(for: last),
                anchor: .bottom
              )
            } else {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }
      }
      if !isSystemNoticeContact {
        Divider()
          .background(Color.galaxySSISeparator)
        if peerSendPending {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text(t("galaxyssi.peer.send_pending", "Sending to device..."))
              .font(.caption)
              .foregroundColor(.galaxySSITextSecondary)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 14)
          .padding(.top, 8)
        }
        GalaxySSIConversationComposer(
          draft: $draft,
          attachments: $attachments,
          attachmentError: $attachmentError,
          attachmentMenuPresented: $attachmentMenuPresented,
          textModeActive: $composerTextModeActive,
          deviceInputPolicy: deviceInputPolicy,
          voiceSettings: store.voiceSettings,
          dedicatedPeerVoiceCapture: GalaxySSIPeerVoiceMessageAudio.shouldUseDedicatedCapture(
            purpose: "chat_message",
            isPersonContact: isPhonePersonContact
          ),
          onNewSession: createAgentConversationFromChat,
          onOpenSessions: openAgentSessionsFromChat,
          onScan: openContactScannerFromChat,
          onTakePhoto: openCameraAttachmentPicker,
          onAddFile: { fileImporterPresented = true },
          onSend: sendCurrentMessage,
          onVoiceTranscript: sendVoiceTranscript,
          t: t
        )
        .disabled(peerSendPending)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .background(navigationShortcuts)
    .navigationBarHidden(true)
    .onAppear {
      GalaxySSIVisibleConversationTracker.shared.markVisible(
        contactId: contact.id,
        token: visibilityToken
      )
      resetMessageWindowIfNeeded()
      store.markContactRead(contact.id)
      NotificationService.cancelIncomingMessage(contactId: contact.id)
    }
    .onChange(of: contactId) { _ in
      GalaxySSIVisibleConversationTracker.shared.markVisible(
        contactId: contact.id,
        token: visibilityToken
      )
      resetMessageWindowIfNeeded()
      store.markContactRead(contact.id)
      NotificationService.cancelIncomingMessage(contactId: contact.id)
    }
    .onDisappear {
      GalaxySSIVisibleConversationTracker.shared.markHidden(token: visibilityToken)
      attachmentMenuPresented = false
    }
    .onChange(of: coordinator.pairingRevocationRevision) { _ in
      dismissIfRevoked()
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
      CameraAttachmentPickerView(
        onAttachment: { attachment in
          defer {
            cameraTargetContactId = ""
            cameraPickerPresented = false
          }
          guard cameraTargetContactId == contact.id else {
            var discarded = attachment
            discarded.wipeSensitive()
            return
          }
          appendAttachment(attachment)
        },
        onCancel: {
          cameraTargetContactId = ""
          cameraPickerPresented = false
        }
      )
    }
    .sheet(item: $runtimeArtifactPreview) { preview in
      GalaxySSIRuntimeArtifactPreviewView(preview: preview)
    }
    .fileExporter(
      isPresented: $runtimeArtifactExportPresented,
      document: runtimeArtifactDocument,
      contentType: .data,
      defaultFilename: runtimeArtifactExportFilename
    ) { result in
      if case .failure(let error) = result {
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
      Button(t("galaxyssi.common.done", "Done"), role: .cancel) {
        runtimeArtifactError = ""
      }
    } message: {
      Text(runtimeArtifactError)
    }
    .alert(
      t("peer_voice_transcription_failed", "Could not transcribe this voice message"),
      isPresented: Binding(
        get: { !peerVoiceTranscriptionError.isEmpty },
        set: { if !$0 { peerVoiceTranscriptionError = "" } }
      )
    ) {
      Button(t("galaxyssi.common.done", "Done"), role: .cancel) {
        peerVoiceTranscriptionError = ""
      }
    } message: {
      Text(peerVoiceTranscriptionError)
    }
    .alert(item: $pendingVoiceRiskConfirmation) { confirmation in
      Alert(
        title: Text(t("galaxyssi.voice.risk_confirmation_title", "Confirm voice command")),
        message: Text(VoiceRiskConfirmationMessageFormatter.message(
          text: confirmation.transcript,
          riskLabel: voiceRiskLabel(confirmation.risk),
          correctionReview: confirmation.correctionReview,
          localize: t
        )),
        primaryButton: .default(Text(t("galaxyssi.voice.risk_confirmation_execute", "Execute"))) {
          executeRiskConfirmedVoiceTranscript(confirmation)
        },
        secondaryButton: .cancel(Text(t("galaxyssi.voice.risk_confirmation_edit", "Edit"))) {
          editRiskConfirmedVoiceTranscript(confirmation)
        }
      )
    }
    .sheet(isPresented: $cloudModelSwitchPresented) {
      NavigationView {
        GalaxySSICloudModelSwitchView(contactId: contact.id, dismissAfterSelection: true)
          .environmentObject(store)
      }
      .navigationViewStyle(StackNavigationViewStyle())
    }
  }

  @ViewBuilder
  private func conversationMessageRow(
    index: Int,
    message: ChatMessage,
    firstRenderedMessageID: UUID?,
    proxy: ScrollViewProxy
  ) -> some View {
    if GalaxySSIConversationDateDivider.shouldShow(
      for: message.createdAt,
      previous: index > 0 ? renderedMessages[index - 1].createdAt : nil
    ) {
      GalaxySSIConversationDateDivider(
        date: message.createdAt,
        language: interfaceLanguage
      )
    }
    MessageBubble(
      message: message,
      myAvatarData: store.profile.avatarData,
      myIdentityFingerprint: store.profile.identityFingerprint,
      remoteContact: contact,
      onAction: handleRichAction,
      isVoiceTranscriptionPending: transcribingVoiceMessageIDs.contains(message.id),
      isRetrying: retryingMessageIDs.contains(message.id),
      onRetry: { retryMessage(message) }
    )
      .id(message.id)
      .contextMenu {
        if !message.isSystem {
          Button {
            UIPasteboard.general.string = GalaxySSIMessageActionPolicy.copyText(for: message)
          } label: {
            Label(t("galaxyssi.common.copy", "Copy"), systemImage: "doc.on.doc")
          }
          Button(role: .destructive) {
            store.deleteMessage(message.id, contactId: contact.id)
          } label: {
            Label(t("galaxyssi.message.delete", "Delete Message"), systemImage: "trash")
          }
        }
      }
    if waitingMessageIDs.contains(message.id) {
      AgentReplyWaitingIndicatorView()
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(AgentReplyWaitingIndicatorPolicy.viewID(for: message))
    }
    if message.id == firstRenderedMessageID {
      Color.clear
        .frame(height: 1)
        .onAppear {
          loadOlderMessages(anchorID: message.id, proxy: proxy)
        }
    }
  }

  private func resetMessageWindowIfNeeded() {
    guard messageWindowContactId != contact.id else { return }
    messageWindowContactId = contact.id
    visibleMessageCount = 100
    loadingOlderMessages = false
    initialMessageScrollCompleted = false
    let page = store.loadMessagePage(
      contactId: contact.id,
      conversationId: visibleAgentConversationId,
      pageSize: 100
    )
    messageHistoryHasMore = page.hasMore
  }

  private func dismissIfRevoked() {
    guard coordinator.lastRevokedContactIds.contains(contactId) else { return }
    dismiss()
  }

  private func loadOlderMessages(anchorID: UUID, proxy: ScrollViewProxy) {
    guard initialMessageScrollCompleted,
          !loadingOlderMessages else { return }
    loadingOlderMessages = true
    if visibleMessageCount < displayedMessages.count {
      visibleMessageCount = min(visibleMessageCount + 100, displayedMessages.count)
    } else if messageHistoryHasMore {
      let page = store.loadMessagePage(
        contactId: contact.id,
        conversationId: visibleAgentConversationId,
        before: renderedMessages.first,
        pageSize: 100
      )
      visibleMessageCount = min(visibleMessageCount + page.messages.count, displayedMessages.count)
      messageHistoryHasMore = page.hasMore
    }
    DispatchQueue.main.async {
      proxy.scrollTo(anchorID, anchor: .top)
      loadingOlderMessages = false
    }
  }

  private var visibleAgentConversationId: String? {
    guard isAgentSessionContact,
          let active = store.agentSession(id: store.activeAgentConversationId),
          active.status == .active,
          active.mergedIntoConversationId.isBlank else { return nil }
    return active.id
  }

  @ViewBuilder
  private var conversationHeader: some View {
    if isSystemNoticeContact {
      ZStack {
        Text(contactTitle)
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
        HStack {
          conversationBackButton
          Spacer()
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 56)
      .background(Color.galaxySSIBarBackground)
    } else {
      HStack(spacing: 8) {
        conversationBackButton
        contactIdentityHeader
        Spacer(minLength: 8)
        if contact.deliveryMode == .cloudAPI {
          Button {
            cloudModelSwitchPresented = true
          } label: {
            HStack(spacing: 5) {
              Image(systemName: "cloud.fill")
                .font(.system(size: 13, weight: .semibold))
              Text(cloudModelHeaderText)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            .foregroundColor(.galaxySSIInsightText)
            .padding(.horizontal, 8)
            .frame(maxWidth: 126, minHeight: 32)
            .background(Color.galaxySSIInsightBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 56)
      .background(Color.galaxySSIBarBackground)
    }
  }

  private var conversationBackButton: some View {
    Button {
      if GalaxySSIPeerComposerActionPolicy.consumesBackAction(
        actionTrayPresented: attachmentMenuPresented
      ) {
        attachmentMenuPresented = false
      } else if composerTextModeActive {
        composerTextModeActive = false
      } else {
        dismiss()
      }
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 22, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(t("galaxyssi.common.back", "Back")))
  }

  private var contactIdentityHeader: some View {
    HStack(spacing: 8) {
      AvatarView(contact: contact, size: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(contactTitle)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
        HStack(spacing: 5) {
          Circle()
            .fill(contactStatusIsOnline ? Color.galaxySSIAccent : Color.galaxySSITextSecondary)
            .frame(width: 7, height: 7)
          Text(contactStatusText)
            .font(.system(size: 11))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(1)
        }
      }
    }
  }

  private var contactTitle: String {
    switch contact.id {
    case "system":
      return t("chat_system_notice", "System Notifications")
    case "me":
      return store.profile.name.ifBlank(GalaxySSIDeviceIdentityName.current(profile: store.profile))
    default:
      return contact.displayName
    }
  }

  @ViewBuilder
  private var navigationShortcuts: some View {
    NavigationLink(
      destination: GalaxySSIConversationHubView(),
      isActive: $agentSessionsShortcutActive
    ) {
      EmptyView()
    }
    .hidden()

    NavigationLink(
      destination: AddContactView(
        autoOpenScanner: true,
        onAgentAdded: openScannedAgentConversationFromChat
      ),
      isActive: $scanShortcutActive
    ) {
      EmptyView()
    }
    .hidden()
  }

  private var isAgentSessionContact: Bool {
    contact.id == "hermes" || contact.type == "agent" || contact.deliveryMode == .cloudAPI
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
    guard action.verb == "preview_runtime_artifact" || action.verb == "save_runtime_artifact" else {
      return
    }
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
        runtimeArtifactPreview = GalaxySSIRuntimeArtifactPreview(
          title: payload.displayName,
          content: try AgentRuntimeArtifactUi.preview(file: file)
        )
      } else {
        runtimeArtifactDocument = GalaxySSIRuntimeArtifactDocument(data: try Data(contentsOf: file))
        runtimeArtifactExportFilename = payload.displayName
        runtimeArtifactExportPresented = true
      }
    } catch {
      runtimeArtifactError = error.localizedDescription
    }
  }

  private func sendCurrentMessage() {
    let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let outgoingAttachments = attachments
    let text = cleanDraft.ifBlank(attachmentLabel(for: outgoingAttachments))
    let agentGoal = cleanDraft.isEmpty && !outgoingAttachments.isEmpty
      ? t("agent_attachment_default_goal", "Inspect and understand the attached content first. Infer the user's most likely goal from its content, type, conversation context, and common use cases, then directly complete the most helpful relevant action. If several interpretations are reasonable, act on the most probable reversible one and briefly state the assumption. Ask one minimal question only when the content cannot be read or no reasonable intent can be inferred.")
      : ""
    draft = ""
    attachments.removeAll()
    attachmentError = ""
    Task {
      var sensitiveAttachments = outgoingAttachments
      defer { sensitiveAttachments.wipeSensitive() }
      await coordinator.send(
        text,
        to: contact,
        attachments: sensitiveAttachments,
        agentGoalOverride: agentGoal
      )
    }
  }

  private func retryMessage(_ message: ChatMessage) {
    guard message.isMine,
          message.deliveryStatus == .failed,
          message.richOutputJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          retryingMessageIDs.insert(message.id).inserted else {
      return
    }
    Task { @MainActor in
      _ = await coordinator.send(message.content, to: contact)
      retryingMessageIDs.remove(message.id)
    }
  }

  private func transcribePeerVoiceMessage(_ message: ChatMessage) {
    guard transcribingVoiceMessageIDs.insert(message.id).inserted else { return }
    let settings = store.voiceSettings
    Task {
      do {
        let transcript = try await GalaxySSIPeerVoiceTranscriber.shared.transcribe(
          message: message,
          settings: settings
        )
        guard store.updateVoiceTranscript(
          transcript,
          messageId: message.id,
          contactId: contact.id
        ) else {
          transcribingVoiceMessageIDs.remove(message.id)
          return
        }
        transcribingVoiceMessageIDs.remove(message.id)
      } catch {
        transcribingVoiceMessageIDs.remove(message.id)
        peerVoiceTranscriptionError = t(
          "peer_voice_transcription_failed",
          error.localizedDescription.ifBlank("Could not transcribe this voice message")
        )
      }
    }
  }

  private func sendVoiceTranscript(_ submission: GalaxySSIVoiceTranscriptSubmission) {
    let transcript = submission.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if isPhonePersonContact,
       let audioData = submission.audioData,
       !audioData.isEmpty {
      let attachment = phoneVoiceAttachment(
        submission: submission,
        data: audioData
      )
      Task {
        _ = await coordinator.send(
          "",
          to: contact,
          attachments: [attachment],
          peerMessageKind: "voice",
          peerDurationMillis: submission.audioDurationMillis
        )
      }
      return
    }
    guard !transcript.isEmpty else { return }
    draft = transcript
    let risk = DefaultVoiceCommandRiskClassifier.classify(transcript)
    let sessionId = VoiceExecutionLedgerBridge.register(
      sessionId: submission.sessionId,
      text: transcript,
      correctionReview: submission.correctionReview,
      risk: risk
    )
    if let review = submission.correctionReview {
      _ = VoiceCorrectionJournal.shared.persist(
        review: review,
        conversationId: isAgentSessionContact
          ? store.activeAgentConversationId.ifBlank(contact.id)
          : contact.id,
        turnId: review.sessionId,
        risk: risk
      )
    }
    if risk >= .high {
      pendingVoiceRiskConfirmation = GalaxySSIConversationVoiceRiskConfirmation(
        transcript: transcript,
        risk: risk,
        correctionReview: submission.correctionReview,
        sessionId: sessionId
      )
      return
    }
    guard VoiceExecutionLedgerBridge.claimPrimaryDispatch(sessionId: sessionId) else { return }
    sendCurrentMessage()
  }

  private var isPhonePersonContact: Bool {
    contact.type.caseInsensitiveCompare("person") == .orderedSame &&
      !contact.isDesktopDeviceContact &&
      contact.opaquePhoneRoutes?.isOpaqueV2Valid == true
  }

  private func phoneVoiceAttachment(
    submission: GalaxySSIVoiceTranscriptSubmission,
    data: Data
  ) -> GalaxySSIDraftAttachment {
    let identity = submission.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(UUID().uuidString.lowercased())
    let stem = "voice-\(identity.prefix(80))"
    let fileExtension = submission.audioFileExtension.ifBlank("wav")
    let sourceURL = submission.audioSourceURL
    return GalaxySSIDraftAttachment(
      id: identity,
      displayName: "\(stem).\(fileExtension)",
      mimeType: submission.audioMimeType,
      data: data,
      sourceDescription: sourceURL?.absoluteString ?? ""
    )
  }

  private func executeRiskConfirmedVoiceTranscript(
    _ confirmation: GalaxySSIConversationVoiceRiskConfirmation
  ) {
    guard VoiceExecutionLedgerBridge.claimPrimaryDispatch(sessionId: confirmation.sessionId) else {
      return
    }
    draft = confirmation.transcript
    sendCurrentMessage()
  }

  private func editRiskConfirmedVoiceTranscript(
    _ confirmation: GalaxySSIConversationVoiceRiskConfirmation
  ) {
    VoiceExecutionLedgerBridge.markUserEdited(sessionId: confirmation.sessionId)
    if let sessionId = confirmation.correctionReview?.sessionId {
      _ = VoiceCorrectionJournal.shared.markUserEdited(sessionId: sessionId)
    }
    draft = confirmation.transcript
    composerTextModeActive = true
  }

  private func voiceRiskLabel(_ risk: VoiceCommandRisk) -> String {
    switch risk {
    case .critical:
      return t("galaxyssi.voice.risk_critical", "critical")
    case .high:
      return t("galaxyssi.voice.risk_high", "high")
    case .medium:
      return t("galaxyssi.voice.risk_medium", "medium")
    case .low:
      return t("galaxyssi.voice.risk_low", "low")
    case .conversation:
      return t("galaxyssi.voice.risk_conversation", "conversation")
    }
  }

  private func createAgentConversationFromChat() {
    _ = store.createAgentSession(title: t("galaxyssi.agent_session.new", "New session"))
    draft = ""
    attachments.wipeSensitive()
    attachmentError = ""
    if let onNavigateToMainTab {
      onNavigateToMainTab(.agent)
    } else {
      agentSessionsShortcutActive = true
    }
  }

  private func openAgentSessionsFromChat() {
    agentSessionsShortcutActive = true
  }

  private func openContactScannerFromChat() {
    scanShortcutActive = true
  }

  private func openScannedAgentConversationFromChat(_ targetIDs: [String]) {
    scanShortcutActive = false
    Task { @MainActor in
      let delays: [UInt64] = [0, 300_000_000, 900_000_000, 1_800_000_000]
      var previousDelay: UInt64 = 0
      for delay in delays {
        if delay > previousDelay {
          try? await Task.sleep(nanoseconds: delay - previousDelay)
        }
        previousDelay = delay
        guard ScannedAgentConversationRouter.open(
          targetIDs: targetIDs,
          store: store,
          title: t("galaxyssi.agent_session.new", "New session")
        ) != nil else { continue }
        draft = ""
        attachments.wipeSensitive()
        attachmentError = ""
        if let onNavigateToMainTab {
          onNavigateToMainTab(.agent)
        } else {
          agentSessionsShortcutActive = true
        }
        return
      }
    }
  }

  private func openCameraAttachmentPicker() {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      attachmentError = t("agent_attachment_camera_unavailable", "Camera is unavailable")
      return
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .denied, .restricted:
      attachmentError = t("galaxyssi.scanner.camera_access_required", "Camera access is required to scan GalaxySSI QR codes.")
    case .authorized, .notDetermined:
      cameraTargetContactId = contact.id
      cameraPickerPresented = true
    @unknown default:
      cameraTargetContactId = contact.id
      cameraPickerPresented = true
    }
  }

  private func attachmentLabel(for values: [GalaxySSIDraftAttachment]) -> String {
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
      let attachment = try GalaxySSIAttachmentPayloadBuilder.makeAttachment(from: url)
      appendAttachment(attachment)
    } catch {
      attachmentError = error.localizedDescription
    }
  }

  private func appendAttachment(_ attachment: GalaxySSIDraftAttachment) {
    guard GalaxySSIAttachmentPayloadBuilder.accepted(attachment, existing: attachments) else {
      attachmentError = t("agent_attachment_rejected", "Some attachments were skipped. You can add up to 10 files, 64 MB each.")
      return
    }
    attachments.append(attachment)
    attachmentError = ""
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct MessageDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  var message: ChatMessage
  var contact: GalaxySSIContact

  var body: some View {
    NavigationView {
      Form {
        Section(t("galaxyssi.message.section", "Message")) {
          Text(messageSenderName)
          Text(message.content)
            .textSelection(.enabled)
          detailRow(t("galaxyssi.message.sent_time", "Sent Time"), message.createdAt.formatted(date: .abbreviated, time: .standard))
          detailRow(
            t("galaxyssi.common.status", "Status"),
            GalaxySSIChatDeliveryStatus.title(message.deliveryStatus, language: interfaceLanguage)
          )
        }
        Section(t("galaxyssi.security.status", "Security Status")) {
          Text(securityStatusText)
            .foregroundColor(.secondary)
        }
        Section(t("galaxyssi.delivery.trace", "Delivery Trace")) {
          if message.deliveryTrace.isEmpty {
            Text(t("galaxyssi.delivery.no_trace", "No trace yet"))
              .foregroundColor(.secondary)
          } else {
            ForEach(message.deliveryTrace) { event in
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(event.displayTitle)
                  Spacer()
                  Text(event.createdAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                if !event.detail.isEmpty {
                  Text(event.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                }
              }
            }
          }
        }
        if hasIdentifiers {
          Section(t("galaxyssi.identifiers", "Identifiers")) {
            if !message.conversationId.isEmpty {
              detailRow(t("galaxyssi.identifier.conversation", "Conversation"), message.conversationId)
            }
            if !message.turnId.isEmpty {
              detailRow(t("galaxyssi.identifier.turn", "Turn"), message.turnId)
            }
            if !message.remoteMessageId.isEmpty {
              detailRow(t("galaxyssi.identifier.remote_message", "Remote Message"), message.remoteMessageId)
            }
          }
        }
      }
      .navigationTitle(t("galaxyssi.message.actions", "Message Actions"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.done", "Done")) {
            dismiss()
          }
        }
      }
    }
  }

  private var securityStatusText: String {
    switch contact.deliveryMode {
    case .link, .pcConnector:
      return t("galaxyssi.security.link", "Protected by the GalaxySSI Link end-to-end session")
    case .cloudAPI:
      return t("galaxyssi.security.cloud", "Protected locally; cloud model requests use the configured provider endpoint")
    case .local:
      return t("galaxyssi.security.local", "Stored locally on this device")
    }
  }

  private var messageSenderName: String {
    if message.isMine {
      return t("galaxyssi.message.sent_by_me", "Sent by me")
    }
    switch contact.id {
    case "system":
      return t("chat_system_notice", "System Notifications")
    case "me":
      return store.profile.name.ifBlank(GalaxySSIDeviceIdentityName.current(profile: store.profile))
    default:
      return contact.displayName
    }
  }

  private var hasIdentifiers: Bool {
    !message.conversationId.isEmpty || !message.turnId.isEmpty || !message.remoteMessageId.isEmpty
  }

  private func detailRow(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)
      Text(value)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct MessageBubbleContainerWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

struct MessageBubble: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var messageContainerWidth: CGFloat = 0

  var message: ChatMessage
  var myAvatarData: Data? = nil
  var myIdentityFingerprint: String = ""
  var remoteContact: GalaxySSIContact? = nil
  var onAction: (AgentRichAction) -> Void = { _ in }
  var onActionWithMessage: ((ChatMessage, AgentRichAction) -> Void)?
  var onFormSubmit: (AgentRichBlock, [String: String]) -> Void = { _, _ in }
  var onParagraphDoubleTap: ((String) -> Void)? = nil
  var isVoiceTranscriptionPending = false
  var isRetrying = false
  var onRetry: () -> Void = {}

  var body: some View {
    if message.isSystem {
      Text(message.content)
        .font(.caption)
        .foregroundColor(.galaxySSITextSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    } else {
      HStack(alignment: .bottom, spacing: 8) {
        if !message.isMine, let remoteContact {
          AvatarView(contact: remoteContact, size: 36)
            .accessibilityHidden(true)
        }
        if message.isMine { Spacer(minLength: 48) }
        VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
          GalaxySSIRichContentView(
            content: message.content,
            richOutputJson: message.richOutputJson,
            isOutgoing: message.isMine,
            expansionStorageKey: "message:\(message.id.uuidString)",
            onAction: { action in
              if let onActionWithMessage = onActionWithMessage {
                onActionWithMessage(message, action)
              } else {
                onAction(action)
              }
            },
            onFormSubmit: onFormSubmit
          )
            .environment(\.agentReplyParagraphSpeechAction, onParagraphDoubleTap)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundColor(.galaxySSITextPrimary)
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
            .background(messageBubbleColor)
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(message.isMine ? Color.clear : Color.galaxySSISeparator, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          if isVoiceTranscriptionPending || !message.voiceTranscript.isBlank {
            Text(
              isVoiceTranscriptionPending
                ? t("peer_voice_transcribing", "Transcribing...")
                : message.voiceTranscript
            )
              .font(.system(size: 14))
              .foregroundColor(.galaxySSITextSecondary)
              .multilineTextAlignment(message.isMine ? .trailing : .leading)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: bubbleMaxWidth, alignment: message.isMine ? .trailing : .leading)
              .accessibilityIdentifier("peer_voice_transcript_\(message.id.uuidString)")
          }
          HStack(spacing: 4) {
            Text(message.createdAt, style: .time)
            if message.isMine {
              Text(
                GalaxySSIPeerDeliveryPresentation.title(
                  for: message.deliveryStatus,
                  isPeerMessage: remoteContact?.isDesktopDeviceContact == true,
                  language: interfaceLanguage
                )
              )
              if canRetryTextMessage {
                Button(action: onRetry) {
                  if isRetrying {
                    ProgressView()
                      .controlSize(.mini)
                  } else {
                    Image(systemName: "arrow.clockwise")
                      .font(.caption.weight(.semibold))
                  }
                }
                .buttonStyle(.plain)
                .disabled(isRetrying)
                .frame(width: 28, height: 28)
                .accessibilityLabel(Text(t("galaxyssi.common.retry", "Retry")))
              }
            }
          }
          .font(.caption2)
          .foregroundColor(.galaxySSITextSecondary)
        }
        if message.isMine {
          GalaxySSIProfileAvatar(
            data: myAvatarData,
            size: 36,
            fingerprint: myIdentityFingerprint
          )
            .accessibilityHidden(true)
        }
        if !message.isMine { Spacer(minLength: 48) }
      }
      .frame(maxWidth: .infinity)
      .background(
        GeometryReader { proxy in
          Color.clear.preference(key: MessageBubbleContainerWidthKey.self, value: proxy.size.width)
        }
      )
      .onPreferenceChange(MessageBubbleContainerWidthKey.self) { width in
        guard width > 0 else { return }
        messageContainerWidth = width
      }
    }
  }

  private var messageBubbleColor: Color {
    return message.isMine ? Color.galaxySSISentBubble : Color.galaxySSIIncomingBubble
  }

  private var canRetryTextMessage: Bool {
    message.isMine &&
      message.deliveryStatus == .failed &&
      message.richOutputJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var bubbleMaxWidth: CGFloat {
    let width = messageContainerWidth > 0 ? messageContainerWidth : UIScreen.main.bounds.width
    return width * 0.75
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIRuntimeArtifactPreview: Identifiable {
  let id = UUID()
  let title: String
  let content: String
}

struct GalaxySSIRuntimeArtifactDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  static var writableContentTypes: [UTType] { [.data] }

  var data: Data

  init(data: Data = Data()) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct GalaxySSIRuntimeArtifactPreviewView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  let preview: GalaxySSIRuntimeArtifactPreview
  @State private var copied = false

  var body: some View {
    NavigationView {
      ScrollView {
        Text(preview.content)
          .font(.system(size: 13, design: .monospaced))
          .foregroundColor(.galaxySSITextPrimary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
      }
      .background(Color.galaxySSIPageBackground)
      .navigationTitle(preview.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(GalaxySSILocalization.string("galaxyssi.common.done", fallback: "Done", language: interfaceLanguage)) {
            dismiss()
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            UIPasteboard.general.string = preview.content
            copied = true
          } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
          }
          .accessibilityLabel(
            GalaxySSILocalization.string(
              copied ? "rich_output_copied" : "rich_output_copy",
              fallback: copied ? "Copied" : "Copy",
              language: interfaceLanguage
            )
          )
        }
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }
}

private struct VoiceSettingsRiskConfirmation: Identifiable {
  let id = UUID()
  var plan: VoiceTranscriptRoutePlan
  var risk: VoiceCommandRisk
  var correctionReview: VoiceTranscriptCorrectionReview?
}

struct VoiceSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @ObservedObject private var voiceAgentRunRecovery = VoiceAgentRunRecoveryCoordinator.shared
  @StateObject private var speech = SpeechCaptureService()
  @StateObject private var replySpeech = VoiceProgressiveReplySpeechService()
  @State private var permissionStatus = ""
  @State private var activeVoiceReplySessionId = ""
  @State private var activeVoiceReplyContactId = ""
  @State private var activeVoiceReplyRouteKind: VoiceRouteKind?
  @State private var activeVoiceReplyPlaybackSessionId = ""
  @State private var progressiveVoiceReplySessionId = ""
  @State private var progressiveVoiceReplyText = ""
  @State private var voiceAgentRunListenerId = ""
  @State private var pendingRiskConfirmation: VoiceSettingsRiskConfirmation?

  var body: some View {
    NavigationView {
      Form {
        Section(t("voice_settings_section_voice", "Voice")) {
          Toggle(t("voice_wake_phrase", "Wake phrase"), isOn: binding(\.wakeListeningEnabled))
          Toggle(t("galaxyssi.voice.speech_recognition", "Speech recognition"), isOn: binding(\.speechRecognitionEnabled))
          Toggle(t("galaxyssi.voice.text_to_speech", "Text to speech"), isOn: binding(\.textToSpeechEnabled))
          Toggle(t("galaxyssi.voice.auto_send_transcripts", "Auto-send transcripts"), isOn: binding(\.autoSendTranscripts))
          Toggle(t("voice_speak_replies", "Speak Replies"), isOn: binding(\.speakReplies))
          TextField(t("voice_locale", "Locale"), text: Binding(
            get: { store.voiceSettings.preferredLocaleIdentifier },
            set: { value in store.updateVoiceSettings { $0.preferredLocaleIdentifier = value } }
          ))
          Picker(t("voice_wake_engine", "Wake Engine"), selection: Binding(
            get: { store.voiceSettings.wakeProvider },
            set: { value in store.updateVoiceSettings { $0.wakeProvider = value } }
          )) {
            ForEach(VoiceWakeProvider.allCases) { provider in
              Text(t(provider.displayTitle, provider.displayTitle)).tag(provider)
            }
          }
          Picker(t("voice_asr_recognition_mode_title", "Recognition mode"), selection: Binding(
            get: { store.voiceSettings.asrRecognitionPreference },
            set: { value in
              if value == .onlineFast {
                VoiceFeatureFlags.setOnlineRealtimeASREnabled(true)
              }
              if value == .remoteNode {
                VoiceFeatureFlags.setRemoteWhisperNodeEnabled(true)
              }
              store.updateVoiceSettings { $0.setASRRecognitionPreference(value) }
            }
          )) {
            ForEach(recognitionPreferences) { preference in
              Text(t(recognitionPreferenceLocalizationKey(preference), recognitionPreferenceTitle(preference)))
                .tag(preference)
            }
          }
          NavigationLink(destination: VoiceWhisperModelSettingsView()) {
            HStack {
              Text(t("voice_asr_model", "ASR Model"))
              Spacer()
              Text(VoiceWhisperModelCatalog.model(store.voiceSettings.asrModelId).displayName)
                .foregroundColor(.secondary)
            }
          }
          Picker(t("voice_model_selection", "Model selection"), selection: Binding(
            get: { store.voiceSettings.asrRuntimeMode },
            set: { value in store.updateVoiceSettings { $0.asrRuntimeMode = value } }
          )) {
            ForEach(VoiceWhisperUserVoiceMode.allCases) { mode in
              Text(t(mode.displayTitle, mode.displayTitle)).tag(mode)
            }
          }
          Picker(t("voice_tts_provider", "TTS Provider"), selection: Binding(
            get: { store.voiceSettings.ttsProvider },
            set: { value in store.updateVoiceSettings { $0.ttsProvider = value } }
          )) {
            ForEach(VoiceTTSProvider.allCases) { provider in
              Text(t(provider.displayTitle, provider.displayTitle)).tag(provider)
            }
          }
          TextField(t("voice_microsoft_voice", "Microsoft Voice"), text: Binding(
            get: { store.voiceSettings.microsoftVoice },
            set: { value in store.updateVoiceSettings { $0.microsoftVoice = value } }
          ))
        }
        Section(t("voice_settings_section_wake", "Wake")) {
          HStack {
            Text(t("voice_wake_words", "Wake Words"))
            Spacer()
            Text(WakeWordPolicy.wakeWord)
              .foregroundColor(.secondary)
          }
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(t("voice_wake_threshold", "Wake Threshold"))
              Spacer()
              Text(store.voiceSettings.wakeThreshold.formatted(.number.precision(.fractionLength(2))))
                .foregroundColor(.secondary)
            }
            Slider(
              value: Binding(
                get: { store.voiceSettings.wakeThreshold },
                set: { value in store.updateVoiceSettings { $0.wakeThreshold = value } }
              ),
              in: 0.01...0.99
            )
          }
          TextField(t("voice_welcome_text", "Welcome Text"), text: Binding(
            get: { store.voiceSettings.welcomeText },
            set: { value in store.updateVoiceSettings { $0.welcomeText = value } }
          ))
        }
        Section(t("voice_settings_section_routing", "Routing")) {
          Picker(t("voice_routing_mode", "Voice Routing"), selection: Binding(
            get: { store.voiceSettings.routingMode },
            set: { value in store.updateVoiceSettings { $0.routingMode = value } }
          )) {
            ForEach(VoiceRoutingMode.allCases) { mode in
              Text(t(mode.displayTitle, mode.displayTitle)).tag(mode)
            }
          }
          Picker(t("voice_default_target", "Default Target"), selection: Binding(
            get: { store.voiceSettings.targetContactId },
            set: { value in store.updateVoiceSettings { $0.targetContactId = value } }
          )) {
            ForEach(store.visibleContacts) { contact in
              Text(contact.displayName).tag(contact.id)
            }
          }
        }
        Section(t("voice_settings_section_agent_runs", "Agent runs")) {
          NavigationLink(destination: GalaxySSIVoiceAgentRunsView()) {
            HStack {
              Image(systemName: "waveform.badge.mic")
                .foregroundColor(.galaxySSIAccent)
              Text(t("galaxyssi.voice_agent_runs.title", "Voice Agent runs"))
              Spacer()
              Text("\(voiceAgentRunRecovery.activeSnapshots.count)")
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("voice_settings_section_recorder", "Recorder")) {
          if speech.isRecording {
            Text(speech.transcript.ifBlank(t("voice_listening", "Listening...")))
            Button(role: .destructive) {
              speech.stop()
            } label: {
              Label(t("voice_stop", "Stop"), systemImage: "stop.circle")
            }
          } else {
            Button {
              Task { await startRecording() }
            } label: {
              Label(t("galaxyssi.voice.recorder", "Hold to Talk"), systemImage: "mic.circle")
            }
          }
          if !permissionStatus.isEmpty {
            Text(permissionStatus)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
      .navigationTitle(t("voice_settings_section_voice", "Voice"))
      .onAppear {
        voiceAgentRunRecovery.start()
        coordinator.onIncomingMessage = handleIncomingVoiceReply
        coordinator.onIncomingMessageDelta = handleIncomingVoiceReplyDelta
        voiceAgentRunListenerId = VoiceAgentRunBridgeRegistry.shared.addListener(
          handleVoiceAgentRunUpdate
        )
      }
      .onDisappear {
        cancelRiskConfirmation(pendingRiskConfirmation, reportStatus: false)
        pendingRiskConfirmation = nil
        coordinator.onIncomingMessage = nil
        coordinator.onIncomingMessageDelta = nil
        if !voiceAgentRunListenerId.isEmpty {
          VoiceAgentRunBridgeRegistry.shared.removeListener(voiceAgentRunListenerId)
          voiceAgentRunListenerId = ""
        }
        replySpeech.stop()
        if !activeVoiceReplySessionId.isEmpty {
          _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
            .completed(sessionId: activeVoiceReplySessionId)
          )
          clearActiveVoiceReplySession(activeVoiceReplySessionId)
        }
      }
    }
    .alert(item: $pendingRiskConfirmation) { confirmation in
      Alert(
        title: Text(t("galaxyssi.voice.risk_confirmation_title", "Confirm voice command")),
        message: Text(VoiceRiskConfirmationMessageFormatter.message(
          text: confirmation.plan.text,
          riskLabel: voiceRiskLabel(confirmation.risk),
          correctionReview: confirmation.correctionReview,
          localize: t
        )),
        primaryButton: .default(Text(t("galaxyssi.voice.risk_confirmation_execute", "Execute"))) {
          sendVoiceRoutePlan(confirmation.plan)
        },
        secondaryButton: .cancel(Text(t("galaxyssi.common.cancel", "Cancel"))) {
          cancelRiskConfirmation(confirmation, reportStatus: true)
        }
      )
    }
  }

  private func binding(_ keyPath: WritableKeyPath<VoiceSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { store.voiceSettings[keyPath: keyPath] },
      set: { value in store.updateVoiceSettings { $0[keyPath: keyPath] = value } }
    )
  }

  private func startRecording() async {
    interruptActiveVoiceReply()
    let granted = await speech.requestAuthorization(settings: store.voiceSettings)
    permissionStatus = granted ? "" : t("Microphone or speech permission is missing.", "Microphone or speech permission is missing.")
    guard granted else { return }
    do {
      speech.onVoiceCommand = handleVoiceCommand
      try speech.start(settings: store.voiceSettings)
    } catch {
      permissionStatus = error.localizedDescription
    }
  }

  private func interruptActiveVoiceReply() {
    let sessionId = activeVoiceReplySessionId
    let hadPlayback = replySpeech.stop()
    guard !sessionId.isEmpty else { return }
    _ = VoiceAgentRunBridgeRegistry.shared.markCancellationRequested(sessionId: sessionId)
    _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
      .cancelled(sessionId: sessionId, reasonCode: "barge_in")
    )
    clearActiveVoiceReplySession(sessionId)
    if hadPlayback {
      permissionStatus = t("voice_reply_interrupted", "Voice reply interrupted.")
    }
  }

  private func handleVoiceCommand(_ command: VoiceInteractionCommand) {
    guard let plan = VoiceTranscriptRoutePolicy.plan(
      command: command,
      settings: store.voiceSettings,
      contacts: store.visibleContacts
    ) else {
      return
    }
    guard plan.shouldSend else {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: plan.sessionId))
      permissionStatus = String(format: t("Transcript ready: %@", "Transcript ready: %@"), plan.text)
      return
    }
    let risk = DefaultVoiceCommandRiskClassifier.classify(plan.text)
    let correctionReview = speech.correctionReview(sessionId: plan.sessionId)
    _ = VoiceExecutionLedgerBridge.register(
      sessionId: plan.sessionId,
      text: plan.text,
      correctionReview: correctionReview,
      risk: risk
    )
    if let correctionReview {
      _ = VoiceCorrectionJournal.shared.persist(
        review: correctionReview,
        conversationId: store.activeAgentConversationId.ifBlank(plan.contact.id),
        turnId: plan.sessionId,
        risk: risk
      )
    }
    if risk >= .high {
      pendingRiskConfirmation = VoiceSettingsRiskConfirmation(
        plan: plan,
        risk: risk,
        correctionReview: correctionReview
      )
      permissionStatus = t(
        "galaxyssi.voice.risk_confirmation_required",
        "Voice command requires confirmation"
      )
      return
    }
    sendVoiceRoutePlan(plan)
  }

  private func sendVoiceRoutePlan(_ plan: VoiceTranscriptRoutePlan) {
    guard VoiceExecutionLedgerBridge.claimPrimaryDispatch(sessionId: plan.sessionId) else {
      permissionStatus = t("galaxyssi.voice.duplicate_ignored", "Duplicate voice request ignored")
      return
    }
    VoiceExecutionLedgerBridge.recordRoute(sessionId: plan.sessionId, decision: plan.routeDecision)
    _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
      .routeSelected(sessionId: plan.sessionId, decision: plan.routeDecision)
    )
    let executionTarget = AgentExecutionTargetStatusPolicy.resolveLabel(
      connectorId: plan.routeDecision.targetId,
      contactId: plan.contact.id,
      runtimeTarget: plan.contact.displayName,
      activeLocalModelName: LocalModelRuntimeSettings.activeProfiles().first?.displayName ?? "",
      contacts: store.contacts
    )
    if !executionTarget.isBlank {
      store.setAgentSessionSelectedModelOrAgent(
        id: store.activeAgentConversationId,
        label: executionTarget
      )
    }
    activeVoiceReplySessionId = plan.sessionId
    activeVoiceReplyContactId = plan.contact.id
    activeVoiceReplyRouteKind = plan.routeDecision.kind
    permissionStatus = String(format: t("Sending voice transcript to %@", "Sending voice transcript to %@"), plan.contact.displayName)
    if plan.routeDecision.kind == .remoteAgent {
      _ = VoiceAgentRunBridgeRegistry.shared.createRun(
        VoiceAgentRunRequest(
          sessionId: plan.sessionId,
          conversationId: store.activeAgentConversationId,
          turnId: plan.sessionId,
          taskId: plan.sessionId,
          sourceMessageId: plan.sessionId,
          contactId: plan.contact.id,
          agentId: plan.contact.galaxySSIId,
          agentName: plan.contact.displayName,
          goal: plan.text,
          idempotencyKey: "voice:\(plan.sessionId)",
          traceId: plan.sessionId,
          createdAtMillis: Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        )
      )
    }
    Task {
      await coordinator.send(
        plan.text,
        to: plan.contact,
        voiceSessionId: plan.routeDecision.kind == .remoteAgent ? plan.sessionId : ""
      )
      await MainActor.run {
        finishVoiceSendIfNoReplyPlaybackStarted(plan)
      }
    }
  }

  private func cancelRiskConfirmation(
    _ confirmation: VoiceSettingsRiskConfirmation?,
    reportStatus: Bool
  ) {
    guard let confirmation else { return }
    let voiceCoordinator = VoiceInteractionCoordinatorRegistry.coordinator
    let current = voiceCoordinator.snapshot()
    if current.sessionId == confirmation.plan.sessionId,
       !current.phase.isTerminal {
      _ = voiceCoordinator.dispatch(
        .cancelled(
          sessionId: confirmation.plan.sessionId,
          reasonCode: "risk_confirmation_cancelled"
        )
      )
    }
    if reportStatus {
      permissionStatus = t(
        "galaxyssi.voice.risk_confirmation_cancelled",
        "Voice command cancelled"
      )
    }
  }

  private func voiceRiskLabel(_ risk: VoiceCommandRisk) -> String {
    switch risk {
    case .critical:
      return t("galaxyssi.voice.risk_critical", "critical")
    case .high:
      return t("galaxyssi.voice.risk_high", "high")
    case .medium:
      return t("galaxyssi.voice.risk_medium", "medium")
    case .low:
      return t("galaxyssi.voice.risk_low", "low")
    case .conversation:
      return t("galaxyssi.voice.risk_conversation", "conversation")
    }
  }

  private func handleIncomingVoiceReply(_ message: ChatMessage) {
    guard let request = VoiceReplyPlaybackPolicy.request(
      message: message,
      settings: store.voiceSettings,
      languagePolicy: store.languagePolicy,
      activeSessionId: activeVoiceReplySessionId,
      activeTargetContactId: activeVoiceReplyContactId
    ) else {
      return
    }
    if activeVoiceReplyRouteKind == .cloudModel,
       progressiveVoiceReplySessionId == request.sessionId {
      appendProgressiveVoiceReply(request: request, content: request.text, isFinal: true)
      return
    }
    switch activeVoiceReplyRouteKind {
    case .remoteAgent:
      _ = VoiceAgentRunBridgeRegistry.shared.markFinalResult(
        sessionId: request.sessionId,
        content: request.text
      )
      let runId = VoiceAgentRunBridgeRegistry.shared.find(sessionId: request.sessionId)?.runId
        ?? message.id.uuidString
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentAccepted(sessionId: request.sessionId, runId: runId)
      )
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentProgress(sessionId: request.sessionId, runId: runId)
      )
    case .cloudModel:
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .modelDelta(sessionId: request.sessionId, text: request.text)
      )
    case .localAction, .none:
      break
    }
    activeVoiceReplyPlaybackSessionId = request.sessionId
    replySpeech.speak(request) { started in
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .playbackStarted(sessionId: started.sessionId, utteranceId: started.utteranceId)
      )
      permissionStatus = t("Speaking reply", "Speaking reply")
    } onDone: { done, success, _ in
      completeVoiceReplyPlayback(done, success: success)
    }
  }

  private func handleVoiceAgentRunUpdate(_ update: VoiceAgentRunUpdate) {
    guard update.snapshot.sessionId == activeVoiceReplySessionId else { return }
    if update.firstAcceptance {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentAccepted(sessionId: update.snapshot.sessionId, runId: update.snapshot.runId)
      )
    }
    if update.firstProgress {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentProgress(sessionId: update.snapshot.sessionId, runId: update.snapshot.runId)
      )
    }
    if !update.message.isEmpty {
      permissionStatus = update.message
    }
    switch update.snapshot.state {
    case .failed, .timedOut:
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .failed(
          sessionId: update.snapshot.sessionId,
          failure: VoiceFailure(
            code: update.snapshot.state.rawValue.lowercased(),
            recoverable: true,
            stage: .agentRunning,
            detail: update.message.ifBlank("The remote Agent run failed.")
          )
        )
      )
      clearActiveVoiceReplySession(update.snapshot.sessionId)
    case .cancelled:
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .cancelled(sessionId: update.snapshot.sessionId, reasonCode: "remote_cancelled")
      )
      clearActiveVoiceReplySession(update.snapshot.sessionId)
    case .created, .accepted, .queued, .starting, .running, .waitingInput, .waitingApproval, .cancelling, .completed:
      break
    }
  }

  private func handleIncomingVoiceReplyDelta(_ message: ChatMessage) {
    guard activeVoiceReplyRouteKind == .cloudModel,
          let request = VoiceReplyPlaybackPolicy.request(
            message: message,
            settings: store.voiceSettings,
            languagePolicy: store.languagePolicy,
            activeSessionId: activeVoiceReplySessionId,
            activeTargetContactId: activeVoiceReplyContactId
          ) else {
      return
    }
    _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
      .modelDelta(sessionId: request.sessionId, text: request.text)
    )
    if progressiveVoiceReplySessionId != request.sessionId {
      progressiveVoiceReplySessionId = request.sessionId
      progressiveVoiceReplyText = ""
      activeVoiceReplyPlaybackSessionId = request.sessionId
      replySpeech.beginProgressive(request) { started in
        _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
          .playbackStarted(sessionId: started.sessionId, utteranceId: started.utteranceId)
        )
        permissionStatus = t("Speaking reply", "Speaking reply")
      } onDone: { done, success, _ in
        completeVoiceReplyPlayback(done, success: success)
      }
    }
    appendProgressiveVoiceReply(request: request, content: request.text, isFinal: false)
  }

  private func appendProgressiveVoiceReply(
    request: VoiceReplyPlaybackRequest,
    content: String,
    isFinal: Bool
  ) {
    guard progressiveVoiceReplySessionId == request.sessionId else { return }
    let normalized = String(content.prefix(VoiceReplyPlaybackPolicy.maximumSpokenCharacters))
    let delta: String
    if normalized.hasPrefix(progressiveVoiceReplyText) {
      delta = String(normalized.dropFirst(progressiveVoiceReplyText.count))
    } else {
      delta = normalized
    }
    progressiveVoiceReplyText = normalized
    replySpeech.appendProgressive(delta, isFinal: isFinal)
  }

  private func completeVoiceReplyPlayback(_ done: VoiceReplyPlaybackRequest, success: Bool) {
    let wasActiveSession = activeVoiceReplySessionId == done.sessionId ||
      activeVoiceReplyPlaybackSessionId == done.sessionId
    if success {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: done.sessionId))
    } else {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .cancelled(sessionId: done.sessionId, reasonCode: "tts_cancelled")
      )
    }
    clearActiveVoiceReplySession(done.sessionId)
    if wasActiveSession {
      permissionStatus = ""
    }
  }

  private func finishVoiceSendIfNoReplyPlaybackStarted(_ plan: VoiceTranscriptRoutePlan) {
    if plan.routeDecision.kind == .localAction {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.localActionCompleted(sessionId: plan.sessionId))
      clearActiveVoiceReplySession(plan.sessionId)
      permissionStatus = ""
      return
    }
    if !store.voiceSettings.speakReplies {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: plan.sessionId))
      clearActiveVoiceReplySession(plan.sessionId)
      permissionStatus = ""
      return
    }
    if plan.routeDecision.kind == .cloudModel,
       activeVoiceReplyPlaybackSessionId != plan.sessionId,
       !replySpeech.isSpeaking,
       activeVoiceReplySessionId == plan.sessionId {
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: plan.sessionId))
      clearActiveVoiceReplySession(plan.sessionId)
      permissionStatus = ""
    }
  }

  private func clearActiveVoiceReplySession(_ sessionId: String) {
    if activeVoiceReplySessionId == sessionId {
      activeVoiceReplySessionId = ""
      activeVoiceReplyContactId = ""
      activeVoiceReplyRouteKind = nil
    }
    if activeVoiceReplyPlaybackSessionId == sessionId {
      activeVoiceReplyPlaybackSessionId = ""
    }
    if progressiveVoiceReplySessionId == sessionId {
      progressiveVoiceReplySessionId = ""
      progressiveVoiceReplyText = ""
    }
  }

  private func recognitionPreferenceLocalizationKey(_ preference: VoiceRecognitionPreference) -> String {
    switch preference {
    case .automatic:
      return "voice_asr_mode_auto"
    case .onlineFast:
      return "voice_asr_mode_online_fast"
    case .localPrivate:
      return "voice_asr_mode_local_private"
    case .localHighAccuracy:
      return "voice_asr_mode_local_accurate"
    case .remoteNode:
      return "voice_asr_mode_remote_node"
    }
  }

  private var recognitionPreferences: [VoiceRecognitionPreference] {
    var preferences: [VoiceRecognitionPreference] = [
      .automatic,
      .onlineFast,
      .localPrivate,
      .localHighAccuracy,
    ]
    if VoiceFeatureFlags.isRemoteWhisperNodeEnabled(),
       store.voiceSettings.remoteWhisperAllowed,
       !coordinator.verifiedRemoteWhisperNodes.isEmpty {
      preferences.append(.remoteNode)
    }
    return preferences
  }

  private func recognitionPreferenceTitle(_ preference: VoiceRecognitionPreference) -> String {
    switch preference {
    case .automatic:
      return "Automatic"
    case .onlineFast:
      return "Online fast"
    case .localPrivate:
      return "Local private"
    case .localHighAccuracy:
      return "Local high accuracy"
    case .remoteNode:
      return "Remote node"
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct AgentSafetySettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  var body: some View {
    Form {
      Section(header: Text(t("agent_preference_mode_section", "Agent Preference Mode"))) {
        Picker(t("agent_preference_mode_section", "Agent Preference Mode"), selection: preferenceModeBinding) {
          ForEach(AgentPreferenceMode.allCases) { mode in
            Text(t(mode.titleKey, mode.titleFallback)).tag(mode)
          }
        }
        Text(t(store.agentPreferenceMode.detailKey, store.agentPreferenceMode.detailFallback))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Section(header: Text(t("Task Execution", "Task Execution"))) {
        Picker(t("Task execution", "Task execution"), selection: taskExecutionModeBinding) {
          ForEach(AgentTaskExecutionMode.allCases) { mode in
            Text(t(mode.displayTitle, mode.displayTitle)).tag(mode)
          }
        }
        Text(t(store.agentSafetySettings.taskExecutionMode.detail, store.agentSafetySettings.taskExecutionMode.detail))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Section(header: Text(t("Action Permissions", "Action Permissions"))) {
        Picker(t("Execution Mode", "Execution Mode"), selection: permissionModeBinding) {
          ForEach(AgentPermissionMode.allCases) { mode in
            Text(t(mode.displayTitle, mode.displayTitle)).tag(mode)
          }
        }
        Text(t(store.agentSafetySettings.permissionMode.detail, store.agentSafetySettings.permissionMode.detail))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Section(header: Text(t("Safety Guards", "Safety Guards"))) {
        Toggle(t("High Risk Guard", "High Risk Guard"), isOn: boolBinding(\.highRiskGuard))
        Toggle(t("Memory Capture", "Memory Capture"), isOn: boolBinding(\.memoryCapture))
        Toggle(t("Pause Execution", "Pause Execution"), isOn: boolBinding(\.executionPaused))
      }
      Section(header: Text(t("Allowed Action Surfaces", "Allowed Action Surfaces"))) {
        Toggle(t("Screen Observation", "Screen Observation"), isOn: boolBinding(\.screenObservationAllowed))
        Toggle(t("Local Actions", "Local Actions"), isOn: boolBinding(\.localActionsAllowed))
        Toggle(t("Connector Calls", "Connector Calls"), isOn: boolBinding(\.connectorCallsAllowed))
        Toggle(t("Device Control", "Device Control"), isOn: boolBinding(\.deviceControlAllowed))
      }
    }
    .navigationTitle(t("Agent Safety", "Agent Safety"))
  }

  private var preferenceModeBinding: Binding<AgentPreferenceMode> {
    Binding(
      get: { store.agentPreferenceMode },
      set: { value in store.updateAgentPreferenceMode(value) }
    )
  }

  private var taskExecutionModeBinding: Binding<AgentTaskExecutionMode> {
    Binding(
      get: { store.agentSafetySettings.taskExecutionMode },
      set: { value in store.updateAgentSafetySettings { $0.taskExecutionMode = value } }
    )
  }

  private var permissionModeBinding: Binding<AgentPermissionMode> {
    Binding(
      get: { store.agentSafetySettings.permissionMode },
      set: { value in store.updateAgentSafetySettings { $0.permissionMode = value } }
    )
  }

  private func boolBinding(_ keyPath: WritableKeyPath<AgentSafetySettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { store.agentSafetySettings[keyPath: keyPath] },
      set: { value in store.updateAgentSafetySettings { $0[keyPath: keyPath] = value } }
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private extension AgentTaskBudget {
  var costLimitLabel: String {
    maxCostMicros <= 0 ? "Unlimited" : String(format: "$%.2f", Double(maxCostMicros) / 1_000_000.0)
  }

  func localizedCostLimitLabel(language: String) -> String {
    maxCostMicros <= 0
      ? GalaxySSILocalization.string("Unlimited", fallback: "Unlimited", language: language)
      : String(format: "$%.2f", Double(maxCostMicros) / 1_000_000.0)
  }
}

struct HomeAssistantSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var isCheckingConnection = false
  @State private var connectionStatus = ""
  @State private var connectionStatusIsFailure = false

  var body: some View {
    Form {
      Section(header: Text(t("device_custom_section_connection", "Connection"))) {
        Toggle(t("galaxyssi.device.home_assistant_enable", "Enable Home Assistant"), isOn: boolBinding(\.enabled))
        TextField(t("galaxyssi.device.home_assistant_url", "Server URL"), text: stringBinding(\.baseUrl))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .keyboardType(.URL)
        SecureField(t("galaxyssi.device.home_assistant_token", "Access Token"), text: stringBinding(\.accessToken))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        if !store.homeAssistantSettings.maskedAccessToken.isEmpty {
          Text(String(format: t("Stored token: %@", "Stored token: %@"), store.homeAssistantSettings.maskedAccessToken))
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      Section(header: Text(t("galaxyssi.device.home_assistant_default_target_section", "Default Target"))) {
        TextField(t("galaxyssi.device.home_assistant_default_entity", "Default Entity"), text: stringBinding(\.defaultEntityId))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        Text(t("galaxyssi.device.home_assistant_default_entity_subtitle", "Example: light.living_room"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Section(header: Text(t("galaxyssi.common.status", "Status"))) {
        if store.homeAssistantSettings.configured {
          Label(t("galaxyssi.device.home_assistant_configured", "Configured"), systemImage: "checkmark.circle")
            .foregroundColor(.green)
        } else if store.homeAssistantSettings.credentialsConfigured {
          Label(t("galaxyssi.device.home_assistant_configured_disabled", "Configured, disabled"), systemImage: "pause.circle")
            .foregroundColor(.orange)
        } else {
          Label(t("galaxyssi.device.home_assistant_not_configured", "Not configured"), systemImage: "exclamationmark.triangle")
            .foregroundColor(.secondary)
        }
        if !connectionStatus.isEmpty {
          Label(
            connectionStatus,
            systemImage: connectionStatusIsFailure ? "exclamationmark.triangle" : "checkmark.circle"
          )
          .foregroundColor(connectionStatusIsFailure ? .orange : .green)
        }
        Button {
          checkConnection()
        } label: {
          Label(
            isCheckingConnection
              ? t("galaxyssi.device.home_assistant_checking", "Checking connection")
              : t("galaxyssi.device.home_assistant_check_connection", "Check connection"),
            systemImage: isCheckingConnection ? "arrow.triangle.2.circlepath" : "checkmark.shield"
          )
        }
        .disabled(!store.homeAssistantSettings.credentialsConfigured || isCheckingConnection)
      }
    }
    .navigationTitle(t("galaxyssi.device.home_assistant", "Home Assistant"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func boolBinding(_ keyPath: WritableKeyPath<HomeAssistantSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { store.homeAssistantSettings[keyPath: keyPath] },
      set: { value in store.updateHomeAssistantSettings { $0[keyPath: keyPath] = value } }
    )
  }

  private func stringBinding(_ keyPath: WritableKeyPath<HomeAssistantSettings, String>) -> Binding<String> {
    Binding(
      get: { store.homeAssistantSettings[keyPath: keyPath] },
      set: { value in store.updateHomeAssistantSettings { $0[keyPath: keyPath] = value } }
    )
  }

  private func checkConnection() {
    guard !isCheckingConnection else { return }
    let settings = store.homeAssistantSettings
    guard settings.credentialsConfigured else { return }
    isCheckingConnection = true
    connectionStatus = t("galaxyssi.device.home_assistant_checking", "Checking connection")
    connectionStatusIsFailure = false
    let nowMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    DispatchQueue.global(qos: .userInitiated).async {
      let provider = AgentIOSConfiguredHomeAssistantToolProvider(settingsProvider: { settings })
      let result = provider.connectionStatus(nowMillis: nowMillis)
      DispatchQueue.main.async {
        isCheckingConnection = false
        connectionStatus = result.isSuccess
          ? t("galaxyssi.device.home_assistant_connected", "Home Assistant connected")
          : result.message.ifBlank(t(
            "galaxyssi.device.home_assistant_connection_failed",
            "Home Assistant connection failed"
          ))
        connectionStatusIsFailure = !result.isSuccess
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct ResetPrivateDataView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @State private var confirmation = ""
  var onReset: () -> Void

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text(t("settings_reset_short", "Reset"))) {
          Text(t(
            "galaxyssi.settings.reset_private_data_warning",
            "This clears your identity, contacts, chats, pairing links, voice settings, agent safety settings, task budget, custom device connectors, Home Assistant configuration, model planner settings, and saved model keys on this device."
          ))
            .foregroundColor(.secondary)
          TextField("RESET", text: $confirmation)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled(true)
          Button(role: .destructive) {
            onReset()
            dismiss()
          } label: {
            Label(t("galaxyssi.settings.reset_private_data", "Reset Private Data"), systemImage: "trash")
          }
          .disabled(confirmation != "RESET")
        }
      }
      .navigationTitle(t("settings_reset_short", "Reset"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("common_cancel", "Cancel")) {
            dismiss()
          }
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct CloudModelProviderDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var showingAddModel = false
  var contactId: String

  private var contact: GalaxySSIContact? {
    store.contact(id: contactId)
  }

  var body: some View {
    Form {
      if let contact {
        Section(header: Text(t("galaxyssi.cloud.provider_section", "Provider"))) {
          Text(contact.displayName)
          Text(contact.cloudProvider.ifBlank(contact.id))
            .font(.caption)
            .foregroundColor(.secondary)
          if let selected = contact.selectedCloudModel {
            Label(String(format: t("Selected: %@", "Selected: %@"), selected.modelId), systemImage: "checkmark.circle")
          }
        }
        Section(header: Text(t("galaxyssi.cloud.selected_model_section", "Selected Model"))) {
          Picker(t("galaxyssi.cloud.model_picker", "Model"), selection: selectedModelBinding(contact)) {
            ForEach(contact.cloudModels) { model in
              Text(model.displayName).tag(model.modelId)
            }
          }
        }
        Section(header: Text(t("galaxyssi.cloud.models_section", "Models"))) {
          ForEach(contact.cloudModels) { model in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(model.displayName)
                  .font(.headline)
                Spacer()
                readinessLabel(for: model, contact: contact)
              }
              Text(model.modelId)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
              Text(model.endpoint)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
              Text(model.apiStyle.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
            }
          }
          .onDelete { offsets in
            let modelIds = offsets.map { contact.cloudModels[$0].modelId }
            for modelId in modelIds {
              store.deleteCloudModel(contactId: contact.id, modelId: modelId)
            }
          }
        }
        Button {
          showingAddModel = true
        } label: {
          Label(t("galaxyssi.cloud.add_model", "Add Model"), systemImage: "plus.circle")
        }
      } else {
        Section(header: Text(t("galaxyssi.cloud.provider_section", "Provider"))) {
          Text(t("galaxyssi.cloud.contact_not_found", "Cloud model contact not found."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(contact?.displayName ?? t("galaxyssi.status.cloud_model", "Cloud Model"))
    .sheet(isPresented: $showingAddModel) {
      AddCloudModelView(initialProvider: contact?.cloudProvider)
    }
  }

  private func selectedModelBinding(_ contact: GalaxySSIContact) -> Binding<String> {
    Binding(
      get: { contact.selectedCloudModelId },
      set: { next in
        store.setSelectedCloudModel(contactId: contact.id, modelId: next)
      }
    )
  }

  private func readinessLabel(for model: CloudModelConfig, contact: GalaxySSIContact) -> some View {
    let ready = CloudModelCredentialPolicy.isAutoRoutable(
      model: model,
      apiKey: store.apiKey(for: model),
      provider: contact.cloudProvider,
      setupStatus: contact.setupStatus
    )
    return Label(
      ready ? t("galaxyssi.status.ready", "Ready") : t("status_needs_setup", "Needs Setup"),
      systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.triangle"
    )
      .font(.caption)
      .foregroundColor(ready ? .green : .orange)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct AddCloudModelView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var selectedPreset: CloudModelPreset
  @State private var provider: String
  @State private var displayName: String
  @State private var modelId: String
  @State private var endpoint: String
  @State private var apiStyle: GalaxySSICloudAPIStyle
  @State private var apiKey = ""
  @State private var errorText = ""

  init(initialProvider: String? = nil) {
    let preset = CloudModelPreset.androidParity.first {
      $0.provider.localizedCaseInsensitiveCompare(initialProvider ?? "") == .orderedSame
    } ?? CloudModelPreset.androidParity.first!
    _selectedPreset = State(initialValue: preset)
    _provider = State(initialValue: initialProvider?.ifBlank(preset.provider) ?? preset.provider)
    _displayName = State(initialValue: preset.name)
    _modelId = State(initialValue: preset.modelId)
    _endpoint = State(initialValue: preset.endpoint)
    _apiStyle = State(initialValue: preset.apiStyle)
  }

  var body: some View {
    NavigationView {
      Form {
        Picker(t("galaxyssi.cloud.preset", "Preset"), selection: $selectedPreset) {
          ForEach(CloudModelPreset.androidParity) { preset in
            Text("\(preset.provider) \(preset.name)").tag(preset)
          }
        }
        .onChange(of: selectedPreset) { preset in
          provider = preset.provider
          displayName = preset.name
          modelId = preset.modelId
          endpoint = preset.endpoint
          apiStyle = preset.apiStyle
        }
        TextField(t("galaxyssi.cloud.provider_section", "Provider"), text: $provider)
        TextField(t("Display Name", "Display Name"), text: $displayName)
        TextField(t("cloud_model_id", "Model ID"), text: $modelId)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        TextField(t("device_custom_endpoint", "Endpoint"), text: $endpoint)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        Picker(t("galaxyssi.cloud.api_style", "API Style"), selection: $apiStyle) {
          ForEach(GalaxySSICloudAPIStyle.allCases) { style in
            Text(style.rawValue).tag(style)
          }
        }
        SecureField(t("API Key", "API Key"), text: $apiKey)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        if !errorText.isEmpty {
          Text(errorText)
            .foregroundColor(.red)
        }
      }
      .navigationTitle(t("galaxyssi.cloud.add_model", "Add Model"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("common_cancel", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("common_save", "Save")) { save() }
            .disabled(!canSave)
        }
      }
    }
  }

  private var canSave: Bool {
    !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      CloudModelCredentialPolicy.isStoredCredential(apiKey)
  }

  private func save() {
    do {
      _ = try store.addCloudModelContact(
        displayName: displayName,
        provider: provider,
        modelId: modelId,
        endpoint: endpoint,
        apiKey: apiKey,
        apiStyle: apiStyle
      )
      dismiss()
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct FriendRequestRow: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var request: GalaxySSIFriendRequest

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Color.galaxySSIAccent)
        Image(systemName: "person.badge.plus")
          .foregroundColor(.white)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 4) {
        Text(request.name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
        Text(request.galaxySSIId)
          .lineLimit(1)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
      }
      Spacer()
      Text(statusLabel(request.status))
        .font(.system(size: 12))
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.galaxySSISurface)
  }

  private func statusLabel(_ status: GalaxySSIFriendRequestStatus) -> String {
    switch status {
    case .pending:
      return t("galaxyssi.friend_request.pending", "Pending Verification")
    case .approved:
      return t("galaxyssi.friend_request.status_approved", "Approved")
    case .rejected:
      return t("galaxyssi.common.rejected", "Rejected")
    case .deleted:
      return t("galaxyssi.security_center.status_revoked", "Revoked")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private extension String {
  var chunkedFingerprint: String {
    String(filter { $0.isLetter || $0.isNumber }.prefix(64))
      .chunked(into: 32)
      .joined(separator: "\n")
  }

  func chunked(into size: Int) -> [String] {
    var chunks: [String] = []
    var index = startIndex
    while index < endIndex {
      let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
      chunks.append(String(self[index..<next]))
      index = next
    }
    return chunks
  }
}
