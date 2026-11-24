import CoreText
import Foundation
import PDFKit
import UIKit

enum AgentIOSWeChatArticleRenderer {
  static func render(document: AgentIOSWeChatArticleDocument, url: URL, messages: AgentIOSWeChatArticleMessages,
                     clock: AgentIOSWeChatExportClock) throws -> AgentIOSWeChatArticlePDFResult {
    try Task.checkCancellation(); try document.validate()
    let id = UUID().uuidString.lowercased()
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("wechat-\(id).pdf")
    defer { try? FileManager.default.removeItem(at: temporary) }
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    var failure: Error?, pageCount = 0, missing = 0, writtenImages = 0, writtenText = false
    let images = AgentIOSWeChatArticleImages(clock: clock)
    func checkpoint() -> Bool {
      if Task.isCancelled { failure = CancellationError() }
      else if clock.now() >= clock.origin + 300_000 { failure = AgentIOSWeChatArticleFailure.pdfFailed }
      return failure == nil
    }
    do {
      try UIGraphicsPDFRenderer(bounds: page).writePDF(to: temporary) { context in
        var y: CGFloat = 36
        func newPage() -> Bool {
          guard checkpoint() else { return false }
          guard pageCount < 100 else { failure = AgentIOSWeChatArticleFailure.tooLarge; return false }
          context.beginPage(); pageCount += 1; y = 36; return true
        }
        func text(_ value: String, size: CGFloat) {
          let attributed = NSAttributedString(string: value, attributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
          let setter = CTFramesetterCreateWithAttributedString(attributed)
          var offset = 0
          while offset < attributed.length, checkpoint() {
            if y > 720, !newPage() { return }
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0),
              CGPath(rect: CGRect(x: 36, y: 36, width: 540, height: 756 - y), transform: nil), nil)
            let visible = CTFrameGetVisibleStringRange(frame).length
            guard visible > 0 else { failure = AgentIOSWeChatArticleFailure.pdfFailed; return }
            let cg = context.cgContext
            cg.saveGState(); cg.textMatrix = .identity; cg.translateBy(x: 0, y: page.height); cg.scaleBy(x: 1, y: -1)
            CTFrameDraw(frame, cg); cg.restoreGState()
            offset += visible
            if offset < attributed.length { guard newPage() else { return } }
            else {
              let height = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: offset - visible, length: visible),
                nil, CGSize(width: 540, height: .greatestFiniteMagnitude), nil).height
              y += ceil(height) + 12
            }
          }
        }
        guard newPage() else { return }
        text(document.title, size: 22); text(url.absoluteString, size: 10)
        for block in document.blocks {
          guard checkpoint() else { break }
          switch block.kind {
          case .text:
            let value = (block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { text(value, size: 13); writtenText = true }
          case .image:
            let image = images.image(block.source)
            guard checkpoint() else { break }
            guard let image else { missing += 1; text(messages.text("wechat_article_missing_image"), size: 11); continue }
            let scale = min(540 / CGFloat(image.width), 680 / CGFloat(image.height), 1)
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            if y + size.height > 756, !newPage() { break }
            UIImage(cgImage: image).draw(in: CGRect(origin: CGPoint(x: 36, y: y), size: size))
            y += size.height + 12; writtenImages += 1
          }
        }
        guard checkpoint() else { return }
        guard (document.hasBodyText && writtenText) || writtenImages > 0 else {
          failure = AgentIOSWeChatArticleFailure.bodyUnavailable; return
        }
        text(messages.footer(missing: missing, source: url), size: 10)
      }
      if let failure { throw failure }
      try Task.checkCancellation()
      let bytes = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
      guard bytes > 0, bytes <= 32 * 1_024 * 1_024, let pdf = PDFDocument(url: temporary), pdf.pageCount == pageCount, pageCount > 0
        else { throw AgentIOSWeChatArticleFailure.pdfFailed }
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path)
      let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let directory = root.appendingPathComponent("Downloads/GongZhongHao", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let stem = String(document.title.replacingOccurrences(of: #"[^\p{L}\p{N}_-]+"#, with: "-", options: .regularExpression).prefix(40)).ifBlank("article")
      let target = directory.appendingPathComponent("\(stem)-\(id).pdf")
      try Task.checkCancellation()
      try FileManager.default.moveItem(at: temporary, to: target)
      do { try Task.checkCancellation() } catch { try? FileManager.default.removeItem(at: target); throw error }
      return .init(url: target, pages: pageCount, missingImages: missing)
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      throw (error as? AgentIOSWeChatArticleFailure) ?? .pdfFailed
    }
  }
}
