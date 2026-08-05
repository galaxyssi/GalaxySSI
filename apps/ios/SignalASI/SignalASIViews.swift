import AVFoundation
import CoreImage
import SwiftUI
import UIKit

@main
struct SignalASIApp: App {
  @StateObject private var store: SignalASIStore
  @StateObject private var coordinator: MessageCoordinator

  init() {
    let store = SignalASIStore()
    _store = StateObject(wrappedValue: store)
    _coordinator = StateObject(wrappedValue: MessageCoordinator(store: store))
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .environmentObject(coordinator)
        .signalASITextScale(store.displaySettings)
        .onAppear { coordinator.start() }
    }
  }
}

struct RootView: View {
  @EnvironmentObject private var store: SignalASIStore

  private var interfaceLanguage: String {
    LanguagePolicySettings.resolveInterface(store.languagePolicy.interfaceLanguage)
  }

  var body: some View {
    AgentHomeView()
      .accentColor(.signalASIAccent)
      .signalASIInterfaceLanguage(store.languagePolicy.interfaceLanguage)
      .id(interfaceLanguage)
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

  func agentDeviceTouchTarget(_ policy: AgentDeviceInputTargetPolicy) -> some View {
    frame(
      minWidth: CGFloat(policy.minimumTouchTargetDp),
      minHeight: CGFloat(policy.minimumTouchTargetDp)
    )
    .contentShape(Rectangle())
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
  @State private var searchText = ""

  private var filteredContacts: [SignalASIContact] {
    store.visibleContacts(matching: searchText)
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        SignalASITopBar(
          title: "SignalASI",
          leading: { Color.clear },
          trailing: { Color.clear }
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
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct ContactRow: View {
  var contact: SignalASIContact
  var summary: ContactConversationSummary

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(contact: contact)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(contact.displayName)
            .font(.system(size: 16, weight: summary.hasUnreadMessages ? .semibold : .regular))
            .foregroundColor(.signalASITextPrimary)
          Spacer()
          if let latestMessage = summary.lastMessage {
            Text(latestMessage.createdAt, style: .time)
              .font(.system(size: 12))
              .foregroundColor(.signalASITextSecondary)
          }
        }
        Text(summary.lastMessage?.content ?? contact.setupDetail)
          .lineLimit(1)
          .font(.system(size: 14))
          .foregroundColor(summary.hasUnreadMessages ? .signalASITextPrimary : .signalASITextSecondary)
      }
      if summary.hasUnreadMessages {
        Text(summary.unreadCount > 99 ? "99+" : "\(summary.unreadCount)")
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundColor(.white)
          .frame(minWidth: 22)
          .padding(.horizontal, 5)
          .padding(.vertical, 3)
          .background(Capsule().fill(Color.signalASIUnreadRed))
          .accessibilityLabel(Text("\(summary.unreadCount) unread messages"))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.signalASISurface)
  }
}

struct ConversationView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var draft = ""
  @State private var attachments: [SignalASIDraftAttachment] = []
  @State private var attachmentMenuPresented = false
  @State private var fileImporterPresented = false
  @State private var photoPickerPresented = false
  @State private var cameraPickerPresented = false
  @State private var attachmentError = ""
  @State private var showingDeleteChatConfirmation = false
  @State private var cloudModelSwitchPresented = false
  @State private var selectedMessageForDetails: ChatMessage?
  var contactId: String

  private var contact: SignalASIContact {
    store.contact(id: contactId) ?? SignalASIContact.hermes()
  }

  private var deviceInputPolicy: AgentDeviceInputTargetPolicy {
    AgentDeviceProfileDetector.detect().inputTargetPolicy
  }

  private var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
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

  private var contactStatusText: String {
    let setupDetail = contact.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines)
    switch contact.deliveryMode {
    case .cloudAPI:
      return contact.selectedCloudModel?.modelId ?? contact.cloudProvider.ifBlank(t("signalasi.status.cloud_model", "Cloud model"))
    case .link:
      return contact.isCommunicable ? "SignalASI Link" : setupDetail.ifBlank(t("signalasi.status.waiting_pairing", "Waiting for Desktop pairing"))
    case .local:
      return setupDetail.ifBlank(t("signalasi.status.local", "Local"))
    }
  }

  private var cloudModelHeaderText: String {
    if let selected = contact.selectedCloudModel {
      return selected.displayName.ifBlank(selected.modelId)
    }
    return contact.cloudProvider.ifBlank(t("signalasi.status.cloud_model", "Cloud model"))
  }

