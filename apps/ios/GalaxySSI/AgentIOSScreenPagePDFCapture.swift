import Foundation
import PDFKit

struct AgentIOSScreenPagePDFResult {
  let captureID: UUID
  var attachments: [GalaxySSIDraftAttachment]
  var pageCount: Int
  var extractedPages: Int
  var emptyTextPages: Int
  var truncated: Bool
}

enum AgentIOSScreenPagePDFDownloads {
  static func save(pdf: Data, captureID: UUID, documents: URL? = nil) throws -> URL {
    try Task.checkCancellation()
    guard pdf.starts(with: Data("%PDF-".utf8)) else {
      throw AgentIOSScreenPagePDFError.invalidDocument
    }
    let root = try documents ?? FileManager.default.url(for: .documentDirectory,
      in: .userDomainMask, appropriateFor: nil, create: true)
    let directory = root.appendingPathComponent("Downloads", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("article-\(captureID.uuidString.lowercased()).pdf")
    try Task.checkCancellation()
    try pdf.write(to: target, options: [.atomic, .completeFileProtection])
    return target
  }
}

enum AgentIOSScreenPagePDFError: Error, Equatable {
  case invalidDocument
  case protectedDocument
  case sizeLimit
  case pageLimit
  case timedOut
}

enum AgentIOSScreenPagePDFCapture {
  static let maximumBytes = 32 * 1_024 * 1_024
  static let maximumPages = 256
  static let maximumTextCharacters = 500_000

  static func collect(url: URL) throws -> AgentIOSScreenPagePDFResult {
    guard url.isFileURL else { throw AgentIOSScreenPagePDFError.invalidDocument }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while true {
      try Task.checkCancellation()
      let count = min(1_024 * 1_024, maximumBytes + 1 - data.count)
      guard count > 0 else { throw AgentIOSScreenPagePDFError.sizeLimit }
      guard let part = try handle.read(upToCount: count), !part.isEmpty else { break }
      data.append(part)
      guard data.count <= maximumBytes else { throw AgentIOSScreenPagePDFError.sizeLimit }
    }
    return try collect(data: data)
  }

  static func collect(data: Data, maximumCharacters: Int = maximumTextCharacters) throws -> AgentIOSScreenPagePDFResult {
    try Task.checkCancellation()
    guard !data.isEmpty else { throw AgentIOSScreenPagePDFError.invalidDocument }
    guard data.count <= maximumBytes else { throw AgentIOSScreenPagePDFError.sizeLimit }
    let started = ProcessInfo.processInfo.systemUptime
    guard let document = PDFDocument(data: data) else {
      throw AgentIOSScreenPagePDFError.invalidDocument
    }
    try Task.checkCancellation()
    guard !document.isEncrypted, !document.isLocked, document.allowsCopying else {
      throw AgentIOSScreenPagePDFError.protectedDocument
    }
    guard document.pageCount > 0 else { throw AgentIOSScreenPagePDFError.invalidDocument }
    guard document.pageCount <= maximumPages else { throw AgentIOSScreenPagePDFError.pageLimit }
    var remaining = min(max(1, maximumCharacters), maximumTextCharacters)
    var pages: [String] = []
    var emptyPages = 0
    var truncated = false
    for index in 0..<document.pageCount {
      try Task.checkCancellation()
      guard ProcessInfo.processInfo.systemUptime - started < 45 else { throw AgentIOSScreenPagePDFError.timedOut }
      guard let page = document.page(at: index) else { throw AgentIOSScreenPagePDFError.invalidDocument }
      let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty { emptyPages += 1 }
      let captured = String(text.prefix(remaining))
      pages.append(captured)
      remaining -= captured.count
      if captured.count < text.count || (remaining == 0 && index + 1 < document.pageCount) {
        truncated = true
        break
      }
    }
    try Task.checkCancellation()
    let note = "Source PDF pages: \(document.pageCount). Extracted pages: \(pages.count). " +
      "Pages without selectable text: \(emptyPages). Text truncated: \(truncated). " +
      "Text is supplementary evidence; the original PDF is retained. Image-only pages have not been OCR-verified."
    let text = note + "\n\n" + pages.enumerated().map { "[Page \($0.offset + 1)]\n\($0.element)" }.joined(separator: "\n\n")
    let sections = pages.enumerated().map {
      "<section><h2>Page \($0.offset + 1)</h2><pre>\(escapeHTML($0.element))</pre></section>"
    }.joined()
    let html = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
    <title>Captured page</title><style>body{font:16px system-ui;max-width:960px;margin:24px auto;padding:0 16px;letter-spacing:0}pre{white-space:pre-wrap;overflow-wrap:anywhere}section{border-top:1px solid #ddd;break-after:page}</style>
    </head><body><h1>Captured page</h1><p>\(escapeHTML(note))</p>\(sections)</body></html>
    """
    let captureID = UUID()
    let id = captureID.uuidString
    let source = "screen-page:\(id)"
    return AgentIOSScreenPagePDFResult(captureID: captureID, attachments: [
      GalaxySSIDraftAttachment(id: id + "-pdf", displayName: "captured-page.pdf", mimeType: "application/pdf", data: data, sourceDescription: source),
      GalaxySSIDraftAttachment(id: id + "-text", displayName: "captured-page.txt", mimeType: "text/plain", data: Data(text.utf8), sourceDescription: source),
      GalaxySSIDraftAttachment(id: id + "-html", displayName: "captured-page.html", mimeType: "text/html", data: Data(html.utf8), sourceDescription: source)
    ], pageCount: document.pageCount, extractedPages: pages.count, emptyTextPages: emptyPages, truncated: truncated)
  }

  private static func escapeHTML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
  }
}
