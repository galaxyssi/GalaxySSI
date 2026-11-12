import CryptoKit
import Foundation
import Network
import Security

// One admitted POST on one connection. This transport does not follow HTTP responses.
enum CloudTrialHTTPTransport {
  static let maximumBytes = 16 * 1_024 * 1_024
  enum Failure: Error { case invalidRequest, invalidResponse, responseTooLarge, timeout }

  struct Response {
    let status: Int
    let body: Data
  }

  struct WireRequest {
    let host: String
    let port: UInt16
    let tls: Bool
    let bytes: Data
    var sha256: String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    init(_ request: URLRequest) throws {
      guard request.httpMethod == "POST", let url = request.url,
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = parts.host, !host.isEmpty, host.utf8.allSatisfy({ Self.hostByte($0) }),
            parts.user == nil, parts.password == nil, parts.fragment == nil,
            let body = request.httpBody, !body.isEmpty, body.count <= maximumBytes
      else { throw Failure.invalidRequest }
      tls = parts.scheme?.lowercased() == "https"
      guard tls || (parts.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1"].contains(host.lowercased())),
            let port = UInt16(exactly: parts.port ?? (tls ? 443 : 80)), port > 0 else { throw Failure.invalidRequest }
      self.host = host
      self.port = port
      let path = parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath
      let target = path + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
      guard target.hasPrefix("/"), target.utf8.count <= 16_384,
            target.utf8.allSatisfy({ (33...126).contains($0) }) else { throw Failure.invalidRequest }
      var lines = ["POST \(target) HTTP/1.1", "Host: " + host + (parts.port.map { ":\($0)" } ?? ""),
        "Connection: close", "Accept-Encoding: identity", "Content-Length: \(body.count)"]
      let reserved: Set<String> = ["host", "connection", "content-length", "transfer-encoding", "accept-encoding", "expect",
        "upgrade", "proxy-authorization", "proxy-connection", "trailer", "te"]
      var seen = Set<String>()
      for (key, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
        let name = key.lowercased()
        guard Self.token(key), !reserved.contains(name), seen.insert(name).inserted,
              value.utf8.allSatisfy({ (32...126).contains($0) || $0 == 9 }) else { throw Failure.invalidRequest }
        lines.append("\(key): \(value)")
      }
      let head = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
      guard head.count <= 32_768 else { throw Failure.invalidRequest }
      bytes = head + body
    }

    static func token(_ text: String) -> Bool {
      !text.isEmpty && text.utf8.allSatisfy { hostByte($0) || "!#$%&'*+^`|~_".utf8.contains($0) }
    }

    private static func hostByte(_ byte: UInt8) -> Bool {
      (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 46
    }
  }

  struct Parser {
    private enum Framing {
      case header, length(Int), untilClose, chunkSize, chunk(Int), trailers
    }
    private static let crlf = Data([13, 10])
    private static let headerEnd = Data([13, 10, 13, 10])
    private var framing = Framing.header
    private var buffer = Data()
    private var body = Data()
    private var status = 0
    private var received = 0

    mutating func append(_ bytes: Data, complete: Bool) throws -> Response? {
      guard bytes.count <= maximumBytes + 1_048_576 - received else { throw Failure.responseTooLarge }
      received += bytes.count
      buffer.append(bytes)
      while true {
        switch framing {
        case .header:
          guard let end = buffer.range(of: Self.headerEnd) else {
            if buffer.count > 32_768 || complete { throw Failure.invalidResponse }
            return nil
          }
          guard end.lowerBound <= 32_768,
                let headers = String(data: buffer.prefix(upTo: end.lowerBound), encoding: .ascii)
          else { throw Failure.invalidResponse }
          buffer.removeSubrange(..<end.upperBound)
          let lines = headers.components(separatedBy: "\r\n")
          let first = lines[0].split(separator: " ", maxSplits: 2)
          guard first.count >= 2, first[0] == "HTTP/1.1" || first[0] == "HTTP/1.0",
                first[1].utf8.count == 3, let code = Int(first[1]), (200...599).contains(code)
          else { throw Failure.invalidResponse }
          status = code
          if !(200...299).contains(code) || code == 204 || code == 205 {
            return .init(status: status, body: Data())
          }
          var fields: [String: [String]] = [:]
          for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), WireRequest.token(String(line[..<colon])) else {
              throw Failure.invalidResponse
            }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[key, default: []].append(value.lowercased())
          }
          guard fields["content-encoding"] == nil || fields["content-encoding"] == ["identity"] else {
            throw Failure.invalidResponse
          }
          if let transfer = fields["transfer-encoding"] {
            guard transfer == ["chunked"], fields["content-length"] == nil else { throw Failure.invalidResponse }
            framing = .chunkSize
          } else if let length = fields["content-length"] {
            guard length.count == 1, !length[0].isEmpty, length[0].utf8.allSatisfy({ (48...57).contains($0) }),
                  let count = Int(length[0]), count <= maximumBytes else { throw Failure.invalidResponse }
            framing = .length(count)
          } else { framing = .untilClose }
        case .length(let count):
          if buffer.count >= count {
            guard buffer.count == count else { throw Failure.invalidResponse }
            return .init(status: status, body: buffer)
          }
          if complete { throw Failure.invalidResponse }
          return nil
        case .untilClose:
          guard buffer.count <= maximumBytes else { throw Failure.responseTooLarge }
          return complete ? .init(status: status, body: buffer) : nil
        case .chunkSize:
          guard let end = buffer.range(of: Self.crlf) else {
            if buffer.count > 1024 || complete { throw Failure.invalidResponse }
            return nil
          }
          guard end.lowerBound - buffer.startIndex <= 1024,
                let line = String(data: buffer.prefix(upTo: end.lowerBound), encoding: .ascii),
                let hex = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first,
                !hex.isEmpty, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                let count = Int(hex, radix: 16), count <= maximumBytes - body.count
          else { throw Failure.invalidResponse }
          buffer.removeSubrange(..<end.upperBound)
          framing = count == 0 ? .trailers : .chunk(count)
        case .chunk(let count):
          guard buffer.count >= count + 2 else {
            if complete { throw Failure.invalidResponse }
            return nil
          }
          guard buffer.dropFirst(count).prefix(2).elementsEqual(Self.crlf) else { throw Failure.invalidResponse }
          body.append(buffer.prefix(count))
          buffer.removeFirst(count + 2)
          framing = .chunkSize
        case .trailers:
          if buffer.starts(with: Self.crlf) { return .init(status: status, body: body) }
          if let end = buffer.range(of: Self.headerEnd), end.upperBound - buffer.startIndex <= 32_768 {
            return .init(status: status, body: body)
          }
          if buffer.count > 32_768 || complete { throw Failure.invalidResponse }
          return nil
        }
      }
    }
  }

