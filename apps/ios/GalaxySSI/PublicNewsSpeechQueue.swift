import CryptoKit
import Foundation

enum PublicNewsSpeechEdition: String, Codable, Equatable, Sendable {
  case original, chinese
}

struct PublicNewsSpeechBookmark: Codable, Equatable, Sendable {
  static let maximumArticles = 20
  static let maximumParagraph = 400

  struct Item: Codable, Equatable, Sendable {
    let articleKey: String
    let edition: PublicNewsSpeechEdition
  }

  var items: [Item] = []
  var index = 0
  var paragraph = 0
  var documentKey: String?

  static func key(for articleID: String) -> String {
    SHA256.hash(data: Data(articleID.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  static func isKey(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  var normalized: Self {
    guard !items.isEmpty, items.count <= Self.maximumArticles,
          items.allSatisfy({ Self.isKey($0.articleKey) }),
          Set(items.map(\.articleKey)).count == items.count else { return Self() }
    var valid = self
    valid.index = min(max(0, index), items.count - 1)
    valid.paragraph = min(max(0, paragraph), Self.maximumParagraph)
    if valid.index != index || documentKey.map(Self.isKey) != true {
      valid.documentKey = nil
      valid.paragraph = 0
    }
    return valid
  }
}

struct PublicNewsSpeechBookmarkStore {
  private static let storageKey = "publicNews.speech.bookmark.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> PublicNewsSpeechBookmark {
    guard let data = defaults.data(forKey: Self.storageKey), data.count <= 8_192,
          let saved = try? JSONDecoder().decode(PublicNewsSpeechBookmark.self, from: data) else {
      return PublicNewsSpeechBookmark()
    }
    return saved.normalized
  }

  func save(_ bookmark: PublicNewsSpeechBookmark) {
    let valid = bookmark.normalized
    guard !valid.items.isEmpty, let data = try? JSONEncoder().encode(valid), data.count <= 8_192 else {
      defaults.removeObject(forKey: Self.storageKey)
      return
    }
    defaults.set(data, forKey: Self.storageKey)
  }
}

struct PublicNewsSpeechQueue: Equatable {
  enum Phase: Equatable { case stopped, paused, loading, playing, failed, finished }
  private(set) var bookmark: PublicNewsSpeechBookmark
  private(set) var phase: Phase
  private(set) var revision: UInt64 = 0

  init(bookmark: PublicNewsSpeechBookmark = PublicNewsSpeechBookmark()) {
    self.bookmark = bookmark.normalized
    phase = self.bookmark.items.isEmpty ? .stopped : .paused
  }

  var current: PublicNewsSpeechBookmark.Item? {
    bookmark.items.indices.contains(bookmark.index) ? bookmark.items[bookmark.index] : nil
  }

  var isActive: Bool { phase == .loading || phase == .playing }

  @discardableResult
  mutating func replace(_ items: [PublicNewsSpeechBookmark.Item], paragraph: Int = 0, documentKey: String? = nil) -> Bool {
    guard paragraph >= 0, paragraph <= PublicNewsSpeechBookmark.maximumParagraph,
          items.count <= PublicNewsSpeechBookmark.maximumArticles else { return false }
    var seen = Set<String>()
    let unique = items.filter { seen.insert($0.articleKey).inserted }
    let next = PublicNewsSpeechBookmark(items: unique, paragraph: paragraph, documentKey: documentKey).normalized
    guard !next.items.isEmpty else { return false }
    revision &+= 1
    bookmark = next
    phase = .paused
    return true
  }

  mutating func resume() -> UInt64? {
    guard current != nil, !isActive else { return nil }
    if phase == .finished { bookmark.paragraph = 0 }
    revision &+= 1
    phase = .loading
    return revision
  }

  @discardableResult
  mutating func prepare(documentKey: String, paragraphCount: Int, token: UInt64) -> Bool {
    guard token == revision, phase == .loading, PublicNewsSpeechBookmark.isKey(documentKey),
          paragraphCount > 0, paragraphCount <= PublicNewsSpeechBookmark.maximumParagraph else { return false }
    if bookmark.documentKey != documentKey || bookmark.paragraph >= paragraphCount {
      bookmark.paragraph = 0
    }
    bookmark.documentKey = documentKey
    return true
  }

  @discardableResult
  mutating func began(paragraph: Int, token: UInt64) -> Bool {
    guard token == revision, isActive, paragraph == bookmark.paragraph else { return false }
    phase = .playing
    return true
  }

  @discardableResult
  mutating func finishedParagraph(_ paragraph: Int, count: Int, token: UInt64) -> Bool {
    guard token == revision, phase == .playing, paragraph == bookmark.paragraph, paragraph + 1 < count,
          count <= PublicNewsSpeechBookmark.maximumParagraph else {
      return false
    }
    bookmark.paragraph += 1
    phase = .loading
    return true
  }

  mutating func pause() {
    guard isActive else { return }
    revision &+= 1
    phase = .paused
  }

  mutating func fail(token: UInt64) {
    guard token == revision, isActive else { return }
    revision &+= 1
    phase = .failed
  }

  @discardableResult
  mutating func next() -> Bool {
    guard current != nil else { return false }
    revision &+= 1
    guard bookmark.index + 1 < bookmark.items.count else {
      phase = .finished
      bookmark.paragraph = 0
      return false
    }
    bookmark.index += 1
    bookmark.paragraph = 0
    bookmark.documentKey = nil
    phase = .paused
    return true
  }

  mutating func stop() {
    revision &+= 1
    bookmark = PublicNewsSpeechBookmark()
    phase = .stopped
  }
}

struct PublicNewsSpeechDocument: Equatable, Sendable {
  let key: String
  let paragraphs: [String]

  init?(checkpoint: PublicNewsBodyCheckpoint, edition: PublicNewsSpeechEdition) {
    switch edition {
    case .original:
      key = checkpoint.fingerprint
      paragraphs = checkpoint.source.paragraphs
    case .chinese:
      guard let translated = checkpoint.translatedDocument else { return nil }
      let body = PublicNewsOriginalBody(title: translated.title, paragraphs: translated.paragraphs)
      key = body.fingerprint
      paragraphs = translated.paragraphs
    }
    guard PublicNewsSpeechBookmark.isKey(key), !paragraphs.isEmpty,
          paragraphs.count <= PublicNewsSpeechBookmark.maximumParagraph,
          paragraphs.allSatisfy({ !$0.isBlank }) else { return nil }
  }
}
