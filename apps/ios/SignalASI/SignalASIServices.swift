import AVFoundation
import Foundation
import Network
import Speech
import SwiftUI
import UserNotifications

enum MqttPublishResult: Equatable {
  case published
  case queued
  case failed
}

protocol SignalASILinkTransport: AnyObject {
  var onMessage: ((String, Data) -> Void)? { get set }
  func connect(clientId: String, serverLinks: [ServerLink])
  func publish(topic: String, payload: Data) async -> MqttPublishResult
}

final class SignalASIMqttClient: ObservableObject, SignalASILinkTransport {
  @Published private(set) var isConnected = false
  var onMessage: ((String, Data) -> Void)?

  private let host = NWEndpoint.Host("broker.emqx.io")
  private let port = NWEndpoint.Port(rawValue: 8883)!
  private let queue = DispatchQueue(label: "com.signalasi.ios.mqtt")
  private var connection: NWConnection?
  private var clientId = ""
  private var subscriptions: [String] = []
  private var receiveBuffer = Data()
  private var packetIdentifier: UInt16 = 1
  private var queuedPublishes: [(topic: String, payload: Data)] = []
  private var connected = false

  func connect(clientId: String, serverLinks: [ServerLink]) {
    self.clientId = clientId
    subscriptions = serverLinks.flatMap { [$0.routes.downTopic, $0.routes.controlTopic] }
    queue.async {
      if self.connection != nil {
        self.subscribeToCurrentTopics()
        return
      }
      self.start()
    }
  }

  func publish(topic: String, payload: Data) async -> MqttPublishResult {
    await withCheckedContinuation { continuation in
      queue.async {
        guard self.connection != nil, self.connected else {
          self.queuedPublishes.append((topic, payload))
          continuation.resume(returning: .queued)
          return
        }
        self.sendPublish(topic: topic, payload: payload)
        continuation.resume(returning: .published)
      }
    }
  }

  private func start() {
    let parameters = NWParameters.tls
    let connection = NWConnection(host: host, port: port, using: parameters)
    self.connection = connection
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.sendConnect()
        self.receiveLoop()
      case .failed, .cancelled:
        self.setConnected(false)
        self.connection = nil
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  private func sendConnect() {
    var variableHeader = Data()
    variableHeader.appendUTF8("MQTT")
    variableHeader.append(0x04)
    variableHeader.append(0x00)
    variableHeader.appendUInt16(30)

    var payload = Data()
    payload.appendUTF8(clientId.ifBlank("signalasi-ios-\(UUID().uuidString)"))
    sendFrame(typeAndFlags: 0x10, variableHeader + payload)
  }

  private func subscribeToCurrentTopics() {
    guard !subscriptions.isEmpty else { return }
    let packetId = nextPacketIdentifier()
    var payload = Data()
    payload.appendUInt16(packetId)
    subscriptions.forEach { topic in
      payload.appendUTF8(topic)
      payload.append(0x01)
    }
    sendFrame(typeAndFlags: 0x82, payload)
  }

  private func sendPublish(topic: String, payload: Data) {
    let packetId = nextPacketIdentifier()
    var body = Data()
    body.appendUTF8(topic)
    body.appendUInt16(packetId)
    body.append(payload)
    sendFrame(typeAndFlags: 0x32, body)
  }

  private func sendPubAck(_ packetId: UInt16) {
    var body = Data()
    body.appendUInt16(packetId)
    sendFrame(typeAndFlags: 0x40, body)
  }

  private func sendFrame(typeAndFlags: UInt8, _ payload: Data) {
    var frame = Data([typeAndFlags])
    frame.appendEncodedRemainingLength(payload.count)
    frame.append(payload)
    connection?.send(content: frame, completion: .contentProcessed { _ in })
  }

  private func receiveLoop() {
    connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, _ in
      guard let self else { return }
      if let data, !data.isEmpty {
        self.receiveBuffer.append(data)
        self.consumePackets()
      }
      if isComplete {
        self.setConnected(false)
        self.connection = nil
      } else {
        self.receiveLoop()
      }
    }
  }

