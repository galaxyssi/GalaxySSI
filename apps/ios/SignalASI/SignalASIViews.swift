import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
        .onAppear { coordinator.start() }
    }
  }
}

struct RootView: View {
  var body: some View {
    TabView {
      ChatListView()
        .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
      ContactsView()
        .tabItem { Label("Contacts", systemImage: "person.2") }
      PairingView()
        .tabItem { Label("Pairing", systemImage: "qrcode.viewfinder") }
      VoiceSettingsView()
        .tabItem { Label("Voice", systemImage: "mic") }
      SettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
    }
  }
}

struct ChatListView: View {
  @EnvironmentObject private var store: SignalASIStore

  var body: some View {
    NavigationView {
      List(store.visibleContacts) { contact in
        NavigationLink(destination: ConversationView(contactId: contact.id)) {
          ContactRow(contact: contact, latestMessage: store.messages(for: contact.id).last)
        }
      }
      .navigationTitle("SignalASI")
    }
  }
}

struct ContactRow: View {
  var contact: SignalASIContact
  var latestMessage: ChatMessage?

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(contact: contact)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(contact.displayName)
            .font(.headline)
          Spacer()
          if let latestMessage {
            Text(latestMessage.createdAt, style: .time)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        Text(latestMessage?.content ?? contact.setupDetail)
          .lineLimit(1)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

struct ConversationView: View {
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var draft = ""
  @State private var attachments: [SignalASIDraftAttachment] = []
  @State private var fileImporterPresented = false
  @State private var photoPickerPresented = false
  @State private var attachmentError = ""
  var contactId: String

  private var contact: SignalASIContact {
    store.contact(id: contactId) ?? SignalASIContact.hermes()
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 10) {
            ForEach(store.messages(for: contact.id)) { message in
              MessageBubble(message: message)
                .id(message.id)
            }
          }
          .padding()
        }
        .onChange(of: store.messages(for: contact.id).count) { _ in
          if let last = store.messages(for: contact.id).last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
          }
        }
      }
      Divider()
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
        HStack(spacing: 10) {
          Button {
            fileImporterPresented = true
          } label: {
            Image(systemName: "paperclip")
              .font(.system(size: 22))
          }
          Button {
            photoPickerPresented = true
          } label: {
            Image(systemName: "photo")
              .font(.system(size: 22))
          }
          TextField("Message", text: $draft)
            .textFieldStyle(.roundedBorder)
          Button {
            let text = draft
            let outgoingAttachments = attachments
            draft = ""
            attachments.removeAll()
            attachmentError = ""
            Task { await coordinator.send(text, to: contact, attachments: outgoingAttachments) }
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.system(size: 30))
          }
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
        }
      }
      .padding()
    }
    .navigationTitle(contact.displayName)
    .navigationBarTitleDisplayMode(.inline)
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
      attachmentError = "Attachment limit reached or file is too large."
      return
    }
    attachments.append(attachment)
    attachmentError = ""
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
          .background(message.isSystem ? Color.secondary.opacity(0.12) : (message.isMine ? Color.blue.opacity(0.18) : Color(.secondarySystemBackground)))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        HStack(spacing: 4) {
          Text(message.createdAt, style: .time)
          if message.isMine {
            Text(message.deliveryStatus.rawValue)
          }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
      }
      if !message.isMine { Spacer(minLength: 48) }
    }
  }
}

struct ContactsView: View {
  @EnvironmentObject private var store: SignalASIStore
  @State private var myQRCodePresented = false
  @State private var contactScannerPresented = false
  @State private var contactImportStatus = ""
  @State private var contactImportIsError = false