  static func send(_ request: URLRequest, expectedSHA256: String, connectMillis: Int64, readMillis: Int64) async throws -> Response {
    let wire = try WireRequest(request)
    guard wire.sha256 == expectedSHA256 else { throw Failure.invalidRequest }
    let transfer = Transfer(wire, connectMillis: connectMillis, readMillis: readMillis)
    return try await withTaskCancellationHandler(operation: { try await transfer.run() }, onCancel: { transfer.cancel() })
  }

  private final class Transfer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "galaxyssi.trial-http")
    private let wire: WireRequest
    private let connection: NWConnection
    private let connectMillis: Int
    private let readMillis: Int
    private var parser = Parser()
    private var sent = false
    private var result: Result<Response, Error>?
    private var waiter: CheckedContinuation<Response, Error>?
    private var timeout: DispatchWorkItem?

    init(_ wire: WireRequest, connectMillis: Int64, readMillis: Int64) {
      self.wire = wire
      self.connectMillis = Int(clamping: connectMillis)
      self.readMillis = Int(clamping: readMillis)
      let tcp = NWProtocolTCP.Options()
      let parameters: NWParameters
      if wire.tls {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, wire.host)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        parameters = NWParameters(tls: tls, tcp: tcp)
      } else { parameters = NWParameters(tls: nil, tcp: tcp) }
      connection = NWConnection(host: NWEndpoint.Host(wire.host), port: NWEndpoint.Port(rawValue: wire.port)!,
        using: parameters)
    }

    func run() async throws -> Response {
      try await withCheckedThrowingContinuation { continuation in
        queue.async {
          if let result = self.result { continuation.resume(with: result); return }
          self.waiter = continuation
          self.arm(milliseconds: self.connectMillis)
          self.connection.stateUpdateHandler = { [weak self] state in self?.update(state) }
          self.connection.start(queue: self.queue)
        }
      }
    }

    func cancel() { queue.async { self.finish(.failure(CancellationError())) } }

    private func update(_ state: NWConnection.State) {
      guard result == nil else { return }
      switch state {
      case .ready:
        guard !sent else { return }
        sent = true
        arm(milliseconds: readMillis)
        connection.send(content: wire.bytes, completion: .contentProcessed { [weak self] error in
          guard let self, self.result == nil else { return }
          if let error { self.finish(.failure(error)) }
          else { self.receive() }
        })
      case .failed(let error), .waiting(let error): finish(.failure(error))
      case .cancelled: finish(.failure(CancellationError()))
      default: break
      }
    }

    private func receive() {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
        guard let self, self.result == nil else { return }
        if let error { self.finish(.failure(error)); return }
        do {
          if let response = try self.parser.append(data ?? Data(), complete: complete) {
            self.finish(.success(response))
          } else { self.receive() }
        } catch { self.finish(.failure(error)) }
      }
    }

    private func arm(milliseconds: Int) {
      timeout?.cancel()
      let next = DispatchWorkItem { [weak self] in self?.finish(.failure(Failure.timeout)) }
      timeout = next
      queue.asyncAfter(deadline: .now() + .milliseconds(max(1, milliseconds)), execute: next)
    }

    private func finish(_ outcome: Result<Response, Error>) {
      guard result == nil else { return }
      result = outcome
      timeout?.cancel()
      connection.stateUpdateHandler = nil
      connection.cancel()
      let continuation = waiter
      waiter = nil
      continuation?.resume(with: outcome)
    }
  }
}