  private func consumePackets() {
    while let packet = receiveBuffer.readMQTTPacket() {
      handle(packet)
    }
  }

  private func handle(_ packet: MQTTPacket) {
    let packetType = packet.header >> 4
    switch packetType {
    case 2:
      setConnected(true)
      subscribeToCurrentTopics()
      flushQueuedPublishes()
    case 3:
      handlePublish(packet)
    case 9, 4, 13:
      break
    default:
      break
    }
  }

  private func handlePublish(_ packet: MQTTPacket) {
    var index = 0
    guard let topic = packet.payload.readUTF8(at: &index) else { return }
    let qos = (packet.header >> 1) & 0x03
    if qos > 0, let packetId = packet.payload.readUInt16(at: &index) {
      sendPubAck(packetId)
    }
    let payload = packet.payload.suffix(from: index)
    DispatchQueue.main.async {
      self.onMessage?(topic, Data(payload))
    }
  }

  private func flushQueuedPublishes() {
    let pending = queuedPublishes
    queuedPublishes.removeAll()
    pending.forEach { sendPublish(topic: $0.topic, payload: $0.payload) }
  }

  private func nextPacketIdentifier() -> UInt16 {
    packetIdentifier = packetIdentifier == UInt16.max ? 1 : packetIdentifier + 1
    return packetIdentifier
  }

  private func setConnected(_ value: Bool) {
    connected = value
    DispatchQueue.main.async {
      self.isConnected = value
    }
  }
}

private struct MQTTPacket {
  var header: UInt8
  var payload: Data
}

struct CloudModelClient {
  func send(contact: SignalASIContact, store: SignalASIStore, turns: [ChatMessage]) async throws -> String {
    guard let model = contact.selectedCloudModel else {
      throw SignalASIError.missingCloudModel
    }
    guard let apiKey = await store.apiKey(for: model), !apiKey.isEmpty else {
      throw SignalASIError.missingAPIKey
    }
    switch model.apiStyle {
    case .anthropic:
      return try await sendAnthropic(model: model, apiKey: apiKey, turns: turns)
    case .gemini:
      return try await sendGemini(model: model, apiKey: apiKey, turns: turns)
    case .openAICompatible:
      return try await sendOpenAICompatible(model: model, apiKey: apiKey, turns: turns)
    }
  }

  private func sendOpenAICompatible(model: CloudModelConfig, apiKey: String, turns: [ChatMessage]) async throws -> String {
    var request = try jsonRequest(url: model.endpoint, apiKey: apiKey)
    var messages: [[String: Any]] = [
      ["role": "system", "content": defaultSystemPrompt]
    ]
    messages.append(contentsOf: turns.filter { !$0.isSystem }.suffix(16).map {
      ["role": $0.isMine ? "user" : "assistant", "content": $0.content] as [String: Any]
    })
    request.httpBody = try SignalASILinkProtocol.jsonData([
      "model": model.modelId,
      "messages": messages,
      "stream": false
    ])
    let object = try await responseObject(for: request)
    if let choices = object["choices"] as? [[String: Any]],
       let message = choices.first?["message"] as? [String: Any],
       let content = message["content"] as? String {
      return content
    }
    if let outputText = object["output_text"] as? String {
      return outputText
    }
    throw SignalASIError.unsupportedResponse
  }

