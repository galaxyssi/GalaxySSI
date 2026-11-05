import Foundation

struct PublicNewsSSEDecoder {
  struct Event: Equatable {
    let type: String
    let data: Data
  }

  static let maximumBytes = 128 * 1_024
  private var line = Data()
  private var payload = Data()
  private var type = ""
  private var frameBytes = 0

  mutating func append(_ byte: UInt8) throws -> Event? {
    frameBytes += 1
    guard frameBytes <= Self.maximumBytes else { throw PublicNewsPushError.invalidEvent }
    guard byte == 10 else { line.append(byte); return nil }
    if line.last == 13 { line.removeLast() }
    defer { line.removeAll(keepingCapacity: true) }
    if line.isEmpty {
      defer {
        type = ""
        payload.removeAll(keepingCapacity: false)
        frameBytes = 0
      }
      return type.isEmpty ? nil : Event(type: type, data: payload)
    }
    if line.starts(with: "event:".utf8) {
      type = String(decoding: line.dropFirst(6), as: UTF8.self).trimmingCharacters(in: .whitespaces)
    } else if line.starts(with: "data:".utf8) {
      var value = line.dropFirst(5)
      if value.first == 32 { value = value.dropFirst() }
      if !payload.isEmpty { payload.append(10) }
      payload.append(contentsOf: value)
    }
    return nil
  }
}

enum PublicNewsPushClient {
  private static let origin = URL(string: "https://hacker-news.firebaseio.com/v0/")!

  static func stream(onEvent: (PublicNewsSSEDecoder.Event) async throws -> Void) async throws {
    let session = makeSession(streaming: true)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: origin.appendingPathComponent("newstories.json"))
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
          http.mimeType == "text/event-stream" else { throw PublicNewsPushError.unavailable }
    var decoder = PublicNewsSSEDecoder()
    for try await byte in bytes {
      guard let event = try decoder.append(byte) else { continue }
      try Task.checkCancellation()
      switch event.type {
      case "put", "patch": try await onEvent(event)
      case "cancel", "auth_revoked": throw PublicNewsPushError.unavailable
      default: break
      }
    }
  }

  static func fetchStory(_ id: Int64, now: Date) async throws -> PublicNewsArticle? {
    let session = makeSession(streaming: false)
    defer { session.invalidateAndCancel() }
    let url = origin.appendingPathComponent("item").appendingPathComponent("\(id).json")
    let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
    guard let http = response as? HTTPURLResponse else { throw PublicNewsPushError.unavailable }
    if http.statusCode == 404 || http.statusCode == 410 { return nil }
    let limit = PublicNewsSSEDecoder.maximumBytes
    guard http.statusCode == 200, http.expectedContentLength <= Int64(limit) else { throw PublicNewsPushError.unavailable }
    var data = Data()
    for try await byte in bytes {
      guard data.count < limit else { throw PublicNewsPushError.invalidStory }
      data.append(byte)
    }
    try Task.checkCancellation()
    return try article(data, id: id, now: now)
  }

  static func article(_ data: Data, id: Int64, now: Date) throws -> PublicNewsArticle? {
    let json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    if json is NSNull { return nil }
    guard let object = json as? [String: Any],
          PublicNewsPushCursor.positiveInteger(object["id"]) == id else { throw PublicNewsPushError.invalidStory }
    guard object["type"] as? String == "story", object["dead"] as? Bool != true, object["deleted"] as? Bool != true,
          let time = PublicNewsPushCursor.positiveInteger(object["time"]),
          let rawURL = object["url"] as? String, rawURL.count <= 2_048,
          var parts = URLComponents(string: rawURL),
          ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
          let host = parts.host, host.contains("."), parts.user == nil, parts.password == nil else { return nil }
    let submitted = Date(timeIntervalSince1970: Double(time))
    guard submitted >= now.addingTimeInterval(-PublicNewsPushCursor.retention),
          submitted <= now.addingTimeInterval(300) else { return nil }
    parts.fragment = nil
    let title = PublicNewsFeedParser.plainText(object["title"] as? String ?? "", limit: 500)
    guard let url = parts.url, !title.isEmpty else { return nil }
    return PublicNewsArticle(
      url: url, title: title, summary: PublicNewsFeedParser.plainText(object["text"] as? String ?? "", limit: 800),
      publisher: host, publishedAt: nil, discoveredAt: min(submitted, now), interests: [.technology]
    )
  }

  private static func makeSession(streaming: Bool) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = streaming ? 90 : 15
    configuration.timeoutIntervalForResource = streaming ? 3_600 : 20
    return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
  }

  private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
  }
}
