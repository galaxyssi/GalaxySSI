import Foundation

struct AgentBlobRelayConfiguration: Codable, Equatable {
  static let payloadType = "blob_relay_config"

  var version = 1
  var desktopId: String
  var clientRouteId: String
  var desktopFingerprint: String
  var revision: Int64
  var enabled: Bool
  var origin: String
  var provisioningToken: String

  enum CodingKeys: String, CodingKey {
    case version
    case desktopId = "desktop_id"
    case clientRouteId = "client_route_id"
    case desktopFingerprint = "desktop_fingerprint"
    case revision
    case enabled
    case origin
    case provisioningToken = "provisioning_token"
  }

  var originURL: URL? { enabled ? URL(string: origin) : nil }

  static func parse(_ payload: [String: Any], link: ServerLink) throws -> Self {
    let enabled = payload["enabled"] as? Bool
    let revision = payload["revision"] as? Int64
      ?? (payload["revision"] as? NSNumber)?.int64Value
    guard payload["version"] as? Int == 1,
          payload.string("desktop_id") == link.desktopId,
          payload.string("client_route_id") == link.routes.clientRouteId,
          payload.string("desktop_fingerprint") == link.routes.remoteFingerprint,
          link.paired,
          let revision, revision > 0,
          let enabled else {
      throw AgentBlobFailure.invalid("blob_config_identity_mismatch")
    }
    if !enabled {
      return Self(
        desktopId: link.desktopId,
        clientRouteId: link.routes.clientRouteId,
        desktopFingerprint: link.routes.remoteFingerprint,
        revision: revision,
        enabled: false,
        origin: "",
        provisioningToken: ""
      )
    }
    let origin = try normalizedHTTPSOrigin(payload.string("origin"))
    let token = payload.string("provisioning_token")
    guard AgentBlobProtocol.validHex(token, bytes: 32) else {
      throw AgentBlobFailure.invalid("invalid_blob_configuration")
    }
    return Self(
      desktopId: link.desktopId,
      clientRouteId: link.routes.clientRouteId,
      desktopFingerprint: link.routes.remoteFingerprint,
      revision: revision,
      enabled: true,
      origin: origin.absoluteString,
      provisioningToken: token
    )
  }

  static func normalizedHTTPSOrigin(_ value: String) throws -> URL {
    guard var components = URLComponents(string: value),
          components.scheme?.lowercased() == "https",
          let host = components.host, !host.isEmpty,
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil,
          components.path.isEmpty || components.path == "/" else {
      throw AgentBlobFailure.invalid("invalid_blob_relay_origin")
    }
    components.scheme = "https"
    components.host = host.lowercased()
    components.path = ""
    guard let result = components.url else {
      throw AgentBlobFailure.invalid("invalid_blob_relay_origin")
    }
    return result
  }
}

final class AgentBlobRelayConfigurationStore {
  private let rootURL: URL
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let fileManager: FileManager
  private let lock = NSLock()

  init(
    applicationSupportDirectory: URL? = nil,
    cipher: GalaxySSIAttachmentAtRestCipher = .shared,
    fileManager: FileManager = .default
  ) {
    let support = applicationSupportDirectory ?? fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? fileManager.temporaryDirectory
    self.rootURL = support.appendingPathComponent("blob-relay-config-v1", isDirectory: true)
    self.cipher = cipher
    self.fileManager = fileManager
  }

  func ingest(_ payload: [String: Any], link: ServerLink) throws {
    guard JSONSerialization.isValidJSONObject(payload),
          let raw = try? JSONSerialization.data(withJSONObject: payload),
          raw.count <= 8 * 1_024 else {
      throw AgentBlobFailure.invalid("invalid_blob_configuration")
    }
    let incoming = try AgentBlobRelayConfiguration.parse(payload, link: link)
    lock.lock()
    defer { lock.unlock() }
    if let current = readLocked(desktopId: link.desktopId, link: link) {
      if incoming.revision < current.revision { return }
      if incoming.revision == current.revision {
        guard incoming == current else {
          throw AgentBlobFailure.invalid("blob_config_revision_conflict")
        }
        return
      }
    }
    let data = try JSONEncoder().encode(incoming)
    try cipher.write(
      data,
      to: fileURL(desktopId: link.desktopId),
      purpose: purpose(desktopId: link.desktopId)
    )
  }

  func configuration(for link: ServerLink) -> AgentBlobRelayConfiguration? {
    guard link.paired else { return nil }
    lock.lock()
    defer { lock.unlock() }
    guard let value = readLocked(desktopId: link.desktopId, link: link), value.enabled else {
      return nil
    }
    return value
  }

  func remove(desktopId: String) {
    lock.lock()
    defer { lock.unlock() }
    try? fileManager.removeItem(at: fileURL(desktopId: desktopId))
  }

  private func readLocked(desktopId: String, link: ServerLink) -> AgentBlobRelayConfiguration? {
    guard let data = try? cipher.read(
      from: fileURL(desktopId: desktopId),
      purpose: purpose(desktopId: desktopId)
    ),
    let value = try? JSONDecoder().decode(AgentBlobRelayConfiguration.self, from: data),
    value.desktopId == link.desktopId,
    value.clientRouteId == link.routes.clientRouteId,
    value.desktopFingerprint == link.routes.remoteFingerprint else {
      return nil
    }
    return value
  }

  private func fileURL(desktopId: String) -> URL {
    let identity = AgentBlobProtocol.sha256(Data(desktopId.utf8))
    return rootURL.appendingPathComponent("\(identity).saenc", isDirectory: false)
  }

  private func purpose(desktopId: String) -> String {
    "blob-relay-config-v1:\(AgentBlobProtocol.sha256(Data(desktopId.utf8)))"
  }
}