  private func sendAnthropic(model: CloudModelConfig, apiKey: String, turns: [ChatMessage]) async throws -> String {
    guard let url = URL(string: model.endpoint) else {
      throw SignalASIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    let messages = turns.filter { !$0.isSystem }.suffix(16).map {
      ["role": $0.isMine ? "user" : "assistant", "content": $0.content]
    }
    request.httpBody = try SignalASILinkProtocol.jsonData([
      "model": model.modelId,
      "system": defaultSystemPrompt,
      "max_tokens": 1200,
      "messages": messages
    ])
    let object = try await responseObject(for: request)
    if let blocks = object["content"] as? [[String: Any]] {
      let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
      if !text.isEmpty { return text }
    }
    throw SignalASIError.unsupportedResponse
  }

  private func sendGemini(model: CloudModelConfig, apiKey: String, turns: [ChatMessage]) async throws -> String {
    var components = URLComponents(string: model.endpoint)
    var items = components?.queryItems ?? []
    items.append(URLQueryItem(name: "key", value: apiKey))
    components?.queryItems = items
    guard let url = components?.url else {
      throw SignalASIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let contents = turns.filter { !$0.isSystem }.suffix(16).map {
      [
        "role": $0.isMine ? "user" : "model",
        "parts": [["text": $0.content]]
      ] as [String: Any]
    }
    request.httpBody = try SignalASILinkProtocol.jsonData([
      "system_instruction": ["parts": [["text": defaultSystemPrompt]]],
      "contents": contents,
      "generationConfig": ["temperature": 0.1, "maxOutputTokens": 1200]
    ])
    let object = try await responseObject(for: request)
    if let candidates = object["candidates"] as? [[String: Any]],
       let content = candidates.first?["content"] as? [String: Any],
       let parts = content["parts"] as? [[String: Any]] {
      let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
      if !text.isEmpty { return text }
    }
    throw SignalASIError.unsupportedResponse
  }

  private func jsonRequest(url: String, apiKey: String) throws -> URLRequest {
    guard let endpoint = URL(string: url) else {
      throw SignalASIError.invalidPayload("Cloud endpoint is not a URL.")
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    if url.localizedCaseInsensitiveContains("openrouter.ai") {
      request.setValue("https://signalasi.local", forHTTPHeaderField: "HTTP-Referer")
      request.setValue("SignalASI", forHTTPHeaderField: "X-Title")
    }
    return request
  }

  private func responseObject(for request: URLRequest) async throws -> [String: Any] {
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw SignalASIError.invalidPayload("Cloud request failed with \(http.statusCode): \(body.prefix(240))")
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SignalASIError.unsupportedResponse
    }
    return object
  }

  private var defaultSystemPrompt: String {
    "You are SignalASI, a private superintelligence interface. Be concise, useful, and preserve user privacy. When a response benefits from structure, use clear sections, tables, or code blocks."
  }
}

@MainActor
final class MessageCoordinator: ObservableObject {
  @Published var pairingStatus = ""
  @Published var lastError = ""

  private let store: SignalASIStore
  private let cloudClient: CloudModelClient
  let mqttClient: SignalASIMqttClient

  init(
    store: SignalASIStore,
    cloudClient: CloudModelClient = CloudModelClient(),
    mqttClient: SignalASIMqttClient = SignalASIMqttClient()
  ) {
    self.store = store
    self.cloudClient = cloudClient
    self.mqttClient = mqttClient
    self.mqttClient.onMessage = { [weak self] topic, payload in
      Task { @MainActor in
        self?.handleIncoming(topic: topic, payload: payload)
      }
    }
  }

  func start() {
    mqttClient.connect(clientId: mqttClientId, serverLinks: store.serverLinks)
  }

  func send(_ text: String, to contact: SignalASIContact) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let outgoing = store.appendOutgoing(trimmed, to: contact.id)
    do {
      switch contact.deliveryMode {
      case .cloudAPI:
        let reply = try await cloudClient.send(contact: contact, store: store, turns: store.messages(for: contact.id))
        store.markMessage(outgoing.id, contactId: contact.id, status: .delivered)
        store.appendIncoming(reply, from: contact.id)
      case .link:
        try await publishLinkMessage(trimmed, contact: contact, outgoing: outgoing)
      case .local:
        store.markMessage(outgoing.id, contactId: contact.id, status: .delivered)
      }
    } catch {
      lastError = error.localizedDescription
      store.markMessage(outgoing.id, contactId: contact.id, status: .failed, detail: error.localizedDescription)
      store.appendSystem(error.localizedDescription, to: contact.id)
    }
  }

  func pair(using qrText: String) async throws {
    let qr = try SignalASILinkProtocol.decodePairingQRCode(from: qrText)
    let link = try store.addServerLink(from: qr, rotateClientRoute: true)
    mqttClient.connect(clientId: mqttClientId, serverLinks: store.serverLinks)
    let claim: [String: Any] = [
      "protocol": SignalASILinkProtocol.name,
      "version": SignalASILinkProtocol.version,
      "type": "signalasi_pairing_claim",
      "pairing_token": qr.pairingToken,
      "from": store.profile.signalASIId,
      "signal_name": store.profile.signalASIId,
      "signal_device_id": 1,
      "server_route_id": link.routes.serverRouteId,
      "client_route_id": link.routes.clientRouteId,
      "client_name": store.profile.name,
      "platform": "ios",
      "signalasi_id": store.profile.signalASIId,
      "identity_fingerprint": store.profile.identityFingerprint,
      "identity_public_key": store.profile.identityPublicKey,
      "signal_bundle": [
        "type": "ios-cryptokit-p256-v1",
        "identity_public_key": store.profile.identityPublicKey,
        "identity_fingerprint": store.profile.identityFingerprint
      ],
      "desktop_control_authorization_token": qr.controlAuthorizationToken,
      "requested_access_profile": qr.access.profile,
      "time": Int64(Date().timeIntervalSince1970 * 1000)
    ]
    let encrypted = try SignalASILinkProtocol.encryptPairingClaim(claim: claim, pairing: qr)
    let payload = try SignalASILinkProtocol.jsonData(encrypted)
    let result = await mqttClient.publish(topic: link.routes.pairingTopic, payload: payload)
    pairingStatus = result == .published ? "Pairing claim sent" : "Pairing claim queued"
  }

  private func publishLinkMessage(_ text: String, contact: SignalASIContact, outgoing: ChatMessage) async throws {
    guard let link = store.serverLinks.first(where: { $0.paired }) ?? store.serverLinks.first else {
      throw SignalASIError.notPaired
    }
    let payload: [String: Any] = [
      "type": "text",
      "content": text,
      "contact_id": contact.id,
      "sender": store.profile.signalASIId,
      "conversation_id": outgoing.conversationId,
      "client_message_id": outgoing.id.uuidString,
      "time": Int64(Date().timeIntervalSince1970 * 1000)
    ]
    let envelope = try SignalASILinkProtocol.makeEnvelope(
      payload: payload,
      sourceId: store.profile.signalASIId,
      targetId: link.desktopId
    )
    let wire = try SignalASILinkProtocol.jsonData([
      "scheme": "signalasi-link-ios-preview",
      "from": store.profile.signalASIId,
      "to": link.desktopId,
      "envelope": envelope
    ])
    let result = await mqttClient.publish(topic: link.routes.upTopic, payload: wire)
    switch result {
    case .published:
      store.markMessage(outgoing.id, contactId: contact.id, status: .sent)
    case .queued:
      store.markMessage(outgoing.id, contactId: contact.id, status: .queued, detail: "Waiting for MQTT connection.")
    case .failed:
      throw SignalASIError.transportUnavailable
    }
  }

  private func handleIncoming(topic: String, payload: Data) {
    guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
      return
    }
    if object.string("type") == "pairing_confirmed" {
      let access = SignalASILinkProtocol.pairingAccess(from: object.dictionary("pairing_access"))
      store.markServerPaired(desktopId: object.string("desktop_id"), access: access)
      pairingStatus = "Pairing confirmed"
      return
    }
    let appPayload: [String: Any]
    if let envelope = object.dictionary("envelope"),
       let unwrapped = SignalASILinkProtocol.unwrapEnvelope(envelope) {
      appPayload = unwrapped
    } else {
      appPayload = object
    }
    let contactId = appPayload.string("contact_id").ifBlank("hermes")
    let content = appPayload.string("content").ifBlank(appPayload.string("text"))
    guard !content.isEmpty else { return }
    store.appendIncoming(content, from: contactId, remoteMessageId: appPayload.string("message_id"))
    NotificationService.notify(title: store.contact(id: contactId)?.displayName ?? "SignalASI", body: content)
  }

