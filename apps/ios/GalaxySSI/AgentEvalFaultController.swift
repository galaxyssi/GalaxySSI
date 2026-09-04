import Foundation
import UIKit

struct AgentEvalFaultControllerLease: Codable, Equatable {
  var controllerId: String
  var bundleIdentifier: String
  var deviceModel: String
  var issuedAtMillis: Int64
  var heartbeatAtMillis: Int64
  var expiresAtMillis: Int64
}

struct AgentEvalFaultRequest: Codable, Equatable {
  var nonce: String
  var caseId: String
  var trialId: String = ""
  var runId: String
  var condition: AgentEvalCondition
  var controllerId: String
  var bundleIdentifier: String
  var deviceModel: String
  var createdAtMillis: Int64
  var expiresAtMillis: Int64
}

struct AgentEvalFaultReceipt: Codable, Equatable {
  var nonce: String
  var caseId: String
  var trialId: String = ""
  var runId: String
  var condition: AgentEvalCondition
  var controllerId: String
  var injectedAtMillis: Int64
  var action: String
}

enum AgentEvalFaultControllerProtocol {
  static let clockSkewMillis: Int64 = 30_000
  static let maximumLeaseMillis: Int64 = 5 * 60 * 1_000

  static func isActive(
    _ lease: AgentEvalFaultControllerLease?,
    bundleIdentifier: String,
    deviceModel: String,
    nowMillis: Int64
  ) -> Bool {
    guard let lease else { return false }
    return !lease.controllerId.isBlank &&
      lease.bundleIdentifier == bundleIdentifier && lease.deviceModel == deviceModel &&
      lease.issuedAtMillis >= 1 && lease.issuedAtMillis <= nowMillis + clockSkewMillis &&
      lease.heartbeatAtMillis >= lease.issuedAtMillis && lease.heartbeatAtMillis <= nowMillis + clockSkewMillis &&
      lease.expiresAtMillis > nowMillis &&
      lease.expiresAtMillis - lease.heartbeatAtMillis <= maximumLeaseMillis
  }

  static func isValid(
    request: AgentEvalFaultRequest,
    receipt: AgentEvalFaultReceipt?,
    activeControllerId: String,
    nowMillis: Int64
  ) -> Bool {
    guard let receipt else { return false }
    return !request.controllerId.isBlank && receipt.nonce == request.nonce &&
      receipt.caseId == request.caseId && receipt.trialId == request.trialId &&
      receipt.runId == request.runId && receipt.condition == request.condition &&
      receipt.controllerId == request.controllerId && receipt.controllerId == activeControllerId &&
      receipt.action == request.condition.rawValue &&
      receipt.injectedAtMillis >= request.createdAtMillis && receipt.injectedAtMillis <= nowMillis + clockSkewMillis &&
      receipt.injectedAtMillis <= request.expiresAtMillis
  }
}

final class AgentEvalFaultControllerStore {
  private let rootURL: URL
  private let bundleIdentifier: String
  private let deviceModel: String
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    rootURL: URL? = nil,
    bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.galaxyssi.GalaxySSI",
    deviceModel: String = UIDevice.current.model
  ) {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    self.rootURL = rootURL ?? support.appendingPathComponent("AgentEvalFaultController", isDirectory: true)
    self.bundleIdentifier = bundleIdentifier
    self.deviceModel = deviceModel
    encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
  }

  func activeLease(nowMillis: Int64 = AgentEvalClock.nowMillis()) -> AgentEvalFaultControllerLease? {
    guard let lease: AgentEvalFaultControllerLease = read(rootURL.appendingPathComponent("lease.json")),
          AgentEvalFaultControllerProtocol.isActive(
            lease, bundleIdentifier: bundleIdentifier, deviceModel: deviceModel, nowMillis: nowMillis
          ) else { return nil }
    return lease
  }

  func request(
    caseId: String,
    trialId: String,
    runId: String,
    condition: AgentEvalCondition,
    nowMillis: Int64 = AgentEvalClock.nowMillis()
  ) -> AgentEvalFaultRequest? {
    guard condition != .normal, let lease = activeLease(nowMillis: nowMillis) else { return nil }
    let request = AgentEvalFaultRequest(
      nonce: UUID().uuidString, caseId: caseId.trimmingCharacters(in: .whitespacesAndNewlines),
      trialId: trialId.trimmingCharacters(in: .whitespacesAndNewlines),
      runId: runId.trimmingCharacters(in: .whitespacesAndNewlines), condition: condition,
      controllerId: lease.controllerId, bundleIdentifier: bundleIdentifier, deviceModel: deviceModel,
      createdAtMillis: nowMillis, expiresAtMillis: nowMillis + 15 * 60 * 1_000
    )
    let directory = rootURL.appendingPathComponent("requests", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard write(request, to: directory.appendingPathComponent("\(request.nonce).json")) else { return nil }
    return request
  }

  func verifiedReceipt(
    for request: AgentEvalFaultRequest,
    nowMillis: Int64 = AgentEvalClock.nowMillis()
  ) -> AgentEvalFaultReceipt? {
    guard let lease = activeLease(nowMillis: nowMillis) else { return nil }
    let url = rootURL.appendingPathComponent("receipts/\(request.nonce).json")
    guard let receipt: AgentEvalFaultReceipt = read(url),
          AgentEvalFaultControllerProtocol.isValid(
            request: request, receipt: receipt, activeControllerId: lease.controllerId, nowMillis: nowMillis
          ) else { return nil }
    return receipt
  }

  private func read<T: Decodable>(_ url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? decoder.decode(T.self, from: data)
  }

  private func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
    guard let data = try? encoder.encode(value) else { return false }
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtection])
      return true
    } catch {
      return false
    }
  }
}