  var body: some View {
    NavigationView {
      List {
        if !store.pendingFriendRequests.isEmpty {
          Section("New Friends") {
            ForEach(store.pendingFriendRequests) { request in
              NavigationLink(destination: FriendRequestDetailView(requestId: request.id)) {
                FriendRequestRow(request: request)
              }
            }
          }
        }
        Section("Contacts") {
          ForEach(store.contacts.filter { !$0.deleted && $0.id != "system" }) { contact in
            NavigationLink(destination: ContactDetailView(contactId: contact.id)) {
              ContactRow(contact: contact, latestMessage: store.messages(for: contact.id).last)
            }
          }
        }
        if !contactImportStatus.isEmpty {
          Section("Status") {
            Text(contactImportStatus)
              .foregroundColor(contactImportIsError ? .red : .secondary)
          }
        }
      }
      .navigationTitle("Contacts")
      .toolbar {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
          Button {
            myQRCodePresented = true
          } label: {
            Image(systemName: "qrcode")
          }
          Button {
            contactScannerPresented = true
          } label: {
            Image(systemName: "qrcode.viewfinder")
          }
        }
      }
      .sheet(isPresented: $myQRCodePresented) {
        MyContactQRCodeView()
      }
      .sheet(isPresented: $contactScannerPresented) {
        QRCodeScannerView { value in
          contactScannerPresented = false
          importContactQR(value)
        }
      }
    }
  }

  private func importContactQR(_ value: String) {
    do {
      let request = try store.importContactQRCodeAsFriendRequest(value)
      contactImportStatus = "Friend request added for \(request.name)."
      contactImportIsError = false
    } catch {
      contactImportStatus = error.localizedDescription
      contactImportIsError = true
    }
  }
}

struct ContactDetailView: View {
  @EnvironmentObject private var store: SignalASIStore
  @Environment(\.dismiss) private var dismiss
  @State private var remarkName = ""
  @State private var deleteMessagesWhenDeleting = false
  @State private var showingDeleteConfirmation = false
  @State private var statusText = ""
  var contactId: String

  private var contact: SignalASIContact? {
    store.contact(id: contactId)
  }