  private var mqttClientId: String {
    "signalasi-ios-v1-\(store.profile.identityFingerprint.prefix(16))"
  }
}

enum NotificationService {
  static func requestAuthorization() async -> Bool {
    (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
  }

  static func notify(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = String(body.prefix(160))
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }
}

final class SpeechCaptureService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
  @Published private(set) var transcript = ""
  @Published private(set) var isRecording = false

  private let audioEngine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?

  func requestAuthorization(localeIdentifier: String) async -> Bool {
    recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    let speechGranted = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
    let micGranted = await AVAudioSession.sharedInstance().requestRecordPermission()
    return speechGranted && micGranted
  }

  @MainActor
  func start(localeIdentifier: String) throws {
    recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    transcript = ""
    request = SFSpeechAudioBufferRecognitionRequest()
    guard let request else { return }
    request.shouldReportPartialResults = true
    let input = audioEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }
    try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
    try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
    audioEngine.prepare()
    try audioEngine.start()
    isRecording = true
    task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
      DispatchQueue.main.async {
        if let result {
          self?.transcript = result.bestTranscription.formattedString
        }
        if error != nil || result?.isFinal == true {
          Task { @MainActor in self?.stop() }
        }
      }
    }
  }

  @MainActor
  func stop() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    isRecording = false
  }
}

