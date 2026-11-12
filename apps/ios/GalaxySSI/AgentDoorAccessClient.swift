import Foundation

struct AgentDoorAccessClient {
  enum Failure: Error { case invalid, unavailable }
  enum Result { case accepted, rejected, unconfirmed }
  struct Credentials: Codable {
    let account: String
    let password: String
  }
  struct Session {
    let token: String
    let user: String
    let service: URL
  }
  struct Door: Equatable {
    let name: String
    let channel: String
  }

  private static let origin = URL(string: "https://haina.taichuan.net")!
  private let send: (URLRequest) async throws -> Data

  init(send: ((URLRequest) async throws -> Data)? = nil) {
    self.send = send ?? Self.response
  }

  func login(_ credentials: Credentials) async throws -> Session {
    guard !credentials.account.isBlank, !credentials.password.isEmpty,
          credentials.account.utf8.count <= 256, credentials.password.utf8.count <= 1_024 else { throw Failure.invalid }
    let response = try await request(Self.origin.appendingPathComponent("MobileApi/House/Login"),
      form: ["account": credentials.account.trimmingCharacters(in: .whitespacesAndNewlines),
             "password": credentials.password, "loginType": "0"])
    guard Self.state(response) == true, let data = response["Data"]?.objectValue,
          let token = data["Token"]?.strictStringValue, !token.isBlank, token.utf8.count <= 2_048,
          let user = data["House"]?.objectValue?["ID"]?.stringValue, !user.isBlank, user.utf8.count <= 128 else {
      throw Failure.unavailable
    }
    try Task.checkCancellation()
    let systems = try await request(Self.origin.appendingPathComponent("GuestApi/PrivateCloud/GetSubSystems"))
    guard Self.state(systems) == true, let entries = systems["Data"]?.arrayValue else { throw Failure.unavailable }
    let hosts = entries.compactMap(\.objectValue).filter { $0["SubSystem"] == .int(1) || $0["SubSystem"] == .string("1") }
    guard hosts.count == 1, let host = hosts.first?["SubSystemHost"]?.strictStringValue,
          let service = Self.secureServiceURL(host) else { throw Failure.invalid }
    return Session(token: token, user: user, service: service)
  }

  func list(_ session: Session) async throws -> [Door] {
    guard var components = URLComponents(url: session.service.appendingPathComponent("Api/MobileApi/Index/SearchEquipment"),
      resolvingAgainstBaseURL: false) else { throw Failure.invalid }
    guard let token = session.token.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { throw Failure.invalid }
    components.percentEncodedQueryItems = [URLQueryItem(name: "token", value: token)]
    guard let url = components.url else { throw Failure.invalid }
    let response = try await request(url)
    guard Self.state(response) == true, let entries = response["Data"]?.arrayValue, entries.count <= 512 else {
      throw Failure.unavailable
    }
    return try entries.map {
      guard let entry = $0.objectValue, let name = entry["EQ_Name"]?.strictStringValue, !name.isBlank,
            name.utf16.count <= 100, let channel = entry["EQ_Num"]?.stringValue, !channel.isBlank,
            channel.utf8.count <= 128 else { throw Failure.invalid }
      return Door(name: name, channel: channel)
    }
  }

  static func uniqueDoor(_ target: AgentDoorAccessConfiguration.Target, in doors: [Door]) -> Door? {
    let matches = doors.filter { $0.name == target.service_name }
    guard matches.count == 1, let match = matches.first, doors.filter({ $0.channel == match.channel }).count == 1 else { return nil }
    return match
  }

  func open(_ session: Session, door: Door, millis: Int64) async -> Result {
    guard !Task.isCancelled, millis > 0, !door.channel.isBlank else { return .unconfirmed }
    let command = AgentMcpJSONCodec.stringify(["messageSenderType": .int(1), "formuid": .string(session.user),
      "msg": .string("tc_20150330_unlock" + String(millis))])
    // One publish attempt. A lost response cannot prove that the lock did not receive it.
    do {
      let response = try await request(Self.origin.appendingPathComponent("MobileApi/Publisher/Publish"),
        form: ["channel": door.channel, "message": command, "token": session.token])
      switch Self.state(response) {
      case true?: return .accepted
      case false?: return .rejected
      case nil: return .unconfirmed
      }
    } catch { return .unconfirmed }
  }

  private static func state(_ response: AgentMcpJSONObject) -> Bool? {
    if let value = response["State"]?.boolValue { return value }
    switch response["State"]?.strictStringValue?.lowercased() {
    case "true": return true
    case "false": return false
    default: return nil
    }
  }

  static func secureServiceURL(_ raw: String) -> URL? {
    guard var parts = URLComponents(string: raw), let host = parts.host, trusted(host),
          ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
          parts.port.map({ [80, 443].contains($0) }) ?? true, parts.user == nil, parts.password == nil,
          parts.query == nil, parts.fragment == nil, ["", "/"].contains(parts.percentEncodedPath) else { return nil }
    parts.scheme = "https"
    parts.port = nil
    return parts.url
  }

  private static func trusted(_ host: String) -> Bool {
    let lower = host.lowercased()
    return lower == "taichuan.net" || lower.hasSuffix(".taichuan.net")
  }

  private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  private func request(_ url: URL, form: [String: String]? = nil) async throws -> AgentMcpJSONObject {
    guard url.scheme?.lowercased() == "https", let host = url.host, Self.trusted(host),
          url.port == nil || url.port == 443, url.user == nil, url.password == nil else { throw Failure.invalid }
    try Task.checkCancellation()
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    if let form {
      request.httpMethod = "POST"
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      let pairs = try form.sorted(by: { $0.key < $1.key }).map { key, value -> String in
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) else { throw Failure.invalid }
        return key + "=" + encoded
      }
      request.httpBody = Data(pairs.joined(separator: "&").utf8)
    }
    let bytes = try await send(request)
    guard (1...262_144).contains(bytes.count) else { throw Failure.unavailable }
    return try JSONDecoder().decode(AgentMcpJSONObject.self, from: bytes)
  }

  private static func response(_ request: URLRequest) async throws -> Data {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForResource = 12
    let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let (stream, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
          response.url == request.url else { throw Failure.unavailable }
    var data = Data()
    for try await byte in stream {
      guard data.count < 262_144 else { throw Failure.unavailable }
      data.append(byte)
    }
    return data
  }

  private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
  }
}