  var body: some View {
    Form {
      if let contact {
        Section("Contact") {
          HStack(spacing: 12) {
            AvatarView(contact: contact)
            VStack(alignment: .leading, spacing: 4) {
              Text(contact.displayName)
                .font(.headline)
              Text(contact.setupDetail)
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
          }
          NavigationLink(destination: ConversationView(contactId: contact.id)) {
            Label("Open Chat", systemImage: "bubble.left.and.bubble.right")
          }
        }
        Section("Remark") {
          TextField("Display Name", text: $remarkName)
          Button {
            saveRemark()
          } label: {
            Label("Save", systemImage: "checkmark")
          }
          .disabled(remarkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || remarkName == contact.displayName)
          if !statusText.isEmpty {
            Text(statusText)
              .foregroundColor(.secondary)
          }
        }
        Section("Identity") {
          detailRow("SignalASI ID", contact.signalASIId)
          detailRow("Fingerprint", contact.identityFingerprint.ifBlank("Unavailable"))
        }
        if hasRouteDetails(contact) {
          Section("Route") {
            if let mqttTopic = contact.mqttTopic, !mqttTopic.isEmpty {
              detailRow("Topic", mqttTopic)
            }
            if let mqttInboxTopic = contact.mqttInboxTopic, !mqttInboxTopic.isEmpty {
              detailRow("Inbox", mqttInboxTopic)
            }
            if let signalBundleRef = contact.signalBundleRef, !signalBundleRef.isEmpty {
              detailRow("Bundle", signalBundleRef)
            }
          }
        }
        if contact.deliveryMode == .cloudAPI {
          Section("Cloud Model") {
            ForEach(contact.cloudModels) { model in
              HStack {
                VStack(alignment: .leading) {
                  Text(model.displayName)
                  Text(model.modelId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                if model.modelId == contact.selectedCloudModelId {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                }
              }
            }
          }
        }
        Section("Manage") {
          Button(role: .destructive) {
            store.deleteMessages(for: contact.id)
            statusText = "Chat history deleted."
          } label: {
            Label("Delete Chat History", systemImage: "trash")
          }
          Toggle("Also Delete Chat History", isOn: $deleteMessagesWhenDeleting)
          Button(role: .destructive) {
            showingDeleteConfirmation = true
          } label: {
            Label("Delete Contact", systemImage: "person.crop.circle.badge.xmark")
          }
        }
      } else {
        Section("Contact") {
          Text("Contact not found.")
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle(contact?.displayName ?? "Contact")
    .onAppear(perform: syncRemarkName)
    .onChange(of: contact?.displayName ?? "") { _ in
      syncRemarkName()
    }
    .alert("Delete Contact?", isPresented: $showingDeleteConfirmation) {
      Button("Delete", role: .destructive) {
        deleteContact()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(deleteMessagesWhenDeleting ? "The contact and chat history will be removed from this device." : "The contact will be removed from this device.")
    }
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

  private func hasRouteDetails(_ contact: SignalASIContact) -> Bool {
    [contact.mqttTopic, contact.mqttInboxTopic, contact.signalBundleRef].contains { value in
      !(value ?? "").isEmpty
    }
  }

  private func syncRemarkName() {
    remarkName = contact?.displayName ?? ""
  }

  private func saveRemark() {
    if store.renameContact(id: contactId, displayName: remarkName) {
      statusText = "Contact updated."
    }
  }

  private func deleteContact() {
    guard let contact else { return }
    if store.deleteContact(id: contact.id, deleteMessages: deleteMessagesWhenDeleting) {
      dismiss()
    }
  }
}

struct PairingView: View {
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var qrText = ""
  @State private var errorText = ""
  @State private var scannerPresented = false

  var body: some View {
    NavigationView {
      Form {
        Section("Desktop") {
          ForEach(store.serverLinks) { link in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text(link.desktopName)
                Spacer()
                Text(link.paired ? "Paired" : "Pending")
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
        Section("QR") {
          TextEditor(text: $qrText)
            .frame(minHeight: 120)
            .font(.system(.caption, design: .monospaced))
          HStack {
            Button {
              scannerPresented = true
            } label: {
              Label("Scan", systemImage: "qrcode.viewfinder")
            }
            Spacer()
            Button {
              Task { await submitPairing() }
            } label: {
              Label("Pair", systemImage: "checkmark.shield")
            }
            .disabled(qrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        if !coordinator.pairingStatus.isEmpty || !errorText.isEmpty {
          Section("Status") {
            Text(errorText.ifBlank(coordinator.pairingStatus))
              .foregroundColor(errorText.isEmpty ? .secondary : .red)
          }
        }
      }
      .navigationTitle("Pairing")
      .sheet(isPresented: $scannerPresented) {
        QRCodeScannerView { value in
          qrText = value
          scannerPresented = false
          Task { await submitPairing() }
        }
      }
    }
  }

  private func submitPairing() async {
    do {
      errorText = ""
      try await coordinator.pair(using: qrText)
    } catch {
      errorText = error.localizedDescription
    }
  }
}

struct VoiceSettingsView: View {
  @EnvironmentObject private var store: SignalASIStore
  @StateObject private var speech = SpeechCaptureService()
  @State private var permissionStatus = ""

  var body: some View {
    NavigationView {
      Form {
        Section("Voice") {
          Toggle("Wake phrase", isOn: binding(\.wakeListeningEnabled))
          Toggle("Speech recognition", isOn: binding(\.speechRecognitionEnabled))
          Toggle("Text to speech", isOn: binding(\.textToSpeechEnabled))
          Toggle("Auto-send transcripts", isOn: binding(\.autoSendTranscripts))
          TextField("Locale", text: Binding(
            get: { store.voiceSettings.preferredLocaleIdentifier },
            set: { value in store.updateVoiceSettings { $0.preferredLocaleIdentifier = value } }
          ))
        }
        Section("Recorder") {
          if speech.isRecording {
            Text(speech.transcript.ifBlank("Listening..."))
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
      .navigationTitle("Voice")
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
    permissionStatus = granted ? "" : "Microphone or speech permission is missing."
    guard granted else { return }
    do {
      try speech.start(localeIdentifier: store.voiceSettings.preferredLocaleIdentifier)
    } catch {
      permissionStatus = error.localizedDescription
    }
  }
}

struct SettingsView: View {
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
  @State private var showingResetPrivateData = false
  @State private var privacyStatus = ""

  var body: some View {
    NavigationView {
      Form {
        Section("Profile") {
          TextField("Name", text: Binding(
            get: { store.profile.name },
            set: { store.updateProfileName($0) }
          ))
          Text(store.profile.signalASIId)
            .font(.system(.caption, design: .monospaced))
          Text(store.profile.identityFingerprint.chunkedFingerprint)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
        }
        Section("Cloud Models") {
          ForEach(store.cloudModelContacts) { contact in
            NavigationLink(destination: CloudModelProviderDetailView(contactId: contact.id)) {
              VStack(alignment: .leading) {
                Text(contact.displayName)
                Text(contact.selectedCloudModel?.modelId ?? "No model")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
          Button {
            showingAddModel = true
          } label: {
            Label("Add Model", systemImage: "plus.circle")
          }
        }
        Section("Backup") {
          SecureField("Password", text: $backupPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
          Toggle("Include Messages", isOn: $backupIncludeMessages)
          HStack {
            Button {
              exportBackup()
            } label: {
              Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(backupPassword.count < SignalASIBackupManager.minimumPasswordLength)
            Spacer()
            Button {
              backupImportPresented = true
            } label: {
              Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(backupPassword.count < SignalASIBackupManager.minimumPasswordLength)
          }
          if !backupStatus.isEmpty {
            Text(backupStatus)
              .foregroundColor(backupStatusIsError ? .red : .secondary)
          }
        }
        Section("Privacy") {
          Button(role: .destructive) {
            showingResetPrivateData = true
          } label: {
            Label("Reset Private Data", systemImage: "trash")
          }
          if !privacyStatus.isEmpty {
            Text(privacyStatus)
              .foregroundColor(.secondary)
          }
        }
        Section("Notifications") {
          Button {
            Task {
              notificationsStatus = await NotificationService.requestAuthorization() ? "Allowed" : "Not allowed"
            }
          } label: {
            Label("Enable Notifications", systemImage: "bell.badge")
          }
          if !notificationsStatus.isEmpty {
            Text(notificationsStatus)
              .foregroundColor(.secondary)
          }
        }
      }
      .navigationTitle("Settings")
      .sheet(isPresented: $showingAddModel) {
        AddCloudModelView()
      }
      .sheet(isPresented: $showingResetPrivateData) {
        ResetPrivateDataView {
          store.destroyAllPrivateData()
          privacyStatus = "Private data reset."
        }
      }
      .fileExporter(
        isPresented: $backupExportPresented,
        document: backupDocument,
        contentType: .data,
        defaultFilename: SignalASIBackupManager.defaultFilename()
      ) { result in
        switch result {
        case .success:
          setBackupStatus("Backup exported.", isError: false)
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
    }
  }

  private func exportBackup() {
    do {
      let password = backupPassword
      let payload = store.exportBackupPayload(includeContacts: true, includeMessages: backupIncludeMessages)
      setBackupStatus("Preparing backup...", isError: false)
      Task {
        do {
          let data = try await Task.detached {
            try SignalASIBackupManager.encryptPayload(payload, password: password)
          }.value
          await MainActor.run {
            backupDocument = SignalASIBackupDocument(data: data)
            backupExportPresented = true
            setBackupStatus("Backup ready.", isError: false)
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
    setBackupStatus("Restoring backup...", isError: false)
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
          setBackupStatus("Backup restored.", isError: false)
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
}

struct ResetPrivateDataView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var confirmation = ""
  var onReset: () -> Void

  var body: some View {
    NavigationView {
      Form {
        Section("Reset") {
          Text("This clears your identity, contacts, chats, pairing links, voice settings, and saved model keys on this device.")
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
      .navigationTitle("Reset")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
    }
  }
}

struct CloudModelProviderDetailView: View {
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
            Label("Selected: \(selected.modelId)", systemImage: "checkmark.circle")
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
    .navigationTitle(contact?.displayName ?? "Cloud Model")
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
    return Label(ready ? "Ready" : "Needs Setup", systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.triangle")
      .font(.caption)
      .foregroundColor(ready ? .green : .orange)
  }
}

struct AddCloudModelView: View {
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
      .navigationTitle("Add Model")
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
}

struct AvatarView: View {
  var contact: SignalASIContact

  var body: some View {
    ZStack {
      Circle()
        .fill(color)
      Image(systemName: iconName)
        .foregroundColor(.white)
        .font(.system(size: 18, weight: .semibold))
    }
    .frame(width: 42, height: 42)
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
          .fill(Color.green)
        Image(systemName: "person.badge.plus")
          .foregroundColor(.white)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 4) {
        Text(request.name)
          .font(.headline)
        Text(request.signalASIId)
          .lineLimit(1)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      Text(request.status.rawValue)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 4)
  }
}

struct FriendRequestDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  var requestId: String

  private var request: SignalASIFriendRequest? {
    store.friendRequest(id: requestId)
  }

  var body: some View {
    Form {
      if let request {
        Section("Identity") {
          Text(request.signalASIId)
            .font(.system(.caption, design: .monospaced))
          Text(request.identityFingerprint.chunkedFingerprint)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
        }
        if !request.mqttInboxTopic.isEmpty {
          Section("Messaging") {
            Text(request.mqttInboxTopic)
              .font(.system(.caption, design: .monospaced))
          }
        }
        Section {
          Button {
            _ = store.approveFriendRequest(id: request.id)
            dismiss()
          } label: {
            Label("Approve", systemImage: "checkmark.circle")
          }
          Button(role: .destructive) {
            _ = store.rejectFriendRequest(id: request.id)
            dismiss()
          } label: {
            Label("Reject", systemImage: "xmark.circle")
          }
        }
        .disabled(request.status != .pending)
      } else {
        Text("Request not found.")
          .foregroundColor(.secondary)
      }
    }
    .navigationTitle(request?.name ?? "Friend Request")
  }
}

struct MyContactQRCodeView: View {
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
        Section("Identity") {
          Text(store.profile.signalASIId)
            .font(.system(.caption, design: .monospaced))
          Text(store.profile.identityFingerprint.chunkedFingerprint)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
        }
        Section("Payload") {
          Text(qrText)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(6)
          Button {
            UIPasteboard.general.string = qrText
            copied = true
          } label: {
            Label(copied ? "Copied" : "Copy Payload", systemImage: "doc.on.doc")
          }
        }
      }
      .navigationTitle("My QR")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear {
        if qrText.isEmpty {
          qrText = (try? store.myContactQRText()) ?? "{}"
        }
      }
    }
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

struct AttachmentPreviewStrip: View {
  var attachments: [SignalASIDraftAttachment]
  var onRemove: (SignalASIDraftAttachment) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(attachments) { attachment in
          AttachmentPreviewChip(attachment: attachment) {
            onRemove(attachment)
          }
        }
      }
      .padding(.vertical, 2)
    }
  }
}

struct AttachmentPreviewChip: View {
  var attachment: SignalASIDraftAttachment
  var onRemove: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      thumbnail
      VStack(alignment: .leading, spacing: 2) {
        Text(attachment.displayName)
          .font(.caption)
          .lineLimit(1)
        Text(attachment.humanSize)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.secondary)
      }
    }
    .padding(8)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var thumbnail: some View {
    if attachment.isImage,
       let image = UIImage(data: attachment.data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    } else {
      Image(systemName: "doc")
        .frame(width: 34, height: 34)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
  }
}

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
  var onAttachment: (SignalASIDraftAttachment) -> Void

  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = SignalASIAttachmentPayloadBuilder.maximumAttachmentCount
    let controller = PHPickerViewController(configuration: configuration)
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onAttachment: onAttachment)
  }

  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    private let onAttachment: (SignalASIDraftAttachment) -> Void

    init(onAttachment: @escaping (SignalASIDraftAttachment) -> Void) {
      self.onAttachment = onAttachment
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      picker.dismiss(animated: true)
      results.forEach { result in
        let provider = result.itemProvider
        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
          UTType(identifier)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
          guard let data else { return }
          let name = provider.suggestedName.map { "\($0).jpg" } ?? "photo.jpg"
          let attachment = SignalASIAttachmentPayloadBuilder.makePhotoAttachment(
            data: data,
            suggestedName: name
          )
          DispatchQueue.main.async {
            self.onAttachment(attachment)
          }
        }
      }
    }
  }
}

struct QRCodeScannerView: UIViewControllerRepresentable {
  var onCode: (String) -> Void

  func makeUIViewController(context: Context) -> QRScannerViewController {
    QRScannerViewController(onCode: onCode)
  }

  func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let onCode: (String) -> Void
  private let session = AVCaptureSession()

  init(onCode: @escaping (String) -> Void) {
    self.onCode = onCode
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      return
    }
    session.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    output.metadataObjectTypes = [.qr]
    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.bounds
    view.layer.addSublayer(preview)
    session.startRunning()
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
    filter { $0.isLetter || $0.isNumber }
      .prefix(64)
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