private extension AVAudioSession {
  func requestRecordPermission() async -> Bool {
    await withCheckedContinuation { continuation in
      requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
  }
}

private extension Data {
  mutating func appendUInt16(_ value: UInt16) {
    append(UInt8((value >> 8) & 0xff))
    append(UInt8(value & 0xff))
  }

  mutating func appendUTF8(_ value: String) {
    let data = Data(value.utf8)
    appendUInt16(UInt16(data.count))
    append(data)
  }

  mutating func appendEncodedRemainingLength(_ length: Int) {
    var value = length
    repeat {
      var encoded = UInt8(value % 128)
      value /= 128
      if value > 0 { encoded = encoded | 128 }
      append(encoded)
    } while value > 0
  }

  mutating func readMQTTPacket() -> MQTTPacket? {
    guard count >= 2 else { return nil }
    let header = self[startIndex]
    var multiplier = 1
    var value = 0
    var offset = 1
    var encoded: UInt8 = 0
    repeat {
      guard offset < count else { return nil }
      encoded = self[offset]
      value += Int(encoded & 127) * multiplier
      multiplier *= 128
      offset += 1
    } while (encoded & 128) != 0
    guard count >= offset + value else { return nil }
    let payload = self.subdata(in: offset..<(offset + value))
    removeSubrange(0..<(offset + value))
    return MQTTPacket(header: header, payload: payload)
  }

  func readUTF8(at index: inout Int) -> String? {
    guard let length = readUInt16(at: &index),
          index + Int(length) <= count else {
      return nil
    }
    let data = subdata(in: index..<(index + Int(length)))
    index += Int(length)
    return String(data: data, encoding: .utf8)
  }

  func readUInt16(at index: inout Int) -> UInt16? {
    guard index + 2 <= count else { return nil }
    let value = (UInt16(self[index]) << 8) | UInt16(self[index + 1])
    index += 2
    return value
  }
}
