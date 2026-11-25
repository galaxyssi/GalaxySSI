import Foundation

enum AgentIOSWeChatArticleFailure: Error, Equatable {
  case bodyUnavailable, loadFailed, tooLarge, pdfFailed, verificationExpired, verificationRequired, alreadySaving
  var key: String {
    switch self {
    case .bodyUnavailable: return "wechat_article_body_unavailable"
    case .loadFailed: return "ios_wechat_load_failed"
    case .tooLarge: return "wechat_article_too_large"
    case .pdfFailed: return "wechat_article_pdf_failed"
    case .verificationExpired: return "wechat_article_verification_expired"
    case .verificationRequired: return "wechat_article_verification"
    case .alreadySaving: return "ios_wechat_already_saving"
    }
  }
}

struct AgentIOSWeChatArticleMessages {
  let language: String
  func text(_ key: String) -> String {
    func value(_ locale: String, fallback: String) -> String {
      guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: path) else { return fallback }
      return bundle.localizedString(forKey: key, value: fallback,
        table: key.hasPrefix("ios_wechat_") ? "WeChatArticleExportNative" : "WeChatArticleExport")
    }
    let english = value("en", fallback: key)
    return value(LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en", fallback: english)
  }
  func saved(_ result: AgentIOSWeChatArticlePDFResult) -> String {
    String(format: text(result.missingImages > 0 ? "ios_wechat_saved_partial" : "ios_wechat_saved"),
      Int64(result.pages), result.url.lastPathComponent, Int64(result.missingImages))
  }
  func footer(missing: Int, source: URL) -> String {
    text("wechat_article_static") + "\n" + String(format: text("ios_wechat_archive_notice"), Int64(missing), source.absoluteString)
  }
}

struct AgentIOSWeChatArticleDocument: Decodable {
  struct Block: Decodable {
    enum Kind: String, Decodable { case text, image }
    let kind: Kind
    let text: String?
    let source: String?
  }
  let title: String
  let hasBodyText: Bool
  let blocks: [Block]
  func validate() throws {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !blocks.isEmpty else {
      throw AgentIOSWeChatArticleFailure.bodyUnavailable
    }
    guard blocks.count <= 32_768 else { throw AgentIOSWeChatArticleFailure.tooLarge }
  }
}

struct AgentIOSWeChatArticlePDFResult {
  let url: URL
  let pages: Int
  let missingImages: Int
}
struct AgentIOSWeChatArticleSource {
  let url: URL
  let html: String
  let httpError: Bool
}

struct AgentIOSWeChatExportClock {
  private let epoch = Int64(Date().timeIntervalSince1970 * 1_000)
  private let uptime = ProcessInfo.processInfo.systemUptime
  var origin: Int64 { epoch }
  func now() -> Int64 { epoch + Int64(max(0, ProcessInfo.processInfo.systemUptime - uptime) * 1_000) }
}

enum AgentIOSWeChatArticleLimits {
  static let htmlBytes = 8 * 1_024 * 1_024
  static let imageBytes: Int64 = 8 * 1_024 * 1_024
  static let allImageBytes: Int64 = 48 * 1_024 * 1_024
  static let imageTimeout: Int64 = 4_000
  static let imageBudget: Int64 = 35_000
  static let uniqueImages = 128
}

final class AgentIOSWeChatExportGate {
  static let shared = AgentIOSWeChatExportGate()
  private let lock = NSLock()
  private var owner: UUID?
  func acquire() throws -> Lease {
    lock.lock(); defer { lock.unlock() }
    guard owner == nil else { throw AgentIOSWeChatArticleFailure.alreadySaving }
    let id = UUID(); owner = id
    return Lease(id: id, gate: self)
  }
  private func release(_ id: UUID) {
    lock.lock(); defer { lock.unlock() }
    if owner == id { owner = nil }
  }
  final class Lease {
    let id: UUID
    private let gate: AgentIOSWeChatExportGate
    fileprivate init(id: UUID, gate: AgentIOSWeChatExportGate) { self.id = id; self.gate = gate }
    deinit { gate.release(id) }
  }
}
