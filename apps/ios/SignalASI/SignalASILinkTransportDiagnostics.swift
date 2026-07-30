import CryptoKit
import Foundation

enum SignalASILinkDiagnosticKind: String, Codable, CaseIterable {
  case encryptedReplay = "encrypted_replay"
  case pendingReplay = "pending_replay"
  case duplicateMessage = "duplicate_message"
  case duplicateReceipt = "duplicate_receipt"
  case oldCounter = "old_counter"
  case decryptFailure = "decrypt_failure"
  case chunkDuplicate = "chunk_duplicate"
  case fragmentRejected = "fragment_rejected"

  static func fromWireName(_ value: String) -> SignalASILinkDiagnosticKind? {
    allCases.first { $0.rawValue == value }
  }
}

struct SignalASILinkDiagnosticEvent: Codable, Equatable, Identifiable {
  var id: String
  var kind: SignalASILinkDiagnosticKind
  var recordedAtMillis: Int64
  var endpointRef: String
  var messageRef: String
  var detailCode: String

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case recordedAtMillis = "recorded_at"
    case endpointRef = "endpoint_ref"
    case messageRef = "message_ref"
    case detailCode = "detail_code"
  }
}

struct SignalASILinkDiagnosticSnapshot: Equatable {
  var totalEvents: Int64
  var counts: [SignalASILinkDiagnosticKind: Int64]
  var recentEvents: [SignalASILinkDiagnosticEvent]

  var replayCount: Int64 {
    count(.encryptedReplay) + count(.pendingReplay)
  }

  var duplicateCount: Int64 {
    count(.duplicateMessage) + count(.duplicateReceipt) + count(.chunkDuplicate)
  }

  var oldCounterCount: Int64 {
    count(.oldCounter)
  }

  var failureCount: Int64 {
    count(.decryptFailure) + count(.fragmentRejected)
  }

  func count(_ kind: SignalASILinkDiagnosticKind) -> Int64 {
    counts[kind] ?? 0
  }
}

protocol SignalASILinkDiagnosticStore {
  func read() -> Data?
  func write(_ data: Data)
  func clear()
}

final class UserDefaultsSignalASILinkDiagnosticStore: SignalASILinkDiagnosticStore {
  private let defaults: UserDefaults
  private let storageKey = "signalasi-ios-link-transport-diagnostics-v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func read() -> Data? {
    defaults.data(forKey: storageKey)
  }

  func write(_ data: Data) {
    defaults.set(data, forKey: storageKey)
  }

  func clear() {
    defaults.removeObject(forKey: storageKey)
  }
}

final class InMemorySignalASILinkDiagnosticStore: SignalASILinkDiagnosticStore {
  private var data: Data?

  func read() -> Data? {
    data
  }

  func write(_ data: Data) {
    self.data = data
  }

  func clear() {
    data = nil
  }
}

final class SignalASILinkDiagnosticLedger {
  static let protocolVersion = "signalasi.link-transport-diagnostics/1.0"
  static let defaultMaximumEvents = 40

  private let store: SignalASILinkDiagnosticStore
  private let clockMillis: () -> Int64
  private let maximumEvents: Int
  private let lock = NSLock()

  init(
    store: SignalASILinkDiagnosticStore,
    clockMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    maximumEvents: Int = defaultMaximumEvents
  ) {
    precondition(maximumEvents > 0)
    self.store = store
    self.clockMillis = clockMillis
    self.maximumEvents = maximumEvents
  }

  @discardableResult
  func record(
    kind: SignalASILinkDiagnosticKind,
    endpointIdentity: String = "",
    messageIdentity: String = "",
    detailCode: String = ""
  ) -> SignalASILinkDiagnosticSnapshot {
    lock.lock()
    defer { lock.unlock() }

    var state = readState()
    state.protocolName = Self.protocolVersion
    state.totalEvents += 1
    state.counts[kind.rawValue, default: 0] += 1
    state.recentEvents.append(SignalASILinkDiagnosticEvent(
      id: UUID().uuidString,
      kind: kind,
      recordedAtMillis: clockMillis(),
      endpointRef: Self.anonymizedReference(endpointIdentity),
      messageRef: Self.anonymizedReference(messageIdentity),
      detailCode: Self.normalizedDetailCode(detailCode)
    ))
    if state.recentEvents.count > maximumEvents {
      state.recentEvents = Array(state.recentEvents.suffix(maximumEvents))
    }
    writeState(state)
    return snapshot(of: state)
  }

