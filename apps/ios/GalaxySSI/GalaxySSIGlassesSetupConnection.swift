import Foundation
import Network
import Security

@MainActor
final class GalaxySSIGlassesSetupConnection {
  typealias Wire = GalaxySSIGlassesSetupProtocol
  private let connection: NWConnection
  private let certificate: Certificate
  private var handshake: Wire.Handshake
  private var confirmationDeadline: TimeInterval = 0
  private var transferDeadline: TimeInterval = 0
  private var started = false

  init(endpoint: NWEndpoint) throws {
    let captured = Certificate()
    certificate = captured
    handshake = try Wire.Handshake()
    let tls = NWProtocolTLS.Options()
    sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
    // This one-use socket admits a self-signed leaf only for the certificate-bound comparison.
    // No profile bytes are constructed or written until the comparison succeeds at both ends.
    sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, peerTrust, complete in
      let trust = sec_trust_copy_ref(peerTrust).takeRetainedValue()
      guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
        complete(false)
        return
      }
      let bytes = SecCertificateCopyData(leaf) as Data
      complete(!bytes.isEmpty && bytes.count <= 16_384 && captured.bind(bytes))
    }, .main)
    let parameters = NWParameters(tls: tls, tcp: .init())
    parameters.requiredInterfaceType = .wifi
    connection = NWConnection(to: endpoint, using: parameters)
  }

  deinit { connection.cancel() }

  static func manualEndpoint(host: String, port: String) -> NWEndpoint? {
    guard let address = IPv4Address(host.trimmingCharacters(in: .whitespacesAndNewlines)),
          let rawPort = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)), rawPort > 0,
          let targetPort = NWEndpoint.Port(rawValue: rawPort) else { return nil }
    let bytes = Array(address.rawValue)
    guard bytes.count == 4, bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
          (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254) else { return nil }
    return .hostPort(host: .ipv4(address), port: targetPort)
  }

  func connect() async throws -> String {
    guard !started else { throw Wire.Failure.invalid }
    started = true
    try await ready()
    let hello = try handshake.hello()
    try await write(hello)
    let challenge = try await read()
    let reveal = try handshake.reveal(after: challenge)
    try await write(reveal)
    let response = try await read()
    let code = try handshake.compare(reveal: response, certificate: certificate.bytes)
    confirmationDeadline = ProcessInfo.processInfo.systemUptime + 55
    return code
  }

  func confirm() async throws {
    guard ProcessInfo.processInfo.systemUptime < confirmationDeadline else { throw Wire.Failure.expired }
    let confirmation = try handshake.confirm()
    try await write(confirmation)
    let response = try await read()
    try handshake.acceptReady(response)
    transferDeadline = ProcessInfo.processInfo.systemUptime + 240
  }

  func transfer(_ profile: Wire.Profile) async throws {
    guard ProcessInfo.processInfo.systemUptime < transferDeadline else { throw Wire.Failure.expired }
    let configuration = try handshake.transfer(profile)
    try await write(configuration)
    let response = try await read()
    guard response["status"] == .string("saved"), response["kind"] == .string("cloud") else {
      throw Wire.Failure.rejected
    }
  }

  func close() { connection.cancel() }

  private func ready() async throws {
    try Task.checkCancellation()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.stateUpdateHandler = { [weak connection] state in
        guard let connection else { return }
        switch state {
        case .ready:
          connection.stateUpdateHandler = nil
          continuation.resume()
        case .failed, .cancelled:
          connection.stateUpdateHandler = nil
          continuation.resume(throwing: Wire.Failure.transport)
        default: break
        }
      }
      connection.start(queue: .main)
    }
    try Task.checkCancellation()
  }

  private func write(_ object: AgentMcpJSONObject) async throws {
    try Task.checkCancellation()
    let data = try Wire.frame(object)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(content: data, completion: .contentProcessed { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      })
    }
  }

  private func read() async throws -> AgentMcpJSONObject {
    let header = try await read(count: 4)
    let size = try Wire.frameLength(header)
    let body = try await read(count: size)
    return try JSONDecoder().decode(AgentMcpJSONObject.self, from: body)
  }

  private func read(count: Int) async throws -> Data {
    try Task.checkCancellation()
    return try await withCheckedThrowingContinuation { continuation in
      connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
        if let data, data.count == count, error == nil { continuation.resume(returning: data) }
        else { continuation.resume(throwing: Wire.Failure.transport) }
      }
    }
  }

  private final class Certificate: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Data()
    func bind(_ candidate: Data) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      if current.isEmpty { current = candidate }
      return current == candidate
    }
    var bytes: Data {
      lock.lock()
      defer { lock.unlock() }
      return current
    }
  }
}
