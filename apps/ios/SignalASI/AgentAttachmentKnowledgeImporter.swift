import Foundation
import PDFKit

struct AgentAttachmentKnowledgeInput: Sendable {
  var id: String
  var displayName: String
  var mimeType: String
  var data: Data
}

enum AgentAttachmentKnowledgeImporter {
  static func inputs(from attachments: [SignalASIDraftAttachment]) -> [AgentAttachmentKnowledgeInput] {
    attachments
      .filter { attachment in
        let mime = attachment.mimeType.lowercased()
        return !mime.hasPrefix("video/") &&
          !mime.hasPrefix("audio/")
      }
      .map {
        AgentAttachmentKnowledgeInput(
          id: $0.id,
          displayName: $0.displayName,
          mimeType: $0.mimeType,
          data: $0.data
        )
      }
  }

  @discardableResult
  static func importDocuments(
    _ attachments: [AgentAttachmentKnowledgeInput],
    conversationId: String,
    store: SignalASIStore
  ) -> Int {
    guard let session = store.agentSession(id: conversationId),
          !session.privateMode,
          !session.trackingPaused else {
      return 0
    }

    return attachments.reduce(into: 0) { importedCount, attachment in
      guard attachment.data.count <= AgentKnowledgeImportPolicy.maxSourceBytes,
            let content = extractText(from: attachment),
            !content.isEmpty else {
        return
      }
      let source = "agent-attachment:\(conversationId):\(attachment.id)"
      importedCount += store.replaceAgentKnowledgeSource(
        title: attachment.displayName,
        content: content,
        source: source,
        kind: knowledgeKind(for: attachment.displayName),
        tags: knowledgeTags(for: attachment)
      ).count
    }
  }

  private static func extractText(from attachment: AgentAttachmentKnowledgeInput) -> String? {
    let extensionName = URL(fileURLWithPath: attachment.displayName).pathExtension.lowercased()
    let result: String?
    if isImage(attachment, extensionName: extensionName) {
      result = extractImageText(from: attachment)
    } else if isHTML(attachment, extensionName: extensionName) {
      result = readableText(from: attachment.data).map {
        AgentIOSPublicArticleParser.plainText(from: $0)
      }
    } else {
      switch extensionName {
      case "pdf":
        result = PDFDocument(data: attachment.data).map { document in
          (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        }
      case "docx":
        result = try? AgentOfficeDocumentExtractor.extractDocx(attachment.data)
      case "xlsx":
        result = try? AgentOfficeDocumentExtractor.extractXlsx(attachment.data)
      case "pptx":
        result = try? AgentOfficeDocumentExtractor.extractPptx(attachment.data)
      default:
        result = readableText(from: attachment.data)
      }
    }
    let clean = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return clean.isEmpty ? nil : String(clean.prefix(AgentKnowledgeImportPolicy.maxExtractedCharacters))
  }

  private static func extractImageText(from attachment: AgentAttachmentKnowledgeInput) -> String? {
    guard Int64(attachment.data.count) <= AgentIOSWebMediaNativeToolCatalog.maxOcrSourceBytes else {
      return nil
    }
    let content = AgentIOSWebMediaContent(
      contentURI: "agent-attachment:\(attachment.id)",
      contentType: attachment.mimeType.ifBlank("image/unknown"),
      displayName: attachment.displayName,
      data: attachment.data
    )
    let request = AgentIOSWebMediaOCRRequest(
      contentURI: content.contentURI,
      sourceKind: "image",
      scriptHint: "auto",
      maxSourceBytes: AgentIOSWebMediaNativeToolCatalog.maxOcrSourceBytes,
      timeoutMillis: AgentIOSWebMediaNativeToolCatalog.maxToolTimeoutMillis
    )
    return try? AgentIOSVisionTextOCRRecognizer()
      .recognize(content: content, request: request)
      .text
  }

  private static func readableText(from data: Data) -> String? {
    let candidates = [
      String(data: data, encoding: .utf8),
      String(data: data, encoding: .utf16),
      String(decoding: data.prefix(512_000), as: UTF8.self)
    ]
    return candidates.compactMap { value in
      guard let value, isReadable(value) else { return nil }
      return value
    }.first
  }

  private static func isReadable(_ value: String) -> Bool {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    let sample = clean.prefix(2_000)
    let invalidScalars = sample.unicodeScalars.filter { $0.value == 0 || $0.value == 0xfffd }.count
    return invalidScalars < max(5, sample.count / 8)
  }

  private static func knowledgeKind(for displayName: String) -> AgentKnowledgeKind {
    switch URL(fileURLWithPath: displayName).pathExtension.lowercased() {
    case "txt", "md", "markdown":
      return .note
    default:
      return .document
    }
  }

  private static func isImage(_ attachment: AgentAttachmentKnowledgeInput, extensionName: String) -> Bool {
    attachment.mimeType.lowercased().hasPrefix("image/") || imageExtensions.contains(extensionName)
  }

  private static func isHTML(_ attachment: AgentAttachmentKnowledgeInput, extensionName: String) -> Bool {
    ["text/html", "application/xhtml+xml"].contains(attachment.mimeType.lowercased()) ||
      ["htm", "html", "xhtml"].contains(extensionName)
  }

  private static func knowledgeTags(for attachment: AgentAttachmentKnowledgeInput) -> [String] {
    let extensionName = URL(fileURLWithPath: attachment.displayName).pathExtension.lowercased()
    return ["agent_attachment", extensionName, attachment.mimeType.lowercased()]
      .filter { !$0.isEmpty }
  }

  private static let imageExtensions: Set<String> = [
    "apng", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
  ]
}
