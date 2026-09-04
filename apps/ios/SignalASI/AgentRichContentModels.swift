import Foundation

enum AgentRichBlockType: String, Codable, CaseIterable, Identifiable {
  case text
  case heading
  case quote
  case list
  case divider
  case code
  case json
  case keyValue = "key_value"
  case table
  case image
  case gallery
  case video
  case audio
  case file
  case link
  case citation
  case status
  case progress
  case metric
  case tool
  case diff
  case mermaid
  case chart
  case timeline
  case notice
  case html
  case webpage
  case actions
  case approval
  case form
  case unknown

  var id: String { rawValue }
}

struct AgentRichAction: Codable, Equatable, Identifiable {
  var id: String
  var label: String
  var verb: String
  var value: String
  var style: String

  enum CodingKeys: String, CodingKey {
    case id
    case label
    case verb
    case value
    case style
  }

  init(id: String, label: String, verb: String, value: String = "", style: String = "default") {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)).ifBlank("action")
    self.label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    self.verb = String(verb.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(80))
    self.value = String(value.prefix(Self.maximumValue))
    self.style = String(style.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)).ifBlank("default")
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      label: try container.decodeIfPresent(String.self, forKey: .label) ?? "",
      verb: try container.decodeIfPresent(String.self, forKey: .verb) ?? "",
      value: try container.decodeIfPresent(String.self, forKey: .value) ?? "",
      style: try container.decodeIfPresent(String.self, forKey: .style) ?? "default"
    )
  }

  private static let maximumValue = 8_000
}

struct AgentRichField: Codable, Equatable, Identifiable {
  var id: String
  var label: String
  var inputType: String
  var value: String
  var required: Bool
  var options: [String]

  enum CodingKeys: String, CodingKey {
    case id
    case label
    case inputType = "input_type"
    case value
    case required
    case options
  }

  init(
    id: String,
    label: String,
    inputType: String = "text",
    value: String = "",
    required: Bool = false,
    options: [String] = []
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    self.label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    self.inputType = String(inputType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(40))
      .ifBlank("text")
    self.value = String(value.prefix(4_000))
    self.required = required
    self.options = options.prefix(Self.maximumOptions).map { String($0.prefix(2_000)) }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      label: try container.decodeIfPresent(String.self, forKey: .label) ?? "",
      inputType: try container.decodeIfPresent(String.self, forKey: .inputType) ?? "text",
      value: try container.decodeIfPresent(String.self, forKey: .value) ?? "",
      required: try container.decodeIfPresent(Bool.self, forKey: .required) ?? false,
      options: try container.decodeIfPresent([String].self, forKey: .options) ?? []
    )
  }

  private static let maximumOptions = 50
}

