import AVFoundation
import BackgroundTasks
import CoreImage
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

private let signalASIStartupLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "com.signalasi.chat.ios",
  category: "startup"
)

enum SignalASIRuntimePlaintextProtection {
  private static let transientPrefixes = [
    "agent_audio_",
    "signalasi_tts_",
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
  private static let nestedTransientDirectories = ["signalasi/visible-capture"]
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
    SignalASIRichMediaPlaybackCoordinator.shared.pauseForRuntimeBoundary()
    notificationCenter.post(name: .signalASIRuntimePlaintextWillClear, object: nil)
    clearKnownTemporaryFiles(fileManager: fileManager)
  }

  static func leaveRuntimeBoundary(notificationCenter: NotificationCenter = .default) {
    guard setBoundaryActive(false) else { return }
    notificationCenter.post(name: .signalASIRuntimePlaintextDidRestore, object: nil)
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
  static let signalASIOpenContact = Notification.Name("signalasi.open_contact")
  static let signalASIRuntimePlaintextWillClear = Notification.Name(
    "signalasi.runtime_plaintext_will_clear"
  )
  static let signalASIRuntimePlaintextDidRestore = Notification.Name(
    "signalasi.runtime_plaintext_did_restore"
  )
}

final class SignalASIAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    signalASIStartupLogger.notice("UIApplication finished launching")
    SignalASIAttachmentAtRestCipher.removeLegacyPlaintextRoots()
    SignalASIRuntimePlaintextProtection.clearKnownTemporaryFiles()
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard SignalASIContactNotificationPresentationPolicy.shouldPresent(
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
      SignalASIContactNotificationPresentationPolicy.contactIdKey
    ] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !contactId.isEmpty {
      UserDefaults.standard.set(contactId, forKey: "signalasi.pending_open_contact")
      DispatchQueue.main.async {
        NotificationCenter.default.post(
          name: .signalASIOpenContact,
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

@main
struct SignalASIApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @UIApplicationDelegateAdaptor(SignalASIAppDelegate.self) private var appDelegate
  @StateObject private var store: SignalASIStore
  @StateObject private var coordinator: MessageCoordinator
  @StateObject private var agentStartupRecovery: AgentStartupRecoveryCoordinator
  @StateObject private var voiceAgentRunRecovery: VoiceAgentRunRecoveryCoordinator
  @StateObject private var workflowTriggerCoordinator: AgentWorkflowTriggerCoordinator
  @StateObject private var backgroundScheduler: AgentProactiveBackgroundScheduler

  init() {
    signalASIStartupLogger.notice("SignalASIApp initialization started")
    let store = SignalASIStore()
    signalASIStartupLogger.notice("SignalASIStore initialized")
    let coordinator = MessageCoordinator(store: store)
    signalASIStartupLogger.notice("MessageCoordinator initialized")
    _store = StateObject(wrappedValue: store)
    _coordinator = StateObject(wrappedValue: coordinator)
    _agentStartupRecovery = StateObject(wrappedValue: AgentStartupRecoveryCoordinator())
    _voiceAgentRunRecovery = StateObject(
      wrappedValue: VoiceAgentRunRecoveryCoordinator.shared
    )
    _workflowTriggerCoordinator = StateObject(
      wrappedValue: AgentWorkflowTriggerCoordinator(coordinator: coordinator)
    )
    _backgroundScheduler = StateObject(
      wrappedValue: AgentProactiveBackgroundScheduler(store: store, coordinator: coordinator)
    )
    signalASIStartupLogger.notice("SignalASIApp initialization finished")
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .environmentObject(coordinator)
        .environmentObject(agentStartupRecovery)
        .environmentObject(voiceAgentRunRecovery)
        .signalASITextScale(store.displaySettings)
        .onAppear {
          signalASIStartupLogger.notice("RootView appeared")
          coordinator.start()
          agentStartupRecovery.start(store: store)
          voiceAgentRunRecovery.start()
          workflowTriggerCoordinator.start()
          backgroundScheduler.start()
          requestNotificationPermissionIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
          if phase == .active {
            store.restoreRuntimePlaintextAfterForeground()
            SignalASIRuntimePlaintextProtection.leaveRuntimeBoundary()
          } else {
            store.clearRuntimePlaintextForBackground()
            SignalASIRuntimePlaintextProtection.enterRuntimeBoundary()
          }
        }
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

struct RootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var store: SignalASIStore
  @State private var systemLocaleRevision = 0

  private var interfaceLanguage: String {
    // Re-evaluate automatic language after iOS reports a locale or time change.
    _ = systemLocaleRevision
    return LanguagePolicySettings.resolveInterface(store.languagePolicy.interfaceLanguage)
  }

  var body: some View {
    ZStack {
      SignalASIMainTabView()
        .accentColor(.signalASIAccent)
        .signalASIInterfaceLanguage(interfaceLanguage)
        .id(interfaceLanguage)
      if scenePhase != .active {
        Color.signalASIPageBackground
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
        await SignalASINavigationContentPrewarm.prepare(store: store)
      }
  }
}

private extension View {
  @ViewBuilder
  func signalASITextScale(_ settings: AppDisplaySettings) -> some View {
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

struct ChatListView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var searchText = ""
  @State private var contactPendingChatDeletion: SignalASIContact?
  @State private var openedContactId = ""
  var showsBackButton = true
  var onNavigateToMainTab: ((SignalASIMainTab) -> Void)? = nil
  var onBackToMainTab: (() -> Void)? = nil
  var initialContactId = ""
  var onInitialContactHandled: (() -> Void)? = nil

  private var filteredContacts: [SignalASIContact] {
    store.chatContacts(matching: searchText)
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        NavigationLink(
          destination: ConversationView(contactId: openedContactId),
          isActive: Binding(
            get: { !openedContactId.isEmpty },
            set: { active in
              if !active {
                openedContactId = ""
              }
            }
          )
        ) {
          EmptyView()
        }
        .frame(width: 0, height: 0)
        .hidden()
        SignalASITopBar(
          title: "SignalASI",
          onTitleTap: showsBackButton ? nil : {
            onNavigateToMainTab?(.voice)
          },
          leading: {
            if showsBackButton {
              SignalASIBackButton()
            } else if let onBackToMainTab {
              Button(action: onBackToMainTab) {
                Image(systemName: "chevron.left")
                  .font(.system(size: 22, weight: .semibold))
                  .foregroundColor(.signalASITextPrimary)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(Text(t("signalasi.common.back", "Back")))
            } else {
              Color.clear
            }
          },
          trailing: {
            NavigationLink(destination: AddContactView()) {
              Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("signalasi.add_contact.title", "Add")))
          }
        )
        VStack(spacing: 10) {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
              .foregroundColor(.signalASITextSecondary)
            TextField(t("signalasi.search.chats", "Search chats"), text: $searchText)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled(true)
          }
          .font(.system(size: 15))
          .padding(.horizontal, 12)
          .frame(height: 36)
          .background(Color.signalASISearchBackground)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          ScrollView {
            LazyVStack(spacing: 0) {
              if filteredContacts.isEmpty {
                Text(t("signalasi.empty.chats", "No matching chats"))
                  .font(.system(size: 15))
                  .foregroundColor(.signalASITextSecondary)
                  .frame(maxWidth: .infinity, minHeight: 90)
              } else {
                ForEach(filteredContacts) { contact in
                  NavigationLink(destination: ConversationView(contactId: contact.id)) {
                    ContactRow(contact: contact, summary: store.conversationSummary(for: contact.id))
                  }
                  .buttonStyle(.plain)
                  .contextMenu {
                    Button(role: .destructive) {
                      contactPendingChatDeletion = contact
                    } label: {
                      Label(t("delete_chat_title", "Delete Chat"), systemImage: "trash")
                    }
                  }
                  .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                      contactPendingChatDeletion = contact
                    } label: {
                      Label(t("delete_chat_title", "Delete Chat"), systemImage: "trash")
                    }
                  }
                  if contact.id != filteredContacts.last?.id {
                    Divider()
                      .background(Color.signalASISeparator)
                      .padding(.leading, 66)
                  }
                }
              }
            }
            .background(Color.signalASISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .onAppear(perform: openInitialContactIfNeeded)
    .onChange(of: initialContactId) { _ in
      openInitialContactIfNeeded()
    }
    .onChange(of: coordinator.pairingRevocationRevision) { _ in
      closeRevokedContactIfNeeded()
    }
    .alert(
      t("delete_chat_title", "Delete Chat"),
      isPresented: Binding(
        get: { contactPendingChatDeletion != nil },
        set: { visible in
          if !visible {
            contactPendingChatDeletion = nil
          }
        }
      )
    ) {
      Button(role: .destructive) {
        if let contact = contactPendingChatDeletion {
          store.deleteMessages(for: contact.id)
        }
        contactPendingChatDeletion = nil
      } label: {
        Text(t("common_delete", "Delete"))
      }
      Button(role: .cancel) {
        contactPendingChatDeletion = nil
      } label: {
        Text(t("common_cancel", "Cancel"))
      }
    } message: {
      Text(
        t(
          "delete_chat_subtitle",
          "Only local chat history is deleted. Contacts are not affected."
        )
      )
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private func openInitialContactIfNeeded() {
    guard openedContactId.isEmpty,
          !initialContactId.isBlank,
          store.contact(id: initialContactId) != nil else {
      return
    }
    openedContactId = initialContactId
    onInitialContactHandled?()
  }

  private func closeRevokedContactIfNeeded() {
    guard !openedContactId.isEmpty,
          coordinator.lastRevokedContactIds.contains(openedContactId) else {
      return
    }
    openedContactId = ""
  }
}

private struct SignalASIConversationVoiceRiskConfirmation: Identifiable {
  let id = UUID()
  var transcript: String
  var risk: VoiceCommandRisk
  var correctionReview: VoiceTranscriptCorrectionReview?
  var sessionId: String
}

struct ConversationView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var draft = ""
  @State private var attachments: [SignalASIDraftAttachment] = []
  @State private var attachmentMenuPresented = false
  @State private var fileImporterPresented = false
  @State private var photoPickerPresented = false
  @State private var cameraPickerPresented = false
  @State private var attachmentError = ""
  @State private var composerTextModeActive = false
  @State private var retryingMessageIDs: Set<UUID> = []
  @State private var transcribingVoiceMessageIDs: Set<UUID> = []
  @State private var peerVoiceTranscriptionError = ""
  @State private var cloudModelSwitchPresented = false
  @State private var selectedMessageForDetails: ChatMessage?
  @State private var runtimeArtifactPreview: SignalASIRuntimeArtifactPreview?
  @State private var runtimeArtifactDocument: SignalASIRuntimeArtifactDocument?
  @State private var runtimeArtifactExportPresented = false
  @State private var runtimeArtifactExportFilename = ""
  @State private var runtimeArtifactError = ""
  @State private var agentSessionsShortcutActive = false
  @State private var scanShortcutActive = false
  @State private var visibleMessageCount = 100
  @State private var loadingOlderMessages = false
  @State private var initialMessageScrollCompleted = false
  @State private var messageWindowContactId = ""
  @State private var pendingVoiceRiskConfirmation: SignalASIConversationVoiceRiskConfirmation?
  @State private var visibilityToken = UUID()
  var contactId: String

  private var contact: SignalASIContact {
    store.contact(id: contactId) ?? SignalASIContact.hermes()
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
      return t("signalasi.peer.transport_offline", "SignalASI Link offline")
    }
    let setupDetail = contact.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines)
    switch contact.deliveryMode {
    case .cloudAPI:
      return contact.selectedCloudModel?.modelId ?? contact.cloudProvider.ifBlank(t("signalasi.status.cloud_model", "Cloud model"))
    case .link, .pcConnector:
      return contact.isCommunicable
        ? t("chat_link_encrypted", "SignalASI Link encrypted")
        : setupDetail.ifBlank(t("signalasi.status.waiting_pairing", "Waiting for Desktop pairing"))
    case .local:
      return setupDetail.ifBlank(t("signalasi.status.local", "Local"))
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
    return contact.cloudProvider.ifBlank(t("signalasi.status.cloud_model", "Cloud model"))
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
        .background(Color.signalASIPageBackground)
        .onAppear {
          resetMessageWindowIfNeeded()
          guard !initialMessageScrollCompleted,
                let last = renderedMessages.last else { return }
          DispatchQueue.main.async {
            proxy.scrollTo(last.id, anchor: .bottom)
            initialMessageScrollCompleted = true
          }
        }
        .onChange(of: displayedMessages.count) { _ in
          if let last = renderedMessages.last {
            withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
          store.markContactRead(contact.id)
        }
        .onChange(of: waitingMessageIDs.count) { _ in
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
          .background(Color.signalASISeparator)
        if peerSendPending {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text(t("signalasi.peer.send_pending", "Sending to device..."))
              .font(.caption)
              .foregroundColor(.signalASITextSecondary)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 14)
          .padding(.top, 8)
        }
        SignalASIConversationComposer(
          draft: $draft,
          attachments: $attachments,
          attachmentError: $attachmentError,
          attachmentMenuPresented: $attachmentMenuPresented,
          textModeActive: $composerTextModeActive,
          deviceInputPolicy: deviceInputPolicy,
          voiceSettings: store.voiceSettings,
          dedicatedPeerVoiceCapture: SignalASIPeerVoiceMessageAudio.shouldUseDedicatedCapture(
            purpose: "chat_message",
            isPersonContact: isPhonePersonContact
          ),
          onSend: sendCurrentMessage,
          onVoiceTranscript: sendVoiceTranscript,
          t: t
        )
        .disabled(peerSendPending)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .background(navigationShortcuts)
    .overlay(attachmentMenuOverlay)
    .navigationBarHidden(true)
    .onAppear {
      SignalASIVisibleConversationTracker.shared.markVisible(
        contactId: contact.id,
        token: visibilityToken
      )
      resetMessageWindowIfNeeded()
      store.markContactRead(contact.id)
    }
    .onChange(of: contactId) { _ in
      SignalASIVisibleConversationTracker.shared.markVisible(
        contactId: contact.id,
        token: visibilityToken
      )
      resetMessageWindowIfNeeded()
    }
    .onDisappear {
      SignalASIVisibleConversationTracker.shared.markHidden(token: visibilityToken)
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
    .sheet(isPresented: $photoPickerPresented) {
      PhotoLibraryPickerView { attachment in
        appendAttachment(attachment)
      }
    }
    .fullScreenCover(isPresented: $cameraPickerPresented) {
      CameraAttachmentPickerView { attachment in
        appendAttachment(attachment)
      }
    }
    .sheet(item: $selectedMessageForDetails) { message in
      SignalASIMessageActionsView(message: message, contact: contact)
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
      Button(t("signalasi.common.done", "Done"), role: .cancel) {
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
      Button(t("signalasi.common.done", "Done"), role: .cancel) {
        peerVoiceTranscriptionError = ""
      }
    } message: {
      Text(peerVoiceTranscriptionError)
    }
    .alert(item: $pendingVoiceRiskConfirmation) { confirmation in
      Alert(
        title: Text(t("signalasi.voice.risk_confirmation_title", "Confirm voice command")),
        message: Text(VoiceRiskConfirmationMessageFormatter.message(
          text: confirmation.transcript,
          riskLabel: voiceRiskLabel(confirmation.risk),
          correctionReview: confirmation.correctionReview,
          localize: t
        )),
        primaryButton: .default(Text(t("signalasi.voice.risk_confirmation_execute", "Execute"))) {
          executeRiskConfirmedVoiceTranscript(confirmation)
        },
        secondaryButton: .cancel(Text(t("signalasi.voice.risk_confirmation_edit", "Edit"))) {
          editRiskConfirmedVoiceTranscript(confirmation)
        }
      )
    }
    .sheet(isPresented: $cloudModelSwitchPresented) {
      NavigationView {
        SignalASICloudModelSwitchView(contactId: contact.id, dismissAfterSelection: true)
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
    if SignalASIConversationDateDivider.shouldShow(
      for: message.createdAt,
      previous: index > 0 ? renderedMessages[index - 1].createdAt : nil
    ) {
      SignalASIConversationDateDivider(
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
          if SignalASIMessageActionPolicy.usesInlineActions(for: contact) {
            if SignalASIPeerMessageActionPolicy.voiceAttachment(in: message) != nil {
              Button {
                transcribePeerVoiceMessage(message)
              } label: {
                Label(
                  transcribingVoiceMessageIDs.contains(message.id)
                    ? t("peer_voice_transcribing", "Transcribing...")
                    : t("peer_voice_transcribe", "Transcribe"),
                  systemImage: "text.bubble"
                )
              }
              .disabled(transcribingVoiceMessageIDs.contains(message.id))
            } else {
              Button {
                UIPasteboard.general.string = SignalASIMessageActionPolicy.copyText(for: message)
              } label: {
                Label(t("signalasi.common.copy", "Copy"), systemImage: "doc.on.doc")
              }
            }
            Button(role: .destructive) {
              store.deleteMessage(message.id, contactId: contact.id)
            } label: {
              Label(t("signalasi.message.delete", "Delete Message"), systemImage: "trash")
            }
          } else {
            Button {
              selectedMessageForDetails = message
            } label: {
              Label(t("signalasi.message.details", "Details"), systemImage: "info.circle")
            }
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
  }

  private func dismissIfRevoked() {
    guard coordinator.lastRevokedContactIds.contains(contactId) else { return }
    dismiss()
  }

  private func loadOlderMessages(anchorID: UUID, proxy: ScrollViewProxy) {
    guard initialMessageScrollCompleted,
          !loadingOlderMessages,
          visibleMessageCount < displayedMessages.count else { return }
    loadingOlderMessages = true
    let nextCount = min(visibleMessageCount + 100, displayedMessages.count)
    visibleMessageCount = nextCount
    DispatchQueue.main.async {
      proxy.scrollTo(anchorID, anchor: .top)
      loadingOlderMessages = false
    }
  }

  private var conversationHeader: some View {
    HStack(spacing: 8) {
      Button {
        if composerTextModeActive {
          composerTextModeActive = false
        } else {
          dismiss()
        }
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("signalasi.common.back", "Back")))
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
          .foregroundColor(.signalASIInsightText)
          .padding(.horizontal, 8)
          .frame(maxWidth: 126, minHeight: 32)
          .background(Color.signalASIInsightBackground)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 56)
    .background(Color.signalASIBarBackground)
  }

  private var contactIdentityHeader: some View {
    HStack(spacing: 8) {
      AvatarView(contact: contact, size: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(contactTitle)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        HStack(spacing: 5) {
          Circle()
            .fill(contactStatusIsOnline ? Color.signalASIAccent : Color.signalASITextSecondary)
            .frame(width: 7, height: 7)
          Text(contactStatusText)
            .font(.system(size: 11))
            .foregroundColor(.signalASITextSecondary)
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
      return store.profile.name.ifBlank(SignalASIDeviceIdentityName.current(profile: store.profile))
    default:
      return contact.displayName
    }
  }

  @ViewBuilder
  private var attachmentMenuOverlay: some View {
    if attachmentMenuPresented {
      ZStack(alignment: .bottom) {
        Color.black.opacity(0.28)
          .ignoresSafeArea()
          .onTapGesture {
            withAnimation(.easeIn(duration: 0.12)) {
              attachmentMenuPresented = false
            }
          }
        VStack(spacing: 0) {
          Spacer(minLength: 0)
          VStack(spacing: 0) {
            if isAgentSessionContact {
              SignalASIAttachmentMenuRow(
                title: t("agent_attachment_new_task", "New session"),
                systemImage: "square.and.pencil"
              ) {
                dismissAttachmentMenu(then: createAgentConversation)
              }
              SignalASIAttachmentMenuDivider()
              SignalASIAttachmentMenuRow(
                title: t("agent_attachment_sessions", "Sessions"),
                systemImage: "list.bullet.rectangle"
              ) {
                dismissAttachmentMenu(then: {
                  agentSessionsShortcutActive = true
                })
              }
              SignalASIAttachmentMenuDivider()
            }
            SignalASIAttachmentMenuRow(
              title: t("agent_attachment_scan", "Scan"),
              systemImage: "qrcode.viewfinder"
            ) {
              dismissAttachmentMenu(then: {
                scanShortcutActive = true
              })
            }
            SignalASIAttachmentMenuDivider()
            SignalASIAttachmentMenuRow(
              title: t("agent_attachment_take_photo", "Take photo"),
              systemImage: "camera"
            ) {
              dismissAttachmentMenu(then: openCameraAttachmentPicker)
            }
            SignalASIAttachmentMenuDivider()
            SignalASIAttachmentMenuRow(
              title: t("agent_attachment_add_photos", "Add photos"),
              systemImage: "photo.on.rectangle"
            ) {
              dismissAttachmentMenu(then: {
                photoPickerPresented = true
              })
            }
            SignalASIAttachmentMenuDivider()
            SignalASIAttachmentMenuRow(
              title: t("agent_attachment_add_file", "Add file"),
              systemImage: "doc"
            ) {
              dismissAttachmentMenu(then: {
                fileImporterPresented = true
              })
            }
          }
          .background(Color.signalASISurface)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .padding(.horizontal, 10)
          .padding(.bottom, 10)
        }
      }
      .transition(.opacity)
    }
  }

  @ViewBuilder
  private var navigationShortcuts: some View {
    NavigationLink(
      destination: SignalASIConversationHubView(),
      isActive: $agentSessionsShortcutActive
    ) {
      EmptyView()
    }
    .hidden()

    NavigationLink(
      destination: AddContactView(autoOpenScanner: true),
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
        runtimeArtifactPreview = SignalASIRuntimeArtifactPreview(
          title: payload.displayName,
          content: try AgentRuntimeArtifactUi.preview(file: file)
        )
      } else {
        runtimeArtifactDocument = SignalASIRuntimeArtifactDocument(data: try Data(contentsOf: file))
        runtimeArtifactExportFilename = payload.displayName
        runtimeArtifactExportPresented = true
      }
    } catch {
      runtimeArtifactError = error.localizedDescription
    }
  }

  private func dismissAttachmentMenu(then action: @escaping () -> Void) {
    withAnimation(.easeIn(duration: 0.12)) {
      attachmentMenuPresented = false
    }
    action()
  }

  private func sendCurrentMessage() {
    let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let outgoingAttachments = attachments
    let text = cleanDraft.ifBlank(attachmentLabel(for: outgoingAttachments))
    let agentGoal = cleanDraft.isEmpty && !outgoingAttachments.isEmpty
      ? t("agent_attachment_default_goal", "The user attached files without stating a task. Ask one concise question about what to do and offer four to six concrete actions suited to the file types. Mention only the file names; do not inspect, summarize, or return the attachments.")
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
        let transcript = try await SignalASIPeerVoiceTranscriber.shared.transcribe(
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

  private func sendVoiceTranscript(_ submission: SignalASIVoiceTranscriptSubmission) {
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
      pendingVoiceRiskConfirmation = SignalASIConversationVoiceRiskConfirmation(
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
    submission: SignalASIVoiceTranscriptSubmission,
    data: Data
  ) -> SignalASIDraftAttachment {
    let identity = submission.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(UUID().uuidString.lowercased())
    let stem = "voice-\(identity.prefix(80))"
    let fileExtension = submission.audioFileExtension.ifBlank("wav")
    let sourceURL = submission.audioSourceURL
    return SignalASIDraftAttachment(
      id: identity,
      displayName: "\(stem).\(fileExtension)",
      mimeType: submission.audioMimeType,
      data: data,
      sourceDescription: sourceURL?.absoluteString ?? ""
    )
  }

  private func executeRiskConfirmedVoiceTranscript(
    _ confirmation: SignalASIConversationVoiceRiskConfirmation
  ) {
    guard VoiceExecutionLedgerBridge.claimPrimaryDispatch(sessionId: confirmation.sessionId) else {
      return
    }
    draft = confirmation.transcript
    sendCurrentMessage()
  }

  private func editRiskConfirmedVoiceTranscript(
    _ confirmation: SignalASIConversationVoiceRiskConfirmation
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
      return t("signalasi.voice.risk_critical", "critical")
    case .high:
      return t("signalasi.voice.risk_high", "high")
    case .medium:
      return t("signalasi.voice.risk_medium", "medium")
    case .low:
      return t("signalasi.voice.risk_low", "low")
    case .conversation:
      return t("signalasi.voice.risk_conversation", "conversation")
    }
  }

  private func createAgentConversation() {
    if isAgentSessionContact {
      _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
    }
    draft = ""
    attachments.removeAll()
    attachmentError = ""
  }

  private func openCameraAttachmentPicker() {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      attachmentError = t("agent_attachment_camera_unavailable", "Camera is unavailable")
      return
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .denied, .restricted:
      attachmentError = t("signalasi.scanner.camera_access_required", "Camera access is required to scan SignalASI QR codes.")
    case .authorized, .notDetermined:
      cameraPickerPresented = true
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
      attachmentError = t("agent_attachment_rejected", "Some attachments were skipped. You can add up to 10 files, 64 MB each.")
      return
    }
    attachments.append(attachment)
    attachmentError = ""
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct MessageDetailView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  var message: ChatMessage
  var contact: SignalASIContact

  var body: some View {
    NavigationView {
      Form {
        Section(t("signalasi.message.section", "Message")) {
          Text(messageSenderName)
          Text(message.content)
            .textSelection(.enabled)
          detailRow(t("signalasi.message.sent_time", "Sent Time"), message.createdAt.formatted(date: .abbreviated, time: .standard))
          detailRow(
            t("signalasi.common.status", "Status"),
            SignalASIChatDeliveryStatus.title(message.deliveryStatus, language: interfaceLanguage)
          )
        }
        Section(t("signalasi.security.status", "Security Status")) {
          Text(securityStatusText)
            .foregroundColor(.secondary)
        }
        Section(t("signalasi.delivery.trace", "Delivery Trace")) {
          if message.deliveryTrace.isEmpty {
            Text(t("signalasi.delivery.no_trace", "No trace yet"))
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
          Section(t("signalasi.identifiers", "Identifiers")) {
            if !message.conversationId.isEmpty {
              detailRow(t("signalasi.identifier.conversation", "Conversation"), message.conversationId)
            }
            if !message.turnId.isEmpty {
              detailRow(t("signalasi.identifier.turn", "Turn"), message.turnId)
            }
            if !message.remoteMessageId.isEmpty {
              detailRow(t("signalasi.identifier.remote_message", "Remote Message"), message.remoteMessageId)
            }
          }
        }
      }
      .navigationTitle(t("signalasi.message.actions", "Message Actions"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("signalasi.common.done", "Done")) {
            dismiss()
          }
        }
      }
    }
  }

  private var securityStatusText: String {
    switch contact.deliveryMode {
    case .link, .pcConnector:
      return t("signalasi.security.link", "Protected by the SignalASI Link end-to-end session")
    case .cloudAPI:
      return t("signalasi.security.cloud", "Protected locally; cloud model requests use the configured provider endpoint")
    case .local:
      return t("signalasi.security.local", "Stored locally on this device")
    }
  }

  private var messageSenderName: String {
    if message.isMine {
      return t("signalasi.message.sent_by_me", "Sent by me")
    }
    switch contact.id {
    case "system":
      return t("chat_system_notice", "System Notifications")
    case "me":
      return store.profile.name.ifBlank(SignalASIDeviceIdentityName.current(profile: store.profile))
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct MessageBubbleContainerWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

struct MessageBubble: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var messageContainerWidth: CGFloat = 0

  var message: ChatMessage
  var myAvatarData: Data? = nil
  var myIdentityFingerprint: String = ""
  var remoteContact: SignalASIContact? = nil
  var onAction: (AgentRichAction) -> Void = { _ in }
  var onActionWithMessage: ((ChatMessage, AgentRichAction) -> Void)?
  var onFormSubmit: (AgentRichBlock, [String: String]) -> Void = { _, _ in }
  var isVoiceTranscriptionPending = false
  var isRetrying = false
  var onRetry: () -> Void = {}

  var body: some View {
    if message.isSystem {
      Text(message.content)
        .font(.caption)
        .foregroundColor(.signalASITextSecondary)
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
          SignalASIRichContentView(
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
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundColor(.signalASITextPrimary)
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
            .background(messageBubbleColor)
            .overlay(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(message.isMine ? Color.clear : Color.signalASISeparator, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          if isVoiceTranscriptionPending || !message.voiceTranscript.isBlank {
            Text(
              isVoiceTranscriptionPending
                ? t("peer_voice_transcribing", "Transcribing...")
                : message.voiceTranscript
            )
              .font(.system(size: 14))
              .foregroundColor(.signalASITextSecondary)
              .multilineTextAlignment(message.isMine ? .trailing : .leading)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: bubbleMaxWidth, alignment: message.isMine ? .trailing : .leading)
              .accessibilityIdentifier("peer_voice_transcript_\(message.id.uuidString)")
          }
          HStack(spacing: 4) {
            Text(message.createdAt, style: .time)
            if message.isMine {
              Text(
                SignalASIPeerDeliveryPresentation.title(
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
                .accessibilityLabel(Text(t("signalasi.common.retry", "Retry")))
              }
            }
          }
          .font(.caption2)
          .foregroundColor(.signalASITextSecondary)
        }
        if message.isMine {
          SignalASIProfileAvatar(
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
    return message.isMine ? Color.signalASISentBubble : Color.signalASIIncomingBubble
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIRuntimeArtifactPreview: Identifiable {
  let id = UUID()
  let title: String
  let content: String
}

struct SignalASIRuntimeArtifactDocument: FileDocument {
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

struct SignalASIRuntimeArtifactPreviewView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  let preview: SignalASIRuntimeArtifactPreview
  @State private var copied = false

  var body: some View {
    NavigationView {
      ScrollView {
        Text(preview.content)
          .font(.system(size: 13, design: .monospaced))
          .foregroundColor(.signalASITextPrimary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
      }
      .background(Color.signalASIPageBackground)
      .navigationTitle(preview.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(SignalASILocalization.string("signalasi.common.done", fallback: "Done", language: interfaceLanguage)) {
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
            SignalASILocalization.string(
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

  let id = UUID()
  var plan: VoiceTranscriptRoutePlan
  var risk: VoiceCommandRisk
  var correctionReview: VoiceTranscriptCorrectionReview?
}

struct VoiceSettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
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
          Toggle(t("signalasi.voice.speech_recognition", "Speech recognition"), isOn: binding(\.speechRecognitionEnabled))
          Toggle(t("signalasi.voice.text_to_speech", "Text to speech"), isOn: binding(\.textToSpeechEnabled))
          Toggle(t("signalasi.voice.auto_send_transcripts", "Auto-send transcripts"), isOn: binding(\.autoSendTranscripts))
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
          NavigationLink(destination: SignalASIVoiceAgentRunsView()) {
            HStack {
              Image(systemName: "waveform.badge.mic")
                .foregroundColor(.signalASIAccent)
              Text(t("signalasi.voice_agent_runs.title", "Voice Agent runs"))
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
              Label(t("signalasi.voice.recorder", "Hold to Talk"), systemImage: "mic.circle")
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
        title: Text(t("signalasi.voice.risk_confirmation_title", "Confirm voice command")),
        message: Text(VoiceRiskConfirmationMessageFormatter.message(
          text: confirmation.plan.text,
          riskLabel: voiceRiskLabel(confirmation.risk),
          correctionReview: confirmation.correctionReview,
          localize: t
        )),
        primaryButton: .default(Text(t("signalasi.voice.risk_confirmation_execute", "Execute"))) {
          sendVoiceRoutePlan(confirmation.plan)
        },
        secondaryButton: .cancel(Text(t("signalasi.common.cancel", "Cancel"))) {
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
        "signalasi.voice.risk_confirmation_required",
        "Voice command requires confirmation"
      )
      return
    }
    sendVoiceRoutePlan(plan)
  }

  private func sendVoiceRoutePlan(_ plan: VoiceTranscriptRoutePlan) {
    guard VoiceExecutionLedgerBridge.claimPrimaryDispatch(sessionId: plan.sessionId) else {
      permissionStatus = t("signalasi.voice.duplicate_ignored", "Duplicate voice request ignored")
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
          agentId: plan.contact.signalASIId,
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
        "signalasi.voice.risk_confirmation_cancelled",
        "Voice command cancelled"
      )
    }
  }

  private func voiceRiskLabel(_ risk: VoiceCommandRisk) -> String {
    switch risk {
    case .critical:
      return t("signalasi.voice.risk_critical", "critical")
    case .high:
      return t("signalasi.voice.risk_high", "high")
    case .medium:
      return t("signalasi.voice.risk_medium", "medium")
    case .low:
      return t("signalasi.voice.risk_low", "low")
    case .conversation:
      return t("signalasi.voice.risk_conversation", "conversation")
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct AgentSafetySettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private extension AgentTaskBudget {
  var costLimitLabel: String {
    maxCostMicros <= 0 ? "Unlimited" : String(format: "$%.2f", Double(maxCostMicros) / 1_000_000.0)
  }

  func localizedCostLimitLabel(language: String) -> String {
    maxCostMicros <= 0
      ? SignalASILocalization.string("Unlimited", fallback: "Unlimited", language: language)
      : String(format: "$%.2f", Double(maxCostMicros) / 1_000_000.0)
  }
}

struct HomeAssistantSettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var isCheckingConnection = false
  @State private var connectionStatus = ""
  @State private var connectionStatusIsFailure = false

  var body: some View {
    Form {
      Section(header: Text(t("device_custom_section_connection", "Connection"))) {
        Toggle(t("signalasi.device.home_assistant_enable", "Enable Home Assistant"), isOn: boolBinding(\.enabled))
        TextField(t("signalasi.device.home_assistant_url", "Server URL"), text: stringBinding(\.baseUrl))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .keyboardType(.URL)
        SecureField(t("signalasi.device.home_assistant_token", "Access Token"), text: stringBinding(\.accessToken))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        if !store.homeAssistantSettings.maskedAccessToken.isEmpty {
          Text(String(format: t("Stored token: %@", "Stored token: %@"), store.homeAssistantSettings.maskedAccessToken))
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      Section(header: Text(t("signalasi.device.home_assistant_default_target_section", "Default Target"))) {
        TextField(t("signalasi.device.home_assistant_default_entity", "Default Entity"), text: stringBinding(\.defaultEntityId))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        Text(t("signalasi.device.home_assistant_default_entity_subtitle", "Example: light.living_room"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Section(header: Text(t("signalasi.common.status", "Status"))) {
        if store.homeAssistantSettings.configured {
          Label(t("signalasi.device.home_assistant_configured", "Configured"), systemImage: "checkmark.circle")
            .foregroundColor(.green)
        } else if store.homeAssistantSettings.credentialsConfigured {
          Label(t("signalasi.device.home_assistant_configured_disabled", "Configured, disabled"), systemImage: "pause.circle")
            .foregroundColor(.orange)
        } else {
          Label(t("signalasi.device.home_assistant_not_configured", "Not configured"), systemImage: "exclamationmark.triangle")
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
              ? t("signalasi.device.home_assistant_checking", "Checking connection")
              : t("signalasi.device.home_assistant_check_connection", "Check connection"),
            systemImage: isCheckingConnection ? "arrow.triangle.2.circlepath" : "checkmark.shield"
          )
        }
        .disabled(!store.homeAssistantSettings.credentialsConfigured || isCheckingConnection)
      }
    }
    .navigationTitle(t("signalasi.device.home_assistant", "Home Assistant"))
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
    connectionStatus = t("signalasi.device.home_assistant_checking", "Checking connection")
    connectionStatusIsFailure = false
    let nowMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    DispatchQueue.global(qos: .userInitiated).async {
      let provider = AgentIOSConfiguredHomeAssistantToolProvider(settingsProvider: { settings })
      let result = provider.connectionStatus(nowMillis: nowMillis)
      DispatchQueue.main.async {
        isCheckingConnection = false
        connectionStatus = result.isSuccess
          ? t("signalasi.device.home_assistant_connected", "Home Assistant connected")
          : result.message.ifBlank(t(
            "signalasi.device.home_assistant_connection_failed",
            "Home Assistant connection failed"
          ))
        connectionStatusIsFailure = !result.isSuccess
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct ResetPrivateDataView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @State private var confirmation = ""
  var onReset: () -> Void

  var body: some View {
    NavigationView {
      Form {
        Section(header: Text(t("settings_reset_short", "Reset"))) {
          Text(t(
            "signalasi.settings.reset_private_data_warning",
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
            Label(t("signalasi.settings.reset_private_data", "Reset Private Data"), systemImage: "trash")
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct CloudModelProviderDetailView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var showingAddModel = false
  var contactId: String

  private var contact: SignalASIContact? {
    store.contact(id: contactId)
  }

  var body: some View {
    Form {
      if let contact {
        Section(header: Text(t("signalasi.cloud.provider_section", "Provider"))) {
          Text(contact.displayName)
          Text(contact.cloudProvider.ifBlank(contact.id))
            .font(.caption)
            .foregroundColor(.secondary)
          if let selected = contact.selectedCloudModel {
            Label(String(format: t("Selected: %@", "Selected: %@"), selected.modelId), systemImage: "checkmark.circle")
          }
        }
        Section(header: Text(t("signalasi.cloud.selected_model_section", "Selected Model"))) {
          Picker(t("signalasi.cloud.model_picker", "Model"), selection: selectedModelBinding(contact)) {
            ForEach(contact.cloudModels) { model in
              Text(model.displayName).tag(model.modelId)
            }
          }
        }
        Section(header: Text(t("signalasi.cloud.models_section", "Models"))) {
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
          Label(t("signalasi.cloud.add_model", "Add Model"), systemImage: "plus.circle")
        }
      } else {
        Section(header: Text(t("signalasi.cloud.provider_section", "Provider"))) {
          Text(t("signalasi.cloud.contact_not_found", "Cloud model contact not found."))
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(contact?.displayName ?? t("signalasi.status.cloud_model", "Cloud Model"))
    .sheet(isPresented: $showingAddModel) {
      AddCloudModelView(initialProvider: contact?.cloudProvider)
    }
  }

  private func selectedModelBinding(_ contact: SignalASIContact) -> Binding<String> {
    Binding(
      get: { contact.selectedCloudModelId },
      set: { next in
        store.setSelectedCloudModel(contactId: contact.id, modelId: next)
      }
    )
  }

  private func readinessLabel(for model: CloudModelConfig, contact: SignalASIContact) -> some View {
    let ready = CloudModelCredentialPolicy.isAutoRoutable(
      model: model,
      apiKey: store.apiKey(for: model),
      provider: contact.cloudProvider,
      setupStatus: contact.setupStatus
    )
    return Label(
      ready ? t("signalasi.status.ready", "Ready") : t("status_needs_setup", "Needs Setup"),
      systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.triangle"
    )
      .font(.caption)
      .foregroundColor(ready ? .green : .orange)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct AddCloudModelView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @State private var selectedPreset: CloudModelPreset
  @State private var provider: String
  @State private var displayName: String
  @State private var modelId: String
  @State private var endpoint: String
  @State private var apiStyle: SignalASICloudAPIStyle
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
        Picker(t("signalasi.cloud.preset", "Preset"), selection: $selectedPreset) {
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
        TextField(t("signalasi.cloud.provider_section", "Provider"), text: $provider)
        TextField(t("Display Name", "Display Name"), text: $displayName)
        TextField(t("cloud_model_id", "Model ID"), text: $modelId)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        TextField(t("device_custom_endpoint", "Endpoint"), text: $endpoint)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        Picker(t("signalasi.cloud.api_style", "API Style"), selection: $apiStyle) {
          ForEach(SignalASICloudAPIStyle.allCases) { style in
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
      .navigationTitle(t("signalasi.cloud.add_model", "Add Model"))
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct FriendRequestRow: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var request: SignalASIFriendRequest

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Color.signalASIAccent)
        Image(systemName: "person.badge.plus")
          .foregroundColor(.white)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 4) {
        Text(request.name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
        Text(request.signalASIId)
          .lineLimit(1)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
      }
      Spacer()
      Text(statusLabel(request.status))
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.signalASISurface)
  }

  private func statusLabel(_ status: SignalASIFriendRequestStatus) -> String {
    switch status {
    case .pending:
      return t("signalasi.friend_request.pending", "Pending Verification")
    case .approved:
      return t("signalasi.friend_request.status_approved", "Approved")
    case .rejected:
      return t("signalasi.common.rejected", "Rejected")
    case .deleted:
      return t("signalasi.security_center.status_revoked", "Revoked")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
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
