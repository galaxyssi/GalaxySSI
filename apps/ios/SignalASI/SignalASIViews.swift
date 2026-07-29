import AVFoundation
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
      HStack(spacing: 10) {
        TextField("Message", text: $draft)
          .textFieldStyle(.roundedBorder)
        Button {
          let text = draft
          draft = ""
          Task { await coordinator.send(text, to: contact) }
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 30))
        }
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding()
    }
    .navigationTitle(contact.displayName)
    .navigationBarTitleDisplayMode(.inline)
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

  var body: some View {
    NavigationView {
      List {
        ForEach(store.contacts.filter { !$0.deleted }) { contact in
          ContactRow(contact: contact, latestMessage: store.messages(for: contact.id).last)
        }
      }
      .navigationTitle("Contacts")
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
          ForEach(store.contacts.filter { $0.deliveryMode == .cloudAPI }) { contact in
            VStack(alignment: .leading) {
              Text(contact.displayName)
              Text(contact.selectedCloudModel?.modelId ?? "No model")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          Button {
            showingAddModel = true
          } label: {
            Label("Add Model", systemImage: "plus.circle")
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
    }
  }
}

struct AddCloudModelView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @State private var selectedPreset = CloudModelPreset.androidParity.first!
  @State private var provider = CloudModelPreset.androidParity.first!.provider
  @State private var displayName = CloudModelPreset.androidParity.first!.name
  @State private var modelId = CloudModelPreset.androidParity.first!.modelId
  @State private var endpoint = CloudModelPreset.androidParity.first!.endpoint
  @State private var apiStyle = CloudModelPreset.androidParity.first!.apiStyle
  @State private var apiKey = ""
  @State private var errorText = ""

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
        TextField("Endpoint", text: $endpoint)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
        Picker("API Style", selection: $apiStyle) {
          ForEach(SignalASICloudAPIStyle.allCases) { style in
            Text(style.rawValue).tag(style)
          }
        }
        SecureField("API Key", text: $apiKey)
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
        }
      }
    }
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