struct AgentRichBlock: Codable, Equatable, Identifiable {
  var id: String
  var type: AgentRichBlockType
  var title: String
  var text: String
  var uri: String
  var dataB64: String
  var mimeType: String
  var language: String
  var columns: [String]
  var rows: [[String]]
  var value: Int
  var maximum: Int
  var fallbackText: String
  var actions: [AgentRichAction]
  var fields: [AgentRichField]
  var metadata: [String: String]

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case title
    case text
    case uri
    case dataB64 = "data_b64"
    case mimeType = "mime_type"
    case language
    case columns
    case rows
    case value
    case maximum
    case fallbackText = "fallback_text"
    case actions
    case fields
    case metadata
  }

  init(
    id: String,
    type: AgentRichBlockType,
    title: String = "",
    text: String = "",
    uri: String = "",
    dataB64: String = "",
    mimeType: String = "",
    language: String = "",
    columns: [String] = [],
    rows: [[String]] = [],
    value: Int = 0,
    maximum: Int = 100,
    fallbackText: String = "",
    actions: [AgentRichAction] = [],
    fields: [AgentRichField] = [],
    metadata: [String: String] = [:]
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)).ifBlank(UUID().uuidString)
    self.type = type
    self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    self.text = Self.normalizedText(text, type: type)
    self.uri = String(uri.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_096))
    self.dataB64 = String(dataB64.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumInlineDataCharacters))
    self.mimeType = String(mimeType.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    self.language = String(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(80))
    self.columns = columns.prefix(Self.maximumTableColumns).map { String($0.prefix(2_000)) }
    self.rows = rows.prefix(Self.maximumTableRows).map { row in
      row.prefix(Self.maximumTableColumns).map { String($0.prefix(2_000)) }
    }
    self.value = value
    self.maximum = max(maximum, 1)
    self.fallbackText = String(fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumBlockText))
    self.actions = Array(actions.prefix(Self.maximumActions))
    self.fields = Array(fields.prefix(Self.maximumFields))
    self.metadata = Dictionary(
      uniqueKeysWithValues: metadata
        .sorted { $0.key < $1.key }
        .prefix(Self.maximumMetadataItems)
        .map { key, value in
          (
            String(key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
            String(value.prefix(Self.maximumMetadataValue))
          )
        }
        .filter { !$0.0.isEmpty }
    )
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rawType = try container.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
    let decodedType = AgentRichBlockType(rawValue: rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
      ?? .unknown
    let uri = try container.decodeIfPresent(String.self, forKey: .uri) ?? ""
    let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
    let language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      type: AgentRichFormatRegistry.normalizedType(declared: decodedType, uri: uri, mimeType: mimeType, language: language),
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
      uri: uri,
      dataB64: try container.decodeIfPresent(String.self, forKey: .dataB64) ?? "",
      mimeType: mimeType,
      language: language,
      columns: try container.decodeIfPresent([String].self, forKey: .columns) ?? [],
      rows: try container.decodeIfPresent([[String]].self, forKey: .rows) ?? [],
      value: try container.decodeIfPresent(Int.self, forKey: .value) ?? 0,
      maximum: try container.decodeIfPresent(Int.self, forKey: .maximum) ?? 100,
      fallbackText: try container.decodeIfPresent(String.self, forKey: .fallbackText) ?? "",
      actions: (try container.decodeIfPresent([AgentRichAction].self, forKey: .actions) ?? []).filter {
        !$0.label.isEmpty && !$0.verb.isEmpty
      },
      fields: (try container.decodeIfPresent([AgentRichField].self, forKey: .fields) ?? []).filter {
        !$0.id.isEmpty && !$0.label.isEmpty
      },
      metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    )
  }

  var hasRenderableContent: Bool {
    !text.isEmpty ||
      !title.isEmpty ||
      !uri.isEmpty ||
      !dataB64.isEmpty ||
      !columns.isEmpty ||
      !rows.isEmpty ||
      !actions.isEmpty ||
      !fields.isEmpty ||
      [.progress, .status, .divider].contains(type)
  }

  var isArtifactBlock: Bool {
    [.image, .video, .audio, .file].contains(type)
  }

  func artifactIdentity() -> String {
    guard isArtifactBlock else { return "" }
    let artifactName = fallbackText
      .replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .ifBlank(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    if let digest = metadata["sha256"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      digest.range(of: Self.hex64, options: [.regularExpression]) != nil {
      return "sha256:\(digest):\(artifactName)"
    }
    if !dataB64.isEmpty {
      return "data:\(dataB64.hashValue):\(artifactName)"
    }
    if !uri.isEmpty {
      return "uri:\(uri.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
    if !fallbackText.isEmpty || !title.isEmpty {
      return "name:\(fallbackText.lowercased()):\(title.lowercased())"
    }
    return ""
  }

  func artifactQuality() -> Int {
    (dataB64.isEmpty ? 0 : 8) +
      (mimeType.isEmpty ? 0 : 4) +
      ((metadata["sha256"] ?? "").isEmpty ? 0 : 2) +
      (uri.hasPrefix("signalasi-artifact://") ? 1 : 0)
  }

  private static func normalizedText(_ value: String, type: AgentRichBlockType) -> String {
    let limited = String(value.prefix(maximumBlockText))
    if [.code, .diff, .json, .html, .mermaid].contains(type) {
      return limited.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
    }
    return limited.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let hex64 = "^[0-9a-f]{64}$"
  private static let maximumBlockText = 32_000
  private static let maximumInlineDataCharacters = 420 * 1_024
  private static let maximumTableColumns = 24
  private static let maximumTableRows = 500
  private static let maximumActions = 12
  private static let maximumFields = 24
  private static let maximumMetadataItems = 32
  private static let maximumMetadataValue = 2_000
}

enum AgentRichContentCodec {
  static let version = 1
  static let maximumSerializedSize = 640 * 1_024
  static let maximumBlocks = 100

  static func normalize(_ raw: String) -> String {
    let blocks = decode(raw)
    return blocks.isEmpty ? "" : encode(blocks)
  }

  static func fallbackText(_ raw: String) -> String {
    decode(raw).lazy
      .map { block in
        block.text.ifBlank(block.title.ifBlank(block.fallbackText.ifBlank(block.uri)))
      }
      .first { !$0.isEmpty } ?? ""
  }

  static func decode(_ raw: String) -> [AgentRichBlock] {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty,
      clean.utf8.count <= maximumSerializedSize,
      let data = clean.data(using: .utf8) else {
      return []
    }
    let document = try? JSONDecoder().decode(AgentRichDocument.self, from: data)
    guard let document, document.version <= version else {
      return []
    }
    var expanded: [AgentRichBlock] = []
    for block in document.blocks.prefix(maximumBlocks) where expanded.count < maximumBlocks {
      if block.type == .text,
         block.text.range(of: Self.mermaidFencePattern, options: .regularExpression) != nil {
        let parsed = fromText(block.text)
        if parsed.contains(where: { $0.type == .mermaid }) {
          expanded.append(contentsOf: parsed.prefix(maximumBlocks - expanded.count).map { value in
            var value = value
            value.metadata.merge(block.metadata) { current, _ in current }
            return value
          })
          continue
        }
      }
      if block.hasRenderableContent {
        expanded.append(block)
      }
    }
    return deduplicateArtifacts(expanded)
  }

  static func encode(_ blocks: [AgentRichBlock]) -> String {
    var limited = Array(blocks.prefix(maximumBlocks).filter(\.hasRenderableContent))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    while !limited.isEmpty {
      let document = AgentRichDocument(version: version, blocks: limited)
      guard let data = try? encoder.encode(document) else {
        return ""
      }
      if data.count <= maximumSerializedSize {
        return String(decoding: data, as: UTF8.self)
      }
      limited.removeLast()
    }
    return ""
  }

  private static func deduplicateArtifacts(_ blocks: [AgentRichBlock]) -> [AgentRichBlock] {
    var result: [AgentRichBlock] = []
    var indexes: [String: Int] = [:]
    for block in blocks {
      let identity = block.artifactIdentity()
      guard !identity.isEmpty else {
        result.append(block)
        continue
      }
      if let previous = indexes[identity] {
        if block.artifactQuality() > result[previous].artifactQuality() {
          result[previous] = block
        }
      } else {
        indexes[identity] = result.count
        result.append(block)
      }
    }
    return result
  }

  private static let mermaidFencePattern = #"(?im)^\s*```\s*mermaid\s*$"#

}

private struct AgentRichDocument: Codable {
  var version: Int
  var blocks: [AgentRichBlock]
}

enum AgentRichFormatRegistry {
  static func normalizedType(
    declared: AgentRichBlockType,
    uri: String,
    mimeType: String,
    language: String = ""
  ) -> AgentRichBlockType {
    let cleanMime = mimeType.lowercased()
    let cleanURI = uri.lowercased()
    let ext = cleanURI.split(separator: "?").first?.split(separator: ".").last.map(String.init) ?? ""
    if declared == .code && language.trimmingCharacters(in: .whitespacesAndNewlines)
      .caseInsensitiveCompare("mermaid") == .orderedSame {
      return .mermaid
    }
    if cleanMime.hasPrefix("image/") || imageExtensions.contains(ext) {
      return .image
    }
    if cleanMime.hasPrefix("video/") || videoExtensions.contains(ext) {
      return .video
    }
    if cleanMime.hasPrefix("audio/") || audioExtensions.contains(ext) {
      return .audio
    }
    if declared == .unknown && (!cleanURI.isEmpty || !cleanMime.isEmpty) {
      return .file
    }
    if declared == .code && !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .code
    }
    return declared
  }

  static func fileName(_ block: AgentRichBlock) -> String {
    let title = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !title.isEmpty {
      return safeFileName(title)
    }
    let path = block.uri.split(separator: "?").first.map(String.init) ?? block.uri
    return safeFileName(path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? "")
  }

  static func safeFileName(_ value: String) -> String {
    let name = value
      .replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/")
      .last
      .map(String.init) ?? value
    let illegal = CharacterSet(charactersIn: "\u{0}\u{1}\u{2}\u{3}\u{4}\u{5}\u{6}\u{7}\u{8}\u{9}\u{a}\u{b}\u{c}\u{d}\u{e}\u{f}\u{10}\u{11}\u{12}\u{13}\u{14}\u{15}\u{16}\u{17}\u{18}\u{19}\u{1a}\u{1b}\u{1c}\u{1d}\u{1e}\u{1f}<>:\"/\\|?*")
    let cleaned = String(name.unicodeScalars.map { illegal.contains($0) ? "_" : String($0) }.joined().prefix(180))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.ifBlank("SignalASI-artifact")
  }

  private static let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "heic", "webp"])
  private static let videoExtensions = Set(["mp4", "mov", "m4v", "webm"])
  private static let audioExtensions = Set(["mp3", "m4a", "wav", "aac", "ogg", "opus", "flac"])
}