  func snapshot() -> SignalASILinkDiagnosticSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return snapshot(of: readState())
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    store.clear()
  }

  static func anonymizedReference(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ""
    }
    let digest = Data(SHA256.hash(data: Data(trimmed.utf8)))
    return Data(digest.prefix(6)).hexString()
  }

  static func normalizedDetailCode(_ value: String) -> String {
    let lowered = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: "[^a-z0-9_.-]+", with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return String(lowered.prefix(64))
  }

  private func readState() -> PersistedState {
    guard let data = store.read(),
          let state = try? JSONDecoder.linkDiagnostics.decode(PersistedState.self, from: data) else {
      return PersistedState()
    }
    return state
  }

  private func writeState(_ state: PersistedState) {
    guard let data = try? JSONEncoder.linkDiagnostics.encode(state) else {
      return
    }
    store.write(data)
  }

  private func snapshot(of state: PersistedState) -> SignalASILinkDiagnosticSnapshot {
    let counts = Dictionary(uniqueKeysWithValues: SignalASILinkDiagnosticKind.allCases.map { kind in
      (kind, state.counts[kind.rawValue] ?? 0)
    })
    return SignalASILinkDiagnosticSnapshot(
      totalEvents: state.totalEvents,
      counts: counts,
      recentEvents: Array(state.recentEvents.reversed())
    )
  }

  private struct PersistedState: Codable {
    var protocolName: String
    var totalEvents: Int64
    var counts: [String: Int64]
    var recentEvents: [SignalASILinkDiagnosticEvent]

    init(
      protocolName: String = SignalASILinkDiagnosticLedger.protocolVersion,
      totalEvents: Int64 = 0,
      counts: [String: Int64] = [:],
      recentEvents: [SignalASILinkDiagnosticEvent] = []
    ) {
      self.protocolName = protocolName
      self.totalEvents = totalEvents
      self.counts = counts
      self.recentEvents = recentEvents
    }

    enum CodingKeys: String, CodingKey {
      case protocolName = "protocol"
      case totalEvents = "total_events"
      case counts
      case recentEvents = "recent_events"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      protocolName = try container.decodeIfPresent(String.self, forKey: .protocolName) ??
        SignalASILinkDiagnosticLedger.protocolVersion
      totalEvents = try container.decodeIfPresent(Int64.self, forKey: .totalEvents) ?? 0
      counts = try container.decodeIfPresent([String: Int64].self, forKey: .counts) ?? [:]
      recentEvents = try container.decodeIfPresent(
        [SignalASILinkDiagnosticEvent].self,
        forKey: .recentEvents
      ) ?? []
    }
  }
}

enum SignalASILinkTransportDiagnostics {
  private static let lock = NSLock()
  private static var ledger: SignalASILinkDiagnosticLedger?

  static func runtimeLedger() -> SignalASILinkDiagnosticLedger {
    lock.lock()
    defer { lock.unlock() }
    if let ledger {
      return ledger
    }
    let next = SignalASILinkDiagnosticLedger(store: UserDefaultsSignalASILinkDiagnosticStore())
    ledger = next
    return next
  }

  @discardableResult
  static func record(
    kind: SignalASILinkDiagnosticKind,
    endpointIdentity: String = "",
    messageIdentity: String = "",
    detailCode: String = ""
  ) -> SignalASILinkDiagnosticSnapshot {
    runtimeLedger().record(
      kind: kind,
      endpointIdentity: endpointIdentity,
      messageIdentity: messageIdentity,
      detailCode: detailCode
    )
  }

  static func snapshot() -> SignalASILinkDiagnosticSnapshot {
    runtimeLedger().snapshot()
  }

  static func clear() {
    runtimeLedger().clear()
  }

  static func classifyDecryptionFailure(_ error: Error) -> SignalASILinkDiagnosticKind {
    let className = String(describing: type(of: error)).lowercased(with: Locale(identifier: "en_US_POSIX"))
    let message = "\(String(describing: error)) \((error as NSError).localizedDescription)"
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
    if message.contains("old counter") || message.contains("oldcounter") {
      return .oldCounter
    }
    if className.contains("duplicatemessage") || message.contains("duplicate message") {
      return .duplicateMessage
    }
    return .decryptFailure
  }

  static func classifyFragmentFailure(_ error: Error) -> SignalASILinkDiagnosticKind {
    let message = "\(String(describing: error)) \((error as NSError).localizedDescription)"
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
    return message.contains("duplicate") ? .chunkDuplicate : .fragmentRejected
  }
}

private extension JSONEncoder {
  static var linkDiagnostics: JSONEncoder {
    JSONEncoder()
  }
}

private extension JSONDecoder {
  static var linkDiagnostics: JSONDecoder {
    JSONDecoder()
  }
}
