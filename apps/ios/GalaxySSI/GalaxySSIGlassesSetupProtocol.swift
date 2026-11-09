import CryptoKit
import Foundation
import Security

enum GalaxySSIGlassesSetupProtocol {
  static let maximumFrame = 32_768
  enum Failure: Error { case invalid, transport, expired, rejected }

  struct Handshake {
    private enum State { case fresh, hello, challenge(Data), comparison, confirmation, ready, transferred }
    private var state = State.fresh
    private let nonce: Data

    init(nonce: Data? = nil) throws {
      if let nonce {
        guard nonce.count == 32 else { throw Failure.invalid }
        self.nonce = nonce
      } else {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
          guard let address = buffer.baseAddress else { return errSecParam }
          return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
        }
        guard status == errSecSuccess else { throw Failure.invalid }
        self.nonce = Data(bytes)
      }
    }

    mutating func hello() throws -> AgentMcpJSONObject {
      guard case .fresh = state else { throw Failure.invalid }
      state = .hello
      return ["type": .string("hello"), "version": .int(1), "commitment": .string(Self.digest(nonce))]
    }

    mutating func reveal(after challenge: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      guard case .hello = state, challenge["type"] == .string("challenge"), challenge["version"] == .int(1),
            let commitment = Self.decode(challenge.string("commitment")) else { throw Failure.invalid }
      state = .challenge(commitment)
      return ["type": .string("reveal"), "nonce": .string(Self.hex(nonce))]
    }

    mutating func compare(reveal: AgentMcpJSONObject, certificate: Data) throws -> String {
      guard case .challenge(let commitment) = state, reveal["type"] == .string("reveal"),
            !certificate.isEmpty, let peer = Self.decode(reveal.string("nonce")),
            let actual = Self.decode(Self.digest(peer)),
            zip(commitment, actual).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 else { throw Failure.invalid }
      state = .comparison
      var input = Data("GalaxySSI-Watch-Setup-v1".utf8)
      input.append(contentsOf: SHA256.hash(data: certificate))
      input.append(nonce)
      input.append(peer)
      let value = SHA256.hash(data: input).reduce(0) { ($0 * 256 + Int($1)) % 1_000_000 }
      return String(format: "%06d", value)
    }

    mutating func confirm() throws -> AgentMcpJSONObject {
      guard case .comparison = state else { throw Failure.invalid }
      state = .confirmation
      return ["type": .string("confirm"), "accept": .bool(true)]
    }

    mutating func acceptReady(_ reply: AgentMcpJSONObject) throws {
      guard case .confirmation = state, reply["type"] == .string("ready") else { throw Failure.invalid }
      state = .ready
    }

    mutating func transfer(_ profile: Profile) throws -> AgentMcpJSONObject {
      guard case .ready = state else { throw Failure.invalid }
      state = .transferred
      return ["type": .string("configure"), "kind": .string("cloud"),
        "agent_name": .string(profile.agentName), "profile": .object(profile.wire)]
    }

    static func digest(_ data: Data) -> String { hex(SHA256.hash(data: data)) }

    private static func hex<S: Sequence>(_ data: S) -> String where S.Element == UInt8 {
      data.map { String(format: "%02x", $0) }.joined()
    }

    private static func decode(_ value: String) -> Data? {
      guard value.utf8.count == 64, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
      else { return nil }
      let bytes = Array(value.utf8)
      func nibble(_ byte: UInt8) -> UInt8 { byte < 58 ? byte - 48 : byte - 87 }
      return Data(stride(from: 0, to: bytes.count, by: 2).map { nibble(bytes[$0]) << 4 | nibble(bytes[$0 + 1]) })
    }
  }

  struct Profile {
    let agentName: String
    fileprivate let wire: AgentMcpJSONObject

    init(agentName: String, model: CloudModelConfig, key: String) throws {
      guard Self.validEndpoint(model), !model.modelId.isBlank, model.modelId.utf16.count <= 128,
            model.modelId.rangeOfCharacter(from: .controlCharacters) == nil,
            !key.isBlank, key.utf16.count <= 4_096, key.rangeOfCharacter(from: .controlCharacters) == nil
      else { throw Failure.invalid }
      let clean = agentName.components(separatedBy: .controlCharacters).joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
      self.agentName = String(clean.prefix(80))
      wire = ["endpoint": .string(model.endpoint), "model": .string(model.modelId),
        "api_style": .string(model.apiStyle.rawValue), "api_key": .string(key)]
    }

    static func validEndpoint(_ model: CloudModelConfig) -> Bool {
      guard let endpoint = URLComponents(string: model.endpoint), endpoint.scheme == "https",
            endpoint.host?.isEmpty == false, endpoint.user == nil, endpoint.password == nil,
            endpoint.query == nil, endpoint.fragment == nil, model.endpoint.utf8.count <= 2_048 else { return false }
      switch model.apiStyle {
      case .openAICompatible: return endpoint.path.hasSuffix("/chat/completions")
      case .anthropic: return endpoint.path.hasSuffix("/messages")
      case .gemini: return endpoint.path.hasSuffix(":generateContent")
      }
    }
  }

  static func frame(_ object: AgentMcpJSONObject) throws -> Data {
    let body = Data(AgentMcpJSONCodec.stringify(object).utf8)
    guard (2...maximumFrame).contains(body.count) else { throw Failure.invalid }
    var count = UInt32(body.count).bigEndian
    return withUnsafeBytes(of: &count) { Data($0) } + body
  }

  static func frameLength(_ header: Data) throws -> Int {
    guard header.count == 4 else { throw Failure.invalid }
    let length = header.reduce(0) { ($0 << 8) | Int($1) }
    guard (2...maximumFrame).contains(length) else { throw Failure.invalid }
    return length
  }
}