  var body: some View {
    VStack(spacing: 0) {
      conversationHeader
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(displayedMessages) { message in
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
          .padding(.horizontal, 12)
          .padding(.top, 14)
          .padding(.bottom, 10)
        }
        .background(Color.signalASIPageBackground)
        .onChange(of: displayedMessages.count) { _ in
          if let last = displayedMessages.last {
            withAnimation(deviceInputPolicy.reduceMotion ? nil : Animation.default) {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
          store.markContactRead(contact.id)
        }
      }
      Divider()
        .background(Color.signalASISeparator)
      VStack(spacing: 8) {
        if !attachments.isEmpty {
          AttachmentPreviewStrip(attachments: attachments) { attachment in
            attachments.removeAll { $0.id == attachment.id }
          }
        }
        if !attachmentError.isEmpty {
          Text(attachmentError)
            .font(.caption)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack(spacing: 8) {
          Button {
            withAnimation(.easeOut(duration: 0.16)) {
              attachmentMenuPresented = true
            }
          } label: {
            Image(systemName: "plus")
              .font(.system(size: 20, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
          .agentDeviceTouchTarget(deviceInputPolicy)
          TextField(t("signalasi.message.input", "Message"), text: $draft)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Color.signalASISearchBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.signalASIInputStroke, lineWidth: 0.5)
            )
          Button {
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
              await coordinator.send(
                text,
                to: contact,
                attachments: outgoingAttachments,
                agentGoalOverride: agentGoal
              )
            }
          } label: {
            Image(systemName: "arrow.up")
              .font(.system(size: 17, weight: .bold))
              .foregroundColor(canSend ? .white : .signalASITextSecondary)
              .frame(width: 32, height: 32)
              .background(Circle().fill(canSend ? Color.signalASIAccent : Color.signalASIButtonSoft))
          }
          .agentDeviceTouchTarget(deviceInputPolicy)
          .disabled(!canSend)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(Color.signalASIBarBackground)
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .overlay(attachmentMenuOverlay)
    .navigationBarHidden(true)
    .onAppear {
      store.markContactRead(contact.id)
    }
    .alert(t("signalasi.chat.delete.title", "Delete Chat?"), isPresented: $showingDeleteChatConfirmation) {
      Button(t("signalasi.common.delete", "Delete"), role: .destructive) {
        store.deleteMessages(for: contact.id)
      }
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {}
    } message: {
      Text(t("signalasi.chat.delete.message", "Only local chat history is deleted. Contacts are not affected."))
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
    .sheet(isPresented: $cloudModelSwitchPresented) {
      NavigationView {
        SignalASICloudModelSwitchView(contactId: contact.id, dismissAfterSelection: true)
          .environmentObject(store)
      }
      .navigationViewStyle(StackNavigationViewStyle())
    }
  }

  private var conversationHeader: some View {
    HStack(spacing: 8) {
      SignalASIBackButton()
      AvatarView(contact: contact, size: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(contact.displayName)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        HStack(spacing: 5) {
          Circle()
            .fill(contact.isCommunicable ? Color.signalASIAccent : Color.signalASITextSecondary)
            .frame(width: 7, height: 7)
          Text(contactStatusText)
            .font(.system(size: 11))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(1)
        }
      }
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
      Button(role: .destructive) {
        showingDeleteChatConfirmation = true
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(store.messages(for: contact.id).isEmpty ? .signalASITextSecondary : .signalASITextPrimary)
          .frame(width: 40, height: 40)
      }
      .disabled(store.messages(for: contact.id).isEmpty)
    }
    .padding(.horizontal, 8)
    .frame(height: 56)
    .background(Color.signalASIBarBackground)
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
            }
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

  private var isAgentSessionContact: Bool {
    contact.id == "hermes" || contact.type == "agent" || contact.deliveryMode == .cloudAPI
  }

  private func dismissAttachmentMenu(then action: @escaping () -> Void) {
    withAnimation(.easeIn(duration: 0.12)) {
      attachmentMenuPresented = false
    }
    action()
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

struct MessageDetailView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  var message: ChatMessage
  var contact: SignalASIContact

  var body: some View {
    NavigationView {
      Form {
        Section(t("signalasi.message.section", "Message")) {
          Text(message.isMine ? t("signalasi.message.sent_by_me", "Sent by me") : contact.displayName)
          Text(message.content)
            .textSelection(.enabled)
          detailRow(t("signalasi.message.sent_time", "Sent Time"), message.createdAt.formatted(date: .abbreviated, time: .standard))
          detailRow(t("signalasi.common.status", "Status"), message.deliveryStatus.rawValue)
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
    case .link:
      return t("signalasi.security.link", "Protected by the SignalASI Link end-to-end session")
    case .cloudAPI:
      return t("signalasi.security.cloud", "Protected locally; cloud model requests use the configured provider endpoint")
    case .local:
      return t("signalasi.security.local", "Stored locally on this device")
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

struct MessageBubble: View {
  var message: ChatMessage

  var body: some View {
    HStack {
      if message.isMine { Spacer(minLength: 48) }
      VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
        Text(message.content)
          .padding(.horizontal, 12)
          .padding(.vertical, 9)
          .foregroundColor(.signalASITextPrimary)
          .background(messageBubbleColor)
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(message.isMine ? Color.clear : Color.signalASISeparator, lineWidth: 0.5)
          )
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        HStack(spacing: 4) {
          Text(message.createdAt, style: .time)
          if message.isMine {
            Text(message.deliveryStatus.rawValue)
          }
        }
        .font(.caption2)
        .foregroundColor(.signalASITextSecondary)
      }
      if !message.isMine { Spacer(minLength: 48) }
    }
  }

  private var messageBubbleColor: Color {
    if message.isSystem {
      return Color.signalASIButtonSoft
    }
    return message.isMine ? Color.signalASISentBubble : Color.signalASIIncomingBubble
  }
}

struct ContactsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var myQRCodePresented = false
  @State private var contactSearchText = ""

  private var filteredFriendRequests: [SignalASIFriendRequest] {
    let normalized = contactSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return store.pendingFriendRequests }
    return store.pendingFriendRequests.filter { request in
      searchMatches([
        request.name,
        request.signalASIId,
        request.mqttTopic,
        request.mqttInboxTopic
      ], query: normalized)
    }
  }

  private var filteredContacts: [SignalASIContact] {
    store.contactList(matching: contactSearchText)
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        SignalASITopBar(
          title: t("signalasi.tab.contacts", "Contacts"),
          leading: {
            Button {
              myQRCodePresented = true
            } label: {
              Image(systemName: "qrcode")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
            }
            .buttonStyle(.plain)
          },
          trailing: {
            NavigationLink(destination: AddContactView()) {
              Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
            }
            .buttonStyle(.plain)
          }
        )
        VStack(spacing: 10) {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
              .foregroundColor(.signalASITextSecondary)
            TextField(t("signalasi.search.contacts", "Search contacts"), text: $contactSearchText)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled(true)
          }
          .font(.system(size: 15))
          .padding(.horizontal, 12)
          .frame(height: 36)
          .background(Color.signalASISearchBackground)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          SignalASIContactDirectoryActionsView()
          ScrollView {
            VStack(alignment: .leading, spacing: 8) {
              if !filteredFriendRequests.isEmpty {
                sectionTitle(t("signalasi.new_friends", "New Friends"))
                VStack(spacing: 0) {
                  ForEach(filteredFriendRequests) { request in
                    NavigationLink(destination: FriendRequestDetailView(requestId: request.id)) {
                      FriendRequestRow(request: request)
                    }
                    .buttonStyle(.plain)
                  }
                }
                .background(Color.signalASISurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              }
              sectionTitle(t("signalasi.tab.contacts", "Contacts"))
              VStack(spacing: 0) {
                if filteredContacts.isEmpty {
                  Text(t("signalasi.empty.contacts", "No matching contacts"))
                    .font(.system(size: 15))
                    .foregroundColor(.signalASITextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                  ForEach(filteredContacts) { contact in
                    NavigationLink(destination: ContactDetailView(contactId: contact.id)) {
                      ContactRow(contact: contact, summary: store.conversationSummary(for: contact.id))
                    }
                    .buttonStyle(.plain)
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
            .padding(.bottom, 18)
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .sheet(isPresented: $myQRCodePresented) {
        MyContactQRCodeView()
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func searchMatches(_ fields: [String], query: String) -> Bool {
    fields.contains {
      $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct PairingView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var qrText = ""
  @State private var errorText = ""
  @State private var pairingNoticeIsError = false
  @State private var scannerPresented = false
  @State private var pendingPairing: PairingQRCode?

  var body: some View {
    NavigationView {
      Form {
        Section(t("signalasi.pairing.section_desktop", "Desktop")) {
          ForEach(store.serverLinks) { link in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(link.desktopName)
                Spacer()
                Text(
                  link.paired
                    ? t("signalasi.pairing.status_paired", "Paired")
                    : t("signalasi.pairing.status_pending", "Pending")
                )
                  .font(.caption)
                  .foregroundColor(link.paired ? .green : .orange)
              }
              Text(link.desktopFingerprint.chunkedFingerprint)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            }
          }
          .onDelete { offsets in
            offsets.map { store.serverLinks[$0].desktopId }.forEach(store.removeServer)
          }
        }
        Section(t("signalasi.pairing.section_qr", "QR")) {
          TextEditor(text: $qrText)
            .frame(minHeight: 120)
            .font(.system(.caption, design: .monospaced))
          HStack {
            Button {
              scannerPresented = true
            } label: {
              Label(t("signalasi.pairing.action_scan", "Scan"), systemImage: "qrcode.viewfinder")
            }
            Spacer()
            Button {
              Task { await submitPairing() }
            } label: {
              Label(t("signalasi.pairing.action_pair", "Pair"), systemImage: "checkmark.shield")
            }
            .disabled(qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        if let pendingPairing {
          Section(t("signalasi.pairing.confirm_title", "Confirm Pairing")) {
            VStack(alignment: .leading, spacing: 8) {
              Text(pendingPairing.desktopName)
                .font(.headline)
              Text(pendingPairing.desktopId)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
              Text(pendingPairing.desktopFingerprint.chunkedFingerprint)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
              Text(
                pendingPairing.access.fullDesktopExecutor
                  ? t("signalasi.pairing.access_full", "Desktop Executor")
                  : t("signalasi.pairing.access_restricted", "Restricted Desktop Access")
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }
            Button {
              Task { await submitPairing(qrText) }
            } label: {
              Label(t("signalasi.pairing.save_trust", "Save Trust"), systemImage: "checkmark.shield")
            }
          }
        }
        if !coordinator.pairingStatus.isEmpty || !errorText.isEmpty {
          Section(t("signalasi.pairing.section_status", "Status")) {
            Text(errorText.ifBlank(coordinator.pairingStatus))
              .foregroundColor(pairingNoticeIsError ? .red : .secondary)
          }
        }
      }
      .navigationTitle(t("signalasi.pairing.title", "Pairing"))
      .sheet(isPresented: $scannerPresented) {
        QRCodeScannerView(
          onCode: { value in
            qrText = value
            scannerPresented = false
            handleScannedQR(value)
          },
          onError: { message in
            scannerPresented = false
            errorText = message
            pairingNoticeIsError = true
          }
        )
      }
    }
  }

  private func handleScannedQR(_ value: String) {
    do {
      errorText = ""
      pairingNoticeIsError = false
      switch try SignalASIContactExchange.classifyQRCode(value) {
      case .desktopPairing(let pairing):
        pendingPairing = pairing
        errorText = t("signalasi.pairing.ready_to_confirm", "Review fingerprints, then save trust.")
        pairingNoticeIsError = false
      case .contact(let request):
        let stored = store.addFriendRequest(request)
        pendingPairing = nil
        errorText = String(
          format: t("signalasi.friend_request.added", "Friend request added for %@."),
          stored.name
        )
        pairingNoticeIsError = false
      }
    } catch {
      pendingPairing = nil
      errorText = error.localizedDescription
      pairingNoticeIsError = true
    }
  }

  private func submitPairing(_ contents: String? = nil) async {
    do {
      let value = (contents ?? qrText).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return }
      errorText = ""
      pairingNoticeIsError = false
      try await coordinator.pair(using: value)
      pendingPairing = nil
    } catch {
      errorText = error.localizedDescription
      pairingNoticeIsError = true
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct VoiceSettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @StateObject private var speech = SpeechCaptureService()
  @StateObject private var replySpeech = VoiceReplySpeechService()
  @State private var permissionStatus = ""
  @State private var activeVoiceReplySessionId = ""
  @State private var activeVoiceReplyContactId = ""
  @State private var activeVoiceReplyRouteKind: VoiceRouteKind?
  @State private var activeVoiceReplyPlaybackSessionId = ""

  var body: some View {
    NavigationView {
      Form {
        Section("Voice") {
          Toggle("Wake phrase", isOn: binding(\.wakeListeningEnabled))
          Toggle("Speech recognition", isOn: binding(\.speechRecognitionEnabled))
          Toggle("Text to speech", isOn: binding(\.textToSpeechEnabled))
          Toggle("Auto-send transcripts", isOn: binding(\.autoSendTranscripts))
          Toggle("Speak Replies", isOn: binding(\.speakReplies))
          TextField("Locale", text: Binding(
            get: { store.voiceSettings.preferredLocaleIdentifier },
            set: { value in store.updateVoiceSettings { $0.preferredLocaleIdentifier = value } }
          ))
          Picker("Wake Engine", selection: Binding(
            get: { store.voiceSettings.wakeProvider },
            set: { value in store.updateVoiceSettings { $0.wakeProvider = value } }
          )) {
            ForEach(VoiceWakeProvider.allCases) { provider in
              Text(t(provider.displayTitle, provider.displayTitle)).tag(provider)
            }
          }
          Picker("ASR Provider", selection: Binding(
            get: { store.voiceSettings.asrProvider },
            set: { value in store.updateVoiceSettings { $0.asrProvider = value } }
          )) {
            ForEach(VoiceASRProvider.allCases) { provider in
              Text(t(provider.displayTitle, provider.displayTitle)).tag(provider)
            }
          }
          NavigationLink(destination: VoiceWhisperModelSettingsView()) {
            HStack {
              Text("ASR Model")
              Spacer()
              Text(VoiceWhisperModelCatalog.model(store.voiceSettings.asrModelId).displayName)
                .foregroundColor(.secondary)
            }
          }
          Picker("Model selection", selection: Binding(
            get: { store.voiceSettings.asrRuntimeMode },
            set: { value in store.updateVoiceSettings { $0.asrRuntimeMode = value } }
          )) {
            ForEach(VoiceWhisperUserVoiceMode.allCases) { mode in
              Text(t(mode.displayTitle, mode.displayTitle)).tag(mode)
            }
          }
          Picker("TTS Provider", selection: Binding(
            get: { store.voiceSettings.ttsProvider },
            set: { value in store.updateVoiceSettings { $0.ttsProvider = value } }
          )) {
            ForEach(VoiceTTSProvider.allCases) { provider in
              Text(t(provider.displayTitle, provider.displayTitle)).tag(provider)
            }
          }
          TextField("Microsoft Voice", text: Binding(
            get: { store.voiceSettings.microsoftVoice },
            set: { value in store.updateVoiceSettings { $0.microsoftVoice = value } }
          ))
        }
        Section("Wake") {
          TextField("Wake Words", text: Binding(
            get: { store.voiceSettings.wakeWordsText },
            set: { value in store.updateVoiceSettings { $0.wakeWords = VoiceSettings.wakeWords(from: value) } }
          ))
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("Wake Threshold")
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
          TextField("Welcome Text", text: Binding(
            get: { store.voiceSettings.welcomeText },
            set: { value in store.updateVoiceSettings { $0.welcomeText = value } }
          ))
        }
        Section("Routing") {
          Picker("Voice Routing", selection: Binding(
            get: { store.voiceSettings.routingMode },
            set: { value in store.updateVoiceSettings { $0.routingMode = value } }
          )) {
            ForEach(VoiceRoutingMode.allCases) { mode in
              Text(t(mode.displayTitle, mode.displayTitle)).tag(mode)
            }
          }
          Picker("Default Target", selection: Binding(
            get: { store.voiceSettings.targetContactId },
            set: { value in store.updateVoiceSettings { $0.targetContactId = value } }
          )) {
            ForEach(store.visibleContacts) { contact in
              Text(contact.displayName).tag(contact.id)
            }
          }
        }
        Section("Recorder") {
          if speech.isRecording {
            Text(speech.transcript.ifBlank(t("Listening...", "Listening...")))
            Button(role: .destructive) {
              speech.stop()
            } label: {
              Label("Stop", systemImage: "stop.circle")
            }
          } else {
            Button {
              Task { await startRecording() }
            } label: {
              Label("Hold to Talk", systemImage: "mic.circle")
            }
          }
          if !permissionStatus.isEmpty {
            Text(permissionStatus)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
      .navigationTitle(t("Voice", "Voice"))
      .onAppear {
        coordinator.onIncomingMessage = handleIncomingVoiceReply
      }
      .onDisappear {
        coordinator.onIncomingMessage = nil
        replySpeech.stop()
        if !activeVoiceReplySessionId.isEmpty {
          _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
            .completed(sessionId: activeVoiceReplySessionId)
          )
          clearActiveVoiceReplySession(activeVoiceReplySessionId)
        }
      }
    }
  }

  private func binding(_ keyPath: WritableKeyPath<VoiceSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { store.voiceSettings[keyPath: keyPath] },
      set: { value in store.updateVoiceSettings { $0[keyPath: keyPath] = value } }
    )
  }

  private func startRecording() async {
    let granted = await speech.requestAuthorization(localeIdentifier: store.voiceSettings.preferredLocaleIdentifier)
    permissionStatus = granted ? "" : t("Microphone or speech permission is missing.", "Microphone or speech permission is missing.")
    guard granted else { return }
    do {
      speech.onVoiceCommand = handleVoiceCommand
      try speech.start(settings: store.voiceSettings)
    } catch {
      permissionStatus = error.localizedDescription
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
    _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
      .routeSelected(sessionId: plan.sessionId, decision: plan.routeDecision)
    )
    activeVoiceReplySessionId = plan.sessionId
    activeVoiceReplyContactId = plan.contact.id
    activeVoiceReplyRouteKind = plan.routeDecision.kind
    permissionStatus = String(format: t("Sending voice transcript to %@", "Sending voice transcript to %@"), plan.contact.displayName)
    Task {
      await coordinator.send(plan.text, to: plan.contact)
      await MainActor.run {
        finishVoiceSendIfNoReplyPlaybackStarted(plan)
      }
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
    switch activeVoiceReplyRouteKind {
    case .remoteAgent:
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentAccepted(sessionId: request.sessionId, runId: message.id.uuidString)
      )
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
        .agentProgress(sessionId: request.sessionId, runId: message.id.uuidString)
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
    } onDone: { done, _, _ in
      _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: done.sessionId))
      if activeVoiceReplyPlaybackSessionId == done.sessionId {
        activeVoiceReplyPlaybackSessionId = ""
      }
      clearActiveVoiceReplySession(done.sessionId)
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
    guard activeVoiceReplySessionId == sessionId else { return }
    activeVoiceReplySessionId = ""
    activeVoiceReplyContactId = ""
    activeVoiceReplyRouteKind = nil
    if activeVoiceReplyPlaybackSessionId == sessionId {
      activeVoiceReplyPlaybackSessionId = ""
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var showingAddModel = false
  @State private var notificationsStatus = ""
  @State private var backupPassword = ""
  @State private var backupIncludeMessages = true
  @State private var backupDocument: SignalASIBackupDocument?
  @State private var backupExportPresented = false
  @State private var backupImportPresented = false
  @State private var backupStatus = ""
  @State private var backupStatusIsError = false
  @State private var linkDiagnosticsSnapshot = SignalASILinkTransportDiagnostics.snapshot()

  var body: some View {
    NavigationView {
      Form {
        Section(t("signalasi.settings.profile", "Profile")) {
          HStack(spacing: 12) {
            SignalASILogoView(size: 42, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 3) {
              Text("SignalASI")
                .font(.headline)
                .foregroundColor(.signalASITextPrimary)
              Text(t("signalasi.agent.mode", "Agent Mode"))
                .font(.caption)
                .foregroundColor(.signalASITextSecondary)
            }
          }
          TextField(t("signalasi.settings.name", "Name"), text: Binding(
            get: { store.profile.name },
            set: { store.updateProfileName($0) }
          ))
          Text(store.profile.signalASIId)
            .font(.system(.caption, design: .monospaced))
          Text(store.profile.identityFingerprint.chunkedFingerprint)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
          NavigationLink(destination: SignalASIProfileIdentityView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_profile_title", "My SignalASI"))
              Text(t("cc_profile_subtitle_ios", "Identity protected by the iOS security boundary"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIControlCenterView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("settings_my_signalasi", "My SignalASI"))
              Text(t("cc_product_subtitle", "Agent operating system - This device online"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.pages", "App Pages")) {
          NavigationLink(destination: ChatListView()) {
            Label(t("signalasi.tab.messages", "Messages"), systemImage: "bubble.left.and.bubble.right")
          }
          NavigationLink(destination: ContactsView()) {
            Label(t("signalasi.tab.contacts", "Contacts"), systemImage: "person.2")
          }
          NavigationLink(destination: DiscoverView()) {
            Label(t("signalasi.tab.discover", "Discover"), systemImage: "safari")
          }
          NavigationLink(destination: SignalASIGeneralControlCenterView()) {
            Label(t("cc_general_page_title", "General"), systemImage: "gearshape")
          }
          NavigationLink(destination: SignalASIAppServicesView()) {
            Label(t("cc_app_services_page_title", "Apps & Services"), systemImage: "square.grid.2x2")
          }
        }
        Section(t("settings_control_general", "General")) {
          NavigationLink(destination: SignalASIGeneralSettingsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_general_page_title", "General"))
              Text(t("signalasi.general_settings.subtitle", "Language, appearance, text size, notifications, and app information"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.language", "Language")) {
          NavigationLink(destination: SignalASILanguageSettingsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.language_policy.title", "Voice & Language"))
              Text(languagePolicySummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIVoiceControlCenterView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_voice_title", "Voice & Interaction"))
              Text(t("signalasi.discover.voice.subtitle", "Wake, transcription and local voice models"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.display", "Display")) {
          NavigationLink(destination: SignalASITextSizeSettingsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_text_size_title", "Text Size"))
              Text(textScaleSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.agent_safety", "Agent Safety")) {
          NavigationLink(destination: SignalASISecurityCenterView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.security_center.title", "Security Center"))
              Text(t("signalasi.security_center.privacy_subtitle", "End-to-end encryption; only devices and contacts with confirmed fingerprints can communicate"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIGlobalAgentControlView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_global_agent_title", "Global Super Agent"))
              Text(globalAgentSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIPermissionsAuditView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_permissions_title", "Permissions & Audit"))
              Text(t("cc_recent_operations_subtitle", "Review native tools, Agent actions, and confirmation decisions"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIExecutionPolicyView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_execution_policy_title", "Execution Policy"))
              Text(t("cc_permission_mode_banner_subtitle", "This setting is enforced by the local safety policy before every action."))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAgentCoreView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_agent_core_title", "Agent Core"))
              Text(t("cc_agent_core_subtitle", "Planning, tool use, replanning, and recovery"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: AgentSafetySettingsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.settings.execution_policy", "Execution Policy"))
              Text("\(t(store.agentSafetySettings.taskExecutionMode.displayTitle, store.agentSafetySettings.taskExecutionMode.displayTitle)) / \(t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle))")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIMemoryControlCenterView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_memory_title", "Memory & Personalization"))
              Text(memoryControlSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAgentMemoryView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.agent_memory.title", "Personal Memory"))
              Text(memorySummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASILearningSkillEvolutionView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_learning_title", "Learning & Skill Evolution"))
              Text(t("cc_learning_subtitle", "Learn from successful tasks; generated content requires review"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAgentMemoryTelemetryView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.agent_memory.telemetry_title", "Agent Memory"))
              Text(t("signalasi.agent_memory.telemetry_subtitle", "iOS resident memory sampled across active Agent tasks"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAgentKnowledgeView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.agent_knowledge.title", "Knowledge"))
              Text(knowledgeSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAgentRecentTasksView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.agent_tasks.title", "Tasks"))
              Text(recentTaskSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAutomationView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.automation.title", "Automation"))
              Text(automationSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAgentSessionsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.agent_sessions.title", "Sessions"))
              Text(agentSessionsSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASINativeToolCatalogView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.native_tool_catalog.title", "Native Tools"))
              Text(nativeToolsSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIMcpControlCenterView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("agent_mcp_title", "MCP"))
              Text(mcpSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAppToolsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_app_tools_title", "Apps & Tools"))
              Text(t("cc_apps_subtitle", "Messaging, calendar, browser, files, and adapters"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIPhoneCapabilitiesView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_phone_title", "Phone Capabilities"))
              Text(t("signalasi.phone_capabilities.summary_subtitle", "Native tools, permissions, and iOS capability boundaries"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAppAdaptersView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("agent_app_adapters_title", "Specialized App Adapters"))
              Text(
                String(
                  format: t("signalasi.settings.app_adapters.status", "%d adapters / iOS handoff boundaries"),
                  SignalASIAppAdapterCatalog.adapterCount
                )
              )
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAgentsModelsNodesView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_nodes_title", "Agents, Models & Nodes"))
              Text(t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          if store.agentSafetySettings.executionPaused {
            Label(t("signalasi.settings.execution_paused", "Execution Paused"), systemImage: "pause.circle")
              .foregroundColor(.orange)
          }
        }
        Section(t("signalasi.settings.agent_task_budget", "Agent Task Budget")) {
          NavigationLink(destination: AgentTaskBudgetSettingsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.settings.task_budget", "Task Budget"))
              Text("\(t(store.agentTaskBudget.profile.displayName, store.agentTaskBudget.profile.displayName)) / \(store.agentTaskBudget.localizedCostLimitLabel(language: interfaceLanguage)) / \(t(store.agentTaskBudget.networkPolicy.displayName, store.agentTaskBudget.networkPolicy.displayName))")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.planning", "Planning & Coordination")) {
          NavigationLink(destination: SignalASIResourceRoutingView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_resource_routing_title", "Models & Resource Routing"))
              Text(t("cc_resource_routing_subtitle", "Choose by quality, latency, privacy, cost, and availability"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: AgentModelPlannerSettingsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.discover.model_planner", "Model Planner"))
              Text(modelPlannerSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASILocalModelLabView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.settings.local_model", "Local Model Settings"))
              Text(t("signalasi.settings.local_model.status", "Configure on-device inference"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIOnDeviceRuntimeView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_runtime_title", "On-device Linux Runtime"))
              Text(t("cc_runtime_subtitle", "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIVoiceAssistantSettingsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("voice_settings_title", "Voice Wake & ASR/TTS"))
              Text(voiceSettingsSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.custom_devices", "Custom Devices")) {
          NavigationLink(destination: SignalASISmartSpacesView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_smart_spaces_title", "Smart Spaces"))
              Text(t("cc_spaces_subtitle", "Home Assistant and custom devices"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: CustomDeviceConnectorsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.settings.device_connectors", "Device Connectors"))
              Text(customDeviceSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section("Home Assistant") {
          NavigationLink(destination: HomeAssistantSettingsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.settings.smart_home", "Smart Home"))
              Text(homeAssistantSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.cloud_models", "Cloud Models")) {
          ForEach(store.cloudModelContacts) { contact in
            NavigationLink(destination: SignalASICloudModelSwitchView(contactId: contact.id)) {
              VStack(alignment: .leading) {
                Text(contact.displayName)
                Text(contact.selectedCloudModel?.modelId ?? t("signalasi.settings.no_model", "No model"))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
          Button {
            showingAddModel = true
          } label: {
            Label(t("signalasi.settings.add_model", "Add Model"), systemImage: "plus.circle")
          }
        }
        Section("SignalASI Link") {
          NavigationLink(destination: SignalASISystemStatusView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_system_status_title", "System Status"))
              Text(t("cc_all_services_normal_subtitle", "Local execution, routing, messaging, and security are available"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIProtocolQualityView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("protocol_quality_title", "Protocol & Quality"))
              Text(t("protocol_quality_hero_subtitle", "Secure communication and Agent collaboration protocol"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASILinkDiagnosticsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.settings.link_diagnostics", "Link Diagnostics"))
              Text(linkDiagnosticsSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIAdvancedOptionsView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("settings_advanced_options", "Advanced Options"))
              Text(t("settings_advanced_options_subtitle", "Logs, network, and protocol diagnostics"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.backup", "Backup")) {
          NavigationLink(destination: SignalASIDataBackupView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_data_title", "Data & Backup"))
              Text(t("cc_data_subtitle", "Encrypted export, restore, storage, and cache"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          SecureField(t("signalasi.settings.password", "Password"), text: $backupPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
          Toggle(t("signalasi.settings.include_messages", "Include Messages"), isOn: $backupIncludeMessages)
          HStack {
            Button {
              exportBackup()
            } label: {
              Label(t("signalasi.common.export", "Export"), systemImage: "square.and.arrow.up")
            }
            .disabled(backupPassword.count < SignalASIBackupManager.minimumPasswordLength)
            Spacer()
            Button {
              backupImportPresented = true
            } label: {
              Label(t("signalasi.common.import", "Import"), systemImage: "square.and.arrow.down")
            }
            .disabled(backupPassword.count < SignalASIBackupManager.minimumPasswordLength)
          }
          if !backupStatus.isEmpty {
            Text(backupStatus)
              .foregroundColor(backupStatusIsError ? .red : .secondary)
          }
        }
        Section(t("signalasi.settings.privacy", "Privacy")) {
          NavigationLink(destination: SignalASIPrivacyControlCenterView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("cc_privacy_dashboard_title", "Privacy Dashboard"))
              Text(t("cc_privacy_dashboard_hero_subtitle", "A metadata-only audit of data sent to cloud models and trusted Desktop Agents"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIPrivacyDashboardView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("signalasi.settings.model_data_sharing", "Model Data Sharing"))
              Text(t("signalasi.settings.model_data_sharing.subtitle", "Review metadata-only disclosure events and destination blocks"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: SignalASIResetDataView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("settings_destroy_data", "Reset Data"))
              Text(t("destroy_data_hero_subtitle", "This deletes identity, contacts, chat history, keys, cache, and backup data."))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        Section(t("signalasi.settings.notifications", "Notifications")) {
          Button {
            Task {
              notificationsStatus = await NotificationService.requestAuthorization()
                ? t("signalasi.status.allowed", "Allowed")
                : t("signalasi.status.not_allowed", "Not allowed")
            }
          } label: {
            Label(t("signalasi.settings.enable_notifications", "Enable Notifications"), systemImage: "bell.badge")
          }
          if !notificationsStatus.isEmpty {
            Text(notificationsStatus)
              .foregroundColor(.secondary)
          }
        }
        Section(t("settings_about_section", "About")) {
          NavigationLink(destination: SignalASIAboutView()) {
            VStack(alignment: .leading, spacing: 4) {
              Text(t("settings_about_signalasi", "About SignalASI"))
              Text(String(format: t("settings_about_version_summary", "Version %@ - Signal Link v1.0.3"), appVersionName))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
      }
      .navigationTitle(t("signalasi.tab.settings", "Settings"))
      .sheet(isPresented: $showingAddModel) {
        AddCloudModelView()
      }
      .fileExporter(
        isPresented: $backupExportPresented,
        document: backupDocument,
        contentType: .data,
        defaultFilename: SignalASIBackupManager.defaultFilename()
      ) { result in
        switch result {
        case .success:
          setBackupStatus(t("signalasi.backup.exported", "Backup exported."), isError: false)
        case .failure(let error):
          setBackupStatus(error.localizedDescription, isError: true)
        }
      }
      .fileImporter(
        isPresented: $backupImportPresented,
        allowedContentTypes: [.data],
        allowsMultipleSelection: false
      ) { result in
        do {
          guard let url = try result.get().first else { return }
          importBackup(from: url)
        } catch {
          setBackupStatus(error.localizedDescription, isError: true)
        }
      }
      .onAppear(perform: refreshLinkDiagnostics)
    }
  }

  private func exportBackup() {
    do {
      let password = backupPassword
      let payload = store.exportBackupPayload(includeContacts: true, includeMessages: backupIncludeMessages)
      setBackupStatus(t("signalasi.backup.preparing", "Preparing backup..."), isError: false)
      Task {
        do {
          let data = try await Task.detached {
            try SignalASIBackupManager.encryptPayload(payload, password: password)
          }.value
          await MainActor.run {
            backupDocument = SignalASIBackupDocument(data: data)
            backupExportPresented = true
            setBackupStatus(t("signalasi.backup.ready", "Backup ready."), isError: false)
          }
        } catch {
          await MainActor.run {
            setBackupStatus(error.localizedDescription, isError: true)
          }
        }
      }
    }
  }

  private func importBackup(from url: URL) {
    let password = backupPassword
    let includeMessages = backupIncludeMessages
    setBackupStatus(t("signalasi.backup.restoring", "Restoring backup..."), isError: false)
    Task {
      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      do {
        let data = try Data(contentsOf: url)
        let payload = try await Task.detached {
          try SignalASIBackupManager.importBackup(data: data, password: password)
        }.value
        try await MainActor.run {
          try store.restoreBackupPayload(payload, includeMessages: includeMessages)
          setBackupStatus(t("signalasi.backup.restored", "Backup restored."), isError: false)
        }
      } catch {
        await MainActor.run {
          setBackupStatus(error.localizedDescription, isError: true)
        }
      }
    }
  }

  private func setBackupStatus(_ value: String, isError: Bool) {
    backupStatus = value
    backupStatusIsError = isError
  }

  private func languageBinding(_ keyPath: WritableKeyPath<LanguagePolicySettings, String>) -> Binding<String> {
    Binding(
      get: { store.languagePolicy[keyPath: keyPath] },
      set: { value in store.updateLanguagePolicy { $0[keyPath: keyPath] = value } }
    )
  }

  private var modelPlannerSummary: String {
    let settings = store.modelPlannerSettings
    guard settings.enabled else { return t("signalasi.settings.local_planner", "Local deterministic planner") }
    return String(
      format: t("signalasi.settings.model_planner.summary", "Model planning / %d actions / %d replans"),
      settings.maxActions,
      settings.maxReplans
    )
  }

  private var voiceSettingsSummary: String {
    let enabled = store.voiceSettings.wakeListeningEnabled ? t("common_on", "On") : t("common_off", "Off")
    let model = VoiceWhisperModelCatalog.model(store.voiceSettings.asrModelId).displayName
    return "\(enabled) / \(model) / \(store.voiceSettings.preferredLocaleIdentifier)"
  }

  private var customDeviceSummary: String {
    let total = store.customDeviceConnectors.count
    guard total > 0 else { return t("signalasi.settings.no_custom_devices", "No custom devices") }
    let enabled = store.customDeviceConnectors.filter(\.enabled).count
    return String(format: t("signalasi.settings.custom_device.summary", "%d configured / %d enabled"), total, enabled)
  }

  private var homeAssistantSummary: String {
    let settings = store.homeAssistantSettings
    if settings.configured { return t("signalasi.settings.configured_enabled", "Configured and enabled") }
    if settings.credentialsConfigured { return t("signalasi.settings.configured_disabled", "Configured, disabled") }
    return t("signalasi.settings.not_configured", "Not configured")
  }

  private var textScaleSummary: String {
    let mode = store.displaySettings.textScale
    return "\(textScaleLabel(mode)) / \(textScaleDescription(mode))"
  }

  private func textScaleLabel(_ mode: AppTextScaleMode) -> String {
    switch mode {
    case .system:
      return t("cc_text_size_system", "Follow system")
    case .standard:
      return t("cc_text_size_standard", "Standard")
    case .comfortable:
      return t("cc_text_size_comfortable", "Comfortable")
    case .large:
      return t("cc_text_size_large", "Large")
    case .extraLarge:
      return t("cc_text_size_extra_large", "Extra large")
    }
  }

  private func textScaleDescription(_ mode: AppTextScaleMode) -> String {
    switch mode {
    case .system:
      return t("cc_text_size_system_subtitle", "Use the iOS text-size preference")
    case .standard:
      return t("cc_text_size_standard_subtitle", "100% - More content on screen")
    case .comfortable:
      return t("cc_text_size_comfortable_subtitle", "110% - Recommended")
    case .large:
      return t("cc_text_size_large_subtitle", "120% - Easier to read")
    case .extraLarge:
      return t("cc_text_size_extra_large_subtitle", "132% - Maximum readability")
    }
  }

  private var languagePolicySummary: String {
    let interface = interfaceLanguageDisplayName(store.languagePolicy.interfaceLanguage)
    let response = voiceLanguageDisplayName(store.languagePolicy.responseLanguage)
    let asrLocale = store.voiceSettings.preferredLocaleIdentifier
    return String(
      format: t("signalasi.language_policy.settings_summary", "%@ / Reply %@ / ASR %@"),
      interface,
      response,
      asrLocale
    )
  }

  private var memorySummary: String {
    let snapshot = store.agentMemorySnapshot()
    return String(
      format: t("signalasi.agent_memory.value", "Memory: %d / conflicts: %d"),
      snapshot.activeCount,
      snapshot.conflicts.count
    )
  }

  private var memoryControlSummary: String {
    let snapshot = store.agentMemorySnapshot()
    return String(
      format: t("cc_memory_subtitle", "%d long-term memories / user controlled"),
      snapshot.activeCount
    )
  }

  private var knowledgeSummary: String {
    let stats = store.agentKnowledgeStats
    return String(
      format: t("signalasi.agent_knowledge.value", "Knowledge: %d items / %d sources / %d hits"),
      stats.itemCount,
      stats.sourceCount,
      store.agentKnowledgeAccessAudit.count
    )
  }

  private var globalAgentSummary: String {
    let settings = store.globalAgentSettings
    let status = settings.enabled
      ? t("cc_global_understanding_active", "Global understanding active")
      : t("signalasi.status.paused", "Paused")
    let cognition = settings.allowCloudCognition
      ? t("cc_global_cloud_allowed", "Cloud cognition")
      : t("cc_global_local_first", "Local first")
    return "\(status) / \(cognition) / \(settings.dailyBackgroundModelCallBudget) calls"
  }

  private var recentTaskSummary: String {
    let tasks = store.recentAgentTasks(limit: 200)
    let running = tasks.filter {
      [.observing, .planning, .executing, .verifying, .waitingConfirmation, .waitingResponse, .paused].contains($0.phase)
    }.count
    return String(
      format: t("signalasi.agent_tasks.value", "Tasks: %d / running: %d"),
      tasks.count,
      running
    )
  }

  private var automationSummary: String {
    let tasks = store.automationTasks()
    let enabled = tasks.filter(\.enabled).count
    return String(
      format: t("signalasi.automation.value", "Tasks: %d / enabled: %d"),
      tasks.count,
      enabled
    )
  }

  private var agentSessionsSummary: String {
    let sessions = store.agentSessions(includeArchived: true)
    let archived = sessions.filter { $0.status == .archived }.count
    return String(
      format: t("signalasi.agent_sessions.value", "Sessions: %d / archived: %d"),
      sessions.count,
      archived
    )
  }

  private var nativeToolsSummary: String {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return String(
      format: t("signalasi.native_tool_catalog.value", "Tools: %d / available: %d"),
      tools.count,
      available
    )
  }

  private var mcpSummary: String {
    let connections = AgentMcpRegistry(FileAgentMcpStore(rootURL: FileAgentMcpStore.defaultRootURL())).list()
    let ready = connections.filter {
      $0.isCallable(nowMillis: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
    }.count
    let recommended = AgentDefaultCapabilityCatalog.mcpEntries.count
    return String(
      format: t("signalasi.mcp.summary", "%d installed / %d ready / %d recommended"),
      connections.count,
      ready,
      recommended
    )
  }

  private var appVersionName: String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
      return "0.1.0"
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "0.1.0" : trimmed
  }

  private var linkDiagnosticsSummary: String {
    let snapshot = linkDiagnosticsSnapshot
    if snapshot.totalEvents == 0 {
      return t("signalasi.settings.link_stable", "Stable / 0 events")
    }
    return String(
      format: t("signalasi.settings.link.summary", "%d events / %d replay / %d failures"),
      snapshot.totalEvents,
      snapshot.replayCount,
      snapshot.failureCount
    )
  }

  private func refreshLinkDiagnostics() {
    linkDiagnosticsSnapshot = SignalASILinkTransportDiagnostics.snapshot()
  }

  private func interfaceLanguageDisplayName(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeInterface(value) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.en:
      return t("signalasi.language.en", "English")
    default:
      let resolved = LanguagePolicySettings.resolveInterface(LanguagePolicySettings.auto)
      let resolvedName = resolved == LanguagePolicySettings.zhCN
        ? t("signalasi.language.zh_cn", "Simplified Chinese")
        : t("signalasi.language.en", "English")
      return String(format: t("signalasi.language.auto_format", "Automatic (%@)"), resolvedName)
    }
  }

  private func voiceLanguageDisplayName(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("signalasi.language.en_us", "English (United States)")
    case LanguagePolicySettings.zhHK:
      return t("signalasi.language.zh_hk", "Traditional Chinese (Hong Kong)")
    case LanguagePolicySettings.zhTW:
      return t("signalasi.language.zh_tw", "Traditional Chinese (Taiwan)")
    default:
      return t("signalasi.language.auto", "Automatic")
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
      Section("Task Execution") {
        Picker("Task execution", selection: taskExecutionModeBinding) {
          ForEach(AgentTaskExecutionMode.allCases) { mode in
            Text(t(mode.displayTitle, mode.displayTitle)).tag(mode)
          }
        }
        Text(t(store.agentSafetySettings.taskExecutionMode.detail, store.agentSafetySettings.taskExecutionMode.detail))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Section("Action Permissions") {
        Picker("Execution Mode", selection: permissionModeBinding) {
          ForEach(AgentPermissionMode.allCases) { mode in
            Text(t(mode.displayTitle, mode.displayTitle)).tag(mode)
          }
        }
        Text(t(store.agentSafetySettings.permissionMode.detail, store.agentSafetySettings.permissionMode.detail))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Section("Safety Guards") {
        Toggle("High Risk Guard", isOn: boolBinding(\.highRiskGuard))
        Toggle("Memory Capture", isOn: boolBinding(\.memoryCapture))
        Toggle("Pause Execution", isOn: boolBinding(\.executionPaused))
      }
      Section("Allowed Action Surfaces") {
        Toggle("Screen Observation", isOn: boolBinding(\.screenObservationAllowed))
        Toggle("Local Actions", isOn: boolBinding(\.localActionsAllowed))
        Toggle("Connector Calls", isOn: boolBinding(\.connectorCallsAllowed))
        Toggle("Device Control", isOn: boolBinding(\.deviceControlAllowed))
      }
    }
    .navigationTitle(t("Agent Safety", "Agent Safety"))
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

struct CustomDeviceConnectorsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  var body: some View {
    Form {
      Section("Devices") {
        if store.customDeviceConnectors.isEmpty {
          Text("No custom devices")
            .foregroundColor(.secondary)
        }
        ForEach(store.customDeviceConnectors) { connector in
          NavigationLink(destination: CustomDeviceConnectorEditorView(connector: connector)) {
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(connector.name)
                Spacer()
                if connector.configured {
                  Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                }
              }
              Text("\(t(connector.transport.displayName, connector.transport.displayName)) / \(t(connector.risk.displayName, connector.risk.displayName))")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        .onDelete { offsets in
          let ids = offsets.map { store.customDeviceConnectors[$0].id }
          for id in ids {
            store.deleteCustomDeviceConnector(id: id)
          }
        }
      }
      Section {
        NavigationLink(destination: CustomDeviceConnectorEditorView(connector: CustomDeviceConnector())) {
          Label("Add Custom Device", systemImage: "plus.circle")
        }
      }
    }
    .navigationTitle(t("Custom Devices", "Custom Devices"))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct CustomDeviceConnectorEditorView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @Environment(\.dismiss) private var dismiss
  @State private var draft: CustomDeviceConnector
  private let originalId: String

  init(connector: CustomDeviceConnector) {
    _draft = State(initialValue: connector)
    originalId = connector.id
  }

  var body: some View {
    Form {
      Section("Connection") {
        TextField("Name", text: stringBinding(\.name))
        Picker("Transport", selection: transportBinding) {
          ForEach(CustomDeviceTransport.allCases) { transport in
            Text(t(transport.displayName, transport.displayName)).tag(transport)
          }
        }
        TextField("Endpoint", text: stringBinding(\.endpoint))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        TextField("Command Target", text: stringBinding(\.commandTarget))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
      }
      Section("Authentication") {
        TextField("Username", text: stringBinding(\.username))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        SecureField("Auth Token", text: stringBinding(\.authToken))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        if !draft.maskedAuthToken.isEmpty {
          Text(String(format: t("Stored token: %@", "Stored token: %@"), draft.maskedAuthToken))
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      Section("Safety") {
        Picker("Risk", selection: riskBinding) {
          ForEach(CustomDeviceRisk.allCases) { risk in
            Text(t(risk.displayName, risk.displayName)).tag(risk)
          }
        }
        Toggle("Enabled", isOn: boolBinding(\.enabled))
      }
      Section("Status") {
        if draft.configured {
          Label("Configured", systemImage: "checkmark.circle")
            .foregroundColor(.green)
        } else {
          Label("Name and endpoint are required", systemImage: "exclamationmark.triangle")
            .foregroundColor(.orange)
        }
      }
      Section {
        Button {
          store.upsertCustomDeviceConnector(draft)
          dismiss()
        } label: {
          Label("Save", systemImage: "checkmark.circle")
        }
        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
          draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        if store.customDeviceConnectors.contains(where: { $0.id == originalId }) {
          Button(role: .destructive) {
            store.deleteCustomDeviceConnector(id: originalId)
            dismiss()
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }
    .navigationTitle(t("Custom Device", "Custom Device"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var transportBinding: Binding<CustomDeviceTransport> {
    Binding(
      get: { draft.transport },
      set: { draft.transport = $0 }
    )
  }

  private var riskBinding: Binding<CustomDeviceRisk> {
    Binding(
      get: { draft.risk },
      set: { draft.risk = $0 }
    )
  }

  private func boolBinding(_ keyPath: WritableKeyPath<CustomDeviceConnector, Bool>) -> Binding<Bool> {
    Binding(
      get: { draft[keyPath: keyPath] },
      set: { draft[keyPath: keyPath] = $0 }
    )
  }

  private func stringBinding(_ keyPath: WritableKeyPath<CustomDeviceConnector, String>) -> Binding<String> {
    Binding(
      get: { draft[keyPath: keyPath] },
      set: { draft[keyPath: keyPath] = $0 }
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct HomeAssistantSettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  var body: some View {
    Form {
      Section("Connection") {
        Toggle("Enable Home Assistant", isOn: boolBinding(\.enabled))
        TextField("Server URL", text: stringBinding(\.baseUrl))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .keyboardType(.URL)
        SecureField("Access Token", text: stringBinding(\.accessToken))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        if !store.homeAssistantSettings.maskedAccessToken.isEmpty {
          Text(String(format: t("Stored token: %@", "Stored token: %@"), store.homeAssistantSettings.maskedAccessToken))
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      Section("Default Target") {
        TextField("Default Entity", text: stringBinding(\.defaultEntityId))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        Text("Example: light.living_room")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Section("Status") {
        if store.homeAssistantSettings.configured {
          Label("Configured", systemImage: "checkmark.circle")
            .foregroundColor(.green)
        } else if store.homeAssistantSettings.credentialsConfigured {
          Label("Configured, disabled", systemImage: "pause.circle")
            .foregroundColor(.orange)
        } else {
          Label("Not configured", systemImage: "exclamationmark.triangle")
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(t("Home Assistant", "Home Assistant"))
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
        Section("Reset") {
          Text("This clears your identity, contacts, chats, pairing links, voice settings, agent safety settings, task budget, custom device connectors, Home Assistant configuration, model planner settings, and saved model keys on this device.")
            .foregroundColor(.secondary)
          TextField("RESET", text: $confirmation)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled(true)
          Button(role: .destructive) {
            onReset()
            dismiss()
          } label: {
            Label("Reset Private Data", systemImage: "trash")
          }
          .disabled(confirmation != "RESET")
        }
      }
      .navigationTitle(t("Reset", "Reset"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
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
        Section("Provider") {
          Text(contact.displayName)
          Text(contact.cloudProvider.ifBlank(contact.id))
            .font(.caption)
            .foregroundColor(.secondary)
          if let selected = contact.selectedCloudModel {
            Label(String(format: t("Selected: %@", "Selected: %@"), selected.modelId), systemImage: "checkmark.circle")
          }
        }
        Section("Selected Model") {
          Picker("Model", selection: selectedModelBinding(contact)) {
            ForEach(contact.cloudModels) { model in
              Text(model.displayName).tag(model.modelId)
            }
          }
        }
        Section("Models") {
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
          Label("Add Model", systemImage: "plus.circle")
        }
      } else {
        Section("Provider") {
          Text("Cloud model contact not found.")
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(contact?.displayName ?? t("Cloud Model", "Cloud Model"))
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
    return Label(ready ? t("Ready", "Ready") : t("Needs Setup", "Needs Setup"), systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.triangle")
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
        Picker("Preset", selection: $selectedPreset) {
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
        TextField("Provider", text: $provider)
        TextField("Display Name", text: $displayName)
        TextField("Model ID", text: $modelId)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        TextField("Endpoint", text: $endpoint)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        Picker("API Style", selection: $apiStyle) {
          ForEach(SignalASICloudAPIStyle.allCases) { style in
            Text(style.rawValue).tag(style)
          }
        }
        SecureField("API Key", text: $apiKey)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        if !errorText.isEmpty {
          Text(errorText)
            .foregroundColor(.red)
        }
      }
      .navigationTitle(t("Add Model", "Add Model"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
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

struct AvatarView: View {
  var contact: SignalASIContact
  var size: CGFloat = 42

  var body: some View {
    ZStack {
      if let assetName {
        Image(assetName)
          .resizable()
          .scaledToFill()
      } else {
        Circle()
          .fill(color)
        Image(systemName: iconName)
          .foregroundColor(.white)
          .font(.system(size: max(14, size * 0.43), weight: .semibold))
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }

  private var assetName: String? {
    let identity = [
      contact.id,
      contact.signalASIId,
      contact.name,
      contact.displayName,
      contact.type
    ]
      .joined(separator: " ")
      .lowercased()
    if identity.contains("hermes") {
      return "HermesLogo"
    }
    if contact.deliveryMode == .link || identity.contains("signalasi") {
      return "SignalASILogo"
    }
    return nil
  }

  private var iconName: String {
    switch contact.deliveryMode {
    case .cloudAPI: return "cloud"
    case .link: return "desktopcomputer"
    case .local: return "gearshape"
    }
  }

  private var color: Color {
    switch contact.deliveryMode {
    case .cloudAPI: return .purple
    case .link: return .green
    case .local: return .gray
    }
  }
}

struct FriendRequestRow: View {
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
      Text(request.status.rawValue)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.signalASISurface)
  }
}

struct MyContactQRCodeView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @State private var copied = false
  @State private var qrText = ""

  var body: some View {
    NavigationView {
      Form {
        Section("QR") {
          HStack {
            Spacer()
            if let image = SignalASIQRCodeImageRenderer.image(from: qrText) {
              Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding(.vertical, 8)
            }
            Spacer()
          }
        }
        Section(t("signalasi.contact.section_identity", "Identity")) {
          Text(store.profile.signalASIId)
            .font(.system(.caption, design: .monospaced))
          Text(store.profile.identityFingerprint.chunkedFingerprint)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
        }
        Section(t("signalasi.contact.payload", "Payload")) {
          Text(qrText)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(6)
          Button {
            UIPasteboard.general.string = qrText
            copied = true
          } label: {
            Label(
              copied
                ? t("signalasi.common.copied", "Copied")
                : t("signalasi.contact.copy_payload", "Copy Payload"),
              systemImage: "doc.on.doc"
            )
          }
        }
      }
      .navigationTitle(t("signalasi.contact.my_qr_title", "My QR"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("signalasi.common.done", "Done")) { dismiss() }
        }
      }
      .onAppear {
        if qrText.isEmpty {
          qrText = (try? store.myContactQRText()) ?? "{}"
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

enum SignalASIQRCodeImageRenderer {
  static func image(from text: String) -> UIImage? {
    let data = Data(text.utf8)
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { return nil }
    return UIImage(ciImage: output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)))
  }
}

struct QRCodeScannerView: UIViewControllerRepresentable {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var onCode: (String) -> Void
  var onError: (String) -> Void = { _ in }

  init(
    onCode: @escaping (String) -> Void,
    onError: @escaping (String) -> Void = { _ in }
  ) {
    self.onCode = onCode
    self.onError = onError
  }

  func makeUIViewController(context: Context) -> QRScannerViewController {
    QRScannerViewController(
      onCode: onCode,
      onError: onError,
      messages: QRScannerMessages(
        cameraAccessRequired: t(
          "signalasi.scanner.camera_access_required",
          "Camera access is required to scan SignalASI QR codes."
        ),
        cameraUnavailable: t(
          "signalasi.scanner.camera_unavailable",
          "Camera is unavailable on this device."
        ),
        outputUnavailable: t(
          "signalasi.scanner.output_unavailable",
          "QR scanner output is unavailable."
        ),
        accessUnavailable: t(
          "signalasi.scanner.access_unavailable",
          "Camera access is unavailable on this device."
        )
      )
    )
  }

  func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

fileprivate struct QRScannerMessages {
  var cameraAccessRequired: String
  var cameraUnavailable: String
  var outputUnavailable: String
  var accessUnavailable: String
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let onCode: (String) -> Void
  private let onError: (String) -> Void
  private let messages: QRScannerMessages
  private let session = AVCaptureSession()
  private var configured = false

  fileprivate init(
    onCode: @escaping (String) -> Void,
    onError: @escaping (String) -> Void,
    messages: QRScannerMessages
  ) {
    self.onCode = onCode
    self.onError = onError
    self.messages = messages
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    prepareCamera()
  }

  private func prepareCamera() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
        DispatchQueue.main.async {
          guard let self else { return }
          if allowed {
            self.configureSession()
          } else {
            self.reportScannerError(self.messages.cameraAccessRequired)
          }
        }
      }
    case .denied, .restricted:
      reportScannerError(messages.cameraAccessRequired)
    @unknown default:
      reportScannerError(messages.accessUnavailable)
    }
  }

  private func configureSession() {
    guard !configured else { return }
    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      reportScannerError(messages.cameraUnavailable)
      return
    }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      reportScannerError(messages.outputUnavailable)
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    output.metadataObjectTypes = [.qr]
    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.bounds
    view.layer.addSublayer(preview)
    configured = true
    session.startRunning()
  }

  private func reportScannerError(_ message: String) {
    onError(message)
    let label = UILabel()
    label.text = message
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach {
      $0.frame = view.bounds
    }
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          let value = readable.stringValue else {
      return
    }
    session.stopRunning()
    onCode(value)
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
