import Foundation
import UIKit
import CryptoKit

struct CloudImagePayload: Equatable {
  static let maximumBytes = 100_000

  var displayName: String
  var mimeType: String
  var data: Data
  var originalData: Data?
  var historicalSourceTurnId: String?
  var sendsOriginal: Bool

  init(displayName: String, mimeType: String, data: Data, originalData: Data? = nil,
       historicalSourceTurnId: String? = nil, sendsOriginal: Bool = false) throws {
    let normalizedMimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !data.isEmpty,
          data.count <= (sendsOriginal ? ComposerImageQuality.maximumOriginalBytes : Self.maximumBytes),
          normalizedMimeType.hasPrefix("image/") else {
      throw CloudImagePayloadError.invalidPayload(displayName)
    }
    self.displayName = GalaxySSIAttachmentPayloadBuilder.sanitizeName(displayName)
    self.mimeType = normalizedMimeType
    self.data = data
    self.originalData = originalData
    self.historicalSourceTurnId = historicalSourceTurnId
    self.sendsOriginal = sendsOriginal
  }

  var base64: String {
    data.base64EncodedString()
  }
}

struct CloudCoordinatorAttachmentRecovery: Codable, Equatable {
  struct Entry: Codable, Equatable {
    let messageID: UUID
    let contactID: String
    let turnID: String
    let richDigest: String
    let attachmentID: String
    let name: String
    let mime: String
    let size: Int
    let originalDigest: String
    let quality: ComposerImageQuality?
    let historicalTurn: String?
    let transportDigest: String?
  }

  let entries: [Entry]

  var isValid: Bool {
    (1...GalaxySSIAttachmentPayloadBuilder.maximumAttachmentCount).contains(entries.count) &&
      Set(entries.map(\.attachmentID)).count == entries.count && entries.allSatisfy {
        !$0.attachmentID.isBlank && !$0.turnID.isBlank && !$0.contactID.isBlank &&
          (1...GalaxySSIAttachmentPayloadBuilder.maximumAttachmentBytes).contains($0.size) &&
          ($0.historicalTurn == nil || $0.historicalTurn == $0.turnID)
      }
  }

  static func capture(_ attachments: [GalaxySSIDraftAttachment], images: [CloudImagePayload],
                      outgoing: ChatMessage, turns: [ChatMessage]) -> Self? {
    guard (1...GalaxySSIAttachmentPayloadBuilder.maximumAttachmentCount).contains(attachments.count),
          Set(attachments.map(\.id)).count == attachments.count else { return nil }
    var imageIndex = 0
    var entries: [Entry] = []
    for attachment in attachments {
      let sourceTurn = attachment.historicalSourceTurnId
      let candidates = ([outgoing] + turns.filter { $0.id != outgoing.id }).filter { message in
        message.isMine && !message.isSystem && message.conversationId == outgoing.conversationId &&
          (sourceTurn == nil || message.turnId.ifBlank(message.id.uuidString) == sourceTurn) &&
          block(for: attachment.id, in: message) != nil
      }
      let source = candidates.first(where: { $0.id == outgoing.id }) ?? (candidates.count == 1 ? candidates.first : nil)
      guard let source, !attachment.data.isEmpty, let block = block(for: attachment.id, in: source),
            block.mimeType.lowercased() == attachment.mimeType.lowercased(),
            block.metadata["size_bytes"] == String(attachment.data.count) else { return nil }
      let transport: String?
      if attachment.isImage {
        guard images.indices.contains(imageIndex), images[imageIndex].originalData == attachment.data else { return nil }
        transport = transportFingerprint(images[imageIndex])
        imageIndex += 1
      } else { transport = nil }
      entries.append(.init(messageID: source.id, contactID: source.contactId,
        turnID: source.turnId.ifBlank(source.id.uuidString), richDigest: digest(Data(source.richOutputJson.utf8)),
        attachmentID: attachment.id, name: attachment.displayName, mime: attachment.mimeType, size: attachment.data.count,
        originalDigest: digest(attachment.data), quality: attachment.composerImageQuality,
        historicalTurn: sourceTurn, transportDigest: transport))
    }
    let manifest = Self(entries: entries)
    return imageIndex == images.count && manifest.isValid ? manifest : nil
  }

  func matches(_ message: ChatMessage, entry: Entry, conversationID: String) -> Bool {
    message.id == entry.messageID && message.contactId == entry.contactID && message.isMine && !message.isSystem &&
      message.conversationId == conversationID && message.turnId.ifBlank(message.id.uuidString) == entry.turnID &&
      Self.digest(Data(message.richOutputJson.utf8)) == entry.richDigest
  }

  func restore(messages: [UUID: ChatMessage], conversationID: String, taskID: String,
               workspace: (String, String, [AgentRichBlock]) -> [AgentRestoredAttachment] = {
                 AgentAttachmentWorkspaceStager.restore(conversationId: $0, turnId: $1, blocks: $2, matchExactIDs: true)
               }) -> [CloudImagePayload]? {
    guard isValid else { return nil }
    var attachments: [GalaxySSIDraftAttachment] = []
    defer { attachments.wipeSensitive() }
    for entry in entries {
      guard !Task.isCancelled, let message = messages[entry.messageID],
            matches(message, entry: entry, conversationID: conversationID),
            let block = Self.block(for: entry.attachmentID, in: message) else { return nil }
      let inline = block.dataB64.utf8.count <= ((GalaxySSIAttachmentPayloadBuilder.maximumInlineBytes + 2) / 3) * 4
        ? Data(base64Encoded: block.dataB64) : nil
      let exactInline = inline.flatMap { $0.count == entry.size && Self.digest($0) == entry.originalDigest ? $0 : nil }
      let data = exactInline ??
        workspace(conversationID, entry.turnID, [block]).first(where: { $0.attachment.id == entry.attachmentID })?.attachment.data
      guard let data, data.count == entry.size, Self.digest(data) == entry.originalDigest else { return nil }
      attachments.append(.init(id: entry.attachmentID, displayName: entry.name, mimeType: entry.mime, data: data,
        historicalSourceTurnId: entry.historicalTurn, composerImageQuality: entry.quality))
    }
    guard let images = try? CloudImagePayloadFactory.prepare(attachments, taskId: taskID),
          images.map(Self.transportFingerprint) == entries.compactMap(\.transportDigest) else { return nil }
    return images
  }

  private static func block(for id: String, in message: ChatMessage) -> AgentRichBlock? {
    let matches = AgentRichContentCodec.decode(message.richOutputJson).filter {
      $0.id == id && $0.metadata["source"] == "user_attachment" && [.image, .file, .audio, .video].contains($0.type)
    }
    return matches.count == 1 ? matches.first : nil
  }

  private static func transportFingerprint(_ image: CloudImagePayload) -> String {
    AgentMcpJSONCodec.sha256(["bytes": .string(digest(image.data)), "name": .string(image.displayName),
      "mime": .string(image.mimeType), "original": .bool(image.sendsOriginal),
      "historical_turn": image.historicalSourceTurnId.map(AgentMcpJSONValue.string) ?? .null])
  }

  private static func digest(_ data: Data) -> String { GalaxySSIAttachmentPayloadBuilder.sha256(data) }
}

enum CloudImagePayloadError: LocalizedError, Equatable {
  case invalidPayload(String)
  case preparationFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidPayload(let name):
      return "Cloud image payload is invalid: \(name)"
    case .preparationFailed(let name):
      return "Cloud image could not be prepared: \(name)"
    }
  }
}

enum CloudImagePayloadFactory {
  static func prepare(
    _ attachments: [GalaxySSIDraftAttachment],
    taskId: String = ""
  ) throws -> [CloudImagePayload] {
    try attachments
      .filter(\.isImage)
      .map { attachment in
        guard let payload = payload(for: attachment, taskId: taskId) else {
          throw CloudImagePayloadError.preparationFailed(attachment.displayName)
        }
        return payload
      }
  }

  private static func payload(
    for attachment: GalaxySSIDraftAttachment,
    taskId: String
  ) -> CloudImagePayload? {
    let sendsOriginal = attachment.composerImageQuality == .original
    guard let encoded = AgentImagePipeline.encodeForTransport(
      attachment,
      byteLimit: sendsOriginal ? ComposerImageQuality.maximumOriginalBytes : CloudImagePayload.maximumBytes,
      taskId: taskId
    ) else { return nil }
    return try? CloudImagePayload(
      displayName: encoded.transportName(originalName: attachment.displayName),
      mimeType: encoded.mimeType,
      data: encoded.data,
      originalData: attachment.data,
      historicalSourceTurnId: attachment.historicalSourceTurnId,
      sendsOriginal: sendsOriginal
    )
  }
}

enum CloudVisionPayloadEncoder {
  static func attachOpenAI(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    let currentImages = insertHistoricalReferences(into: &conversation, images: images) { label, image in
      ["role": "user", "content": [
        ["type": "text", "text": label],
        ["type": "image_url", "image_url": ["url": "data:\(image.mimeType);base64,\(image.base64)", "detail": "auto"]]
      ]]
    }
    guard !currentImages.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "content": ""])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var content = contentParts(message["content"], textType: "text")
    let reference = CloudVisionOrientationSheet.make(for: images)
    let payloads = currentImages.map { (Optional($0.offset), $0.element) } + (reference.map { [(nil, $0)] } ?? [])
    for (sourceIndex, image) in payloads {
      if sourceIndex == nil { content.append(["type": "text", "text": CloudVisionOrientationSheet.guidance]) }
      content.append([
        "type": "image_url",
        "image_url": [
          "url": "data:\(image.mimeType);base64,\(image.base64)",
          "detail": "auto"
        ]
      ])
      if let sourceIndex { content.append(["type": "text", "text": sourceLabel(sourceIndex)]) }
    }
    message["content"] = content
    conversation[index] = message
  }

  static func attachAnthropic(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    let currentImages = insertHistoricalReferences(into: &conversation, images: images) { label, image in
      ["role": "user", "content": [
        ["type": "text", "text": label],
        ["type": "image", "source": ["type": "base64", "media_type": image.mimeType, "data": image.base64]]
      ]]
    }
    guard !currentImages.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "content": ""])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var content = contentParts(message["content"], textType: "text")
    let reference = CloudVisionOrientationSheet.make(for: images)
    let payloads = currentImages.map { (Optional($0.offset), $0.element) } + (reference.map { [(nil, $0)] } ?? [])
    for (sourceIndex, image) in payloads {
      if sourceIndex == nil { content.append(["type": "text", "text": CloudVisionOrientationSheet.guidance]) }
      content.append([
        "type": "image",
        "source": [
          "type": "base64",
          "media_type": image.mimeType,
          "data": image.base64
        ]
      ])
      if let sourceIndex { content.append(["type": "text", "text": sourceLabel(sourceIndex)]) }
    }
    message["content"] = content
    conversation[index] = message
  }

  static func attachGemini(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    let currentImages = insertHistoricalReferences(into: &conversation, images: images,
      emptyUser: ["role": "user", "parts": [[String: Any]]()]) { label, image in
      ["role": "user", "parts": [
        ["text": label],
        ["inline_data": ["mime_type": image.mimeType, "data": image.base64]]
      ]]
    }
    guard !currentImages.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "parts": [[String: Any]]()])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var parts = message["parts"] as? [[String: Any]] ?? []
    let reference = CloudVisionOrientationSheet.make(for: images)
    let payloads = currentImages.map { (Optional($0.offset), $0.element) } + (reference.map { [(nil, $0)] } ?? [])
    for (sourceIndex, image) in payloads {
      if sourceIndex == nil { parts.append(["text": CloudVisionOrientationSheet.guidance]) }
      parts.append([
        "inline_data": [
          "mime_type": image.mimeType,
          "data": image.base64
        ]
      ])
      if let sourceIndex { parts.append(["text": sourceLabel(sourceIndex)]) }
    }
    message["parts"] = parts
    conversation[index] = message
  }

  private static func insertHistoricalReferences(
    into conversation: inout [[String: Any]], images: [CloudImagePayload],
    emptyUser: [String: Any] = ["role": "user", "content": ""],
    message: (String, CloudImagePayload) -> [String: Any]
  ) -> [(offset: Int, element: CloudImagePayload)] {
    var references: [[String: Any]] = []
    var current: [(offset: Int, element: CloudImagePayload)] = []
    for (index, image) in images.enumerated() {
      guard let turn = image.historicalSourceTurnId else { current.append((index, image)); continue }
      let safeTurn = String(turn.unicodeScalars.filter {
        CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0)
      }.prefix(128).map(String.init).joined())
      let label = "Historical image reference (source turn: \(safeTurn), image index: \(index)). " +
        "This is not a new upload. Use it only if relevant to the latest request; do not restart the earlier task."
      references.append(message(label, image))
    }
    if !references.isEmpty {
      if !current.isEmpty && latestUserIndex(in: conversation) == nil { conversation.append(emptyUser) }
      conversation.insert(contentsOf: references, at: latestUserIndex(in: conversation) ?? conversation.endIndex)
    }
    return current
  }

  private static func sourceLabel(_ index: Int) -> String {
    "Source image index: \(index)."
  }

  private static func latestUserIndex(in conversation: [[String: Any]]) -> Int? {
    conversation.indices.reversed().first { conversation[$0]["role"] as? String == "user" }
  }

  private static func contentParts(_ value: Any?, textType: String) -> [[String: Any]] {
    if let content = value as? [[String: Any]] {
      return content
    }
    if let content = value as? [[Any]] {
      return content.compactMap { $0 as? [String: Any] }
    }
    guard let text = value as? String, !text.isEmpty else { return [] }
    return [["type": textType, "text": text]]
  }
}

struct CloudImageAnnotationMark: Equatable {
  var left: CGFloat
  var top: CGFloat
  var right: CGFloat
  var bottom: CGFloat
  var verdict: String
  var note: String
  var correction: String
}

struct CloudImageAnnotationPlan: Equatable {
  static let toolName = "image_annotate"
  static let maximumMarks = 24

  var imageIndex: Int
  var marks: [CloudImageAnnotationMark]

  static func parse(_ arguments: AgentMcpJSONObject, imageCount: Int) throws -> Self {
    guard let imageIndex = arguments["image_index"]?.integerForSchema,
          (0..<imageCount).contains(imageIndex),
          let values = arguments["marks"]?.arrayValue,
          (1...maximumMarks).contains(values.count) else {
      throw GalaxySSIError.invalidPayload("Image annotation needs a valid image index and 1 to 24 marks.")
    }
    let marks = try values.map { value -> CloudImageAnnotationMark in
      guard let item = value.objectValue else {
        throw GalaxySSIError.invalidPayload("Each image annotation mark must be an object.")
      }
      func coordinate(_ key: String) throws -> CGFloat {
        guard let value = item[key]?.doubleForSchema, value.isFinite, (0...1).contains(value) else {
          throw GalaxySSIError.invalidPayload("Image annotation coordinates must be between zero and one.")
        }
        return CGFloat(value)
      }
      let left = try coordinate("left")
      let top = try coordinate("top")
      let right = try coordinate("right")
      let bottom = try coordinate("bottom")
      let verdict = item["verdict"]?.strictStringValue ?? ""
      let note = item["note"]?.strictStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let correction = item["correction"]?.strictStringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard left < right, top < bottom,
            ["correct", "incorrect", "uncertain", "note"].contains(verdict),
            (1...160).contains(note.count),
            !note.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            correction.count <= 40,
            !correction.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            verdict != "incorrect" || !correction.isEmpty else {
        throw GalaxySSIError.invalidPayload("Image annotation verdicts and corrections are invalid.")
      }
      return CloudImageAnnotationMark(
        left: left, top: top, right: right, bottom: bottom,
        verdict: verdict, note: note, correction: correction
      )
    }
    return Self(imageIndex: imageIndex, marks: marks)
  }

  static func instruction(imageCount: Int) -> String {
    guard imageCount > 0 else { return "" }
    return """
    There are \(imageCount) available source images indexed from 0. Historical references are not new uploads. Use the source image index in its label, not its position in the conversation. Derived orientation references have no source index and cannot be annotated. Only annotate when the latest user request asks for grading or annotations; call image_annotate with normalized bounds on the source image. The bounds locate answers but are never drawn. Use correct, incorrect, uncertain, or note. Incorrect marks require a short replacement answer in correction; put reasoning in note. Do not add boxes, numbering, legends, extra pages, replacement worksheets, links, or duplicate images. The app appends one annotated copy of each source image.
    """
  }
}

enum CloudImageAnnotationRenderer {
  static func render(source: UIImage, plan: CloudImageAnnotationPlan) throws -> UIImage {
    let source = normalized(source)
    guard let cgImage = source.cgImage,
          cgImage.width > 0, cgImage.height > 0,
          Int64(cgImage.width) * Int64(cgImage.height) <= 8_000_000 else {
      throw GalaxySSIError.invalidPayload("Input image is too large or could not be decoded.")
    }
    let size = CGSize(width: cgImage.width, height: cgImage.height)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = false
    let bounds = plan.marks.map {
      CGRect(x: $0.left * size.width, y: $0.top * size.height,
             width: ($0.right - $0.left) * size.width,
             height: ($0.bottom - $0.top) * size.height)
    }
    var occupied: [CGRect] = []
    var renderingError: Error?
    let output = UIGraphicsImageRenderer(size: size, format: format).image { context in
      source.draw(in: CGRect(origin: .zero, size: size))
      let drawing = context.cgContext
      drawing.setLineCap(.round)
      drawing.setLineJoin(.round)
      for (index, mark) in plan.marks.enumerated() {
        let answer = bounds[index]
        let markSize = min(size.width * 0.024, answer.height * 0.48)
          .clamped(to: 12...36)
        let color = color(for: mark.verdict)
        let correction = mark.verdict == "incorrect" ? mark.correction : ""
        let maximumLabelWidth = max(size.width * 0.32, markSize)
        var fontSize = markSize
        var attributes: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
          .foregroundColor: color
        ]
        var correctionWidth = (correction as NSString).size(withAttributes: attributes).width
        while correctionWidth > maximumLabelWidth, fontSize > markSize * 0.6 {
          fontSize = max(markSize * 0.6, fontSize - 0.5)
          attributes[.font] = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
          correctionWidth = (correction as NSString).size(withAttributes: attributes).width
        }
        let gap = max(markSize * 0.25, 2)
        guard correctionWidth + markSize + gap <= size.width else {
          renderingError = GalaxySSIError.invalidPayload("Shorten the correction to fit beside the answer.")
          return
        }
        let inkWidth = min(size.width, markSize + (correction.isEmpty ? 0 : gap + correctionWidth))
        let ink = placement(
          around: answer,
          inkSize: CGSize(width: inkWidth, height: markSize * 1.2),
          gap: gap,
          canvas: CGRect(origin: .zero, size: size),
          occupied: bounds + occupied
        )
        occupied.append(ink)
        drawing.setStrokeColor(color.cgColor)
        drawing.setLineWidth(max(markSize * 0.1, 1.5))
        let x = ink.minX
        let y = ink.minY + markSize * 0.2
        switch mark.verdict {
        case "correct":
          drawing.move(to: CGPoint(x: x, y: y + markSize * 0.45))
          drawing.addLine(to: CGPoint(x: x + markSize * 0.32, y: y + markSize * 0.8))
          drawing.addLine(to: CGPoint(x: x + markSize, y: y))
          drawing.strokePath()
        case "incorrect":
          drawing.move(to: CGPoint(x: x, y: y))
          drawing.addLine(to: CGPoint(x: x + markSize * 0.8, y: y + markSize * 0.8))
          drawing.move(to: CGPoint(x: x + markSize * 0.8, y: y))
          drawing.addLine(to: CGPoint(x: x, y: y + markSize * 0.8))
          drawing.strokePath()
        default:
          ((mark.verdict == "uncertain" ? "?" : "*") as NSString).draw(
            at: CGPoint(x: x, y: y), withAttributes: attributes
          )
        }
        if !correction.isEmpty {
          (correction as NSString).draw(
            at: CGPoint(x: x + markSize + gap, y: y + markSize - fontSize),
            withAttributes: attributes
          )
        }
      }
    }
    if let renderingError { throw renderingError }
    return output
  }

  private static func color(for verdict: String) -> UIColor {
    switch verdict {
    case "correct": return UIColor(red: 0, green: 0.49, blue: 0.29, alpha: 1)
    case "incorrect": return UIColor(red: 0.76, green: 0.14, blue: 0.16, alpha: 1)
    case "uncertain": return UIColor(red: 0.57, green: 0.37, blue: 0, alpha: 1)
    default: return UIColor(red: 0.14, green: 0.33, blue: 0.63, alpha: 1)
    }
  }

  private static func normalized(_ source: UIImage) -> UIImage {
    guard source.imageOrientation != .up else { return source }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = source.scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
      source.draw(in: CGRect(origin: .zero, size: source.size))
    }
  }

  private static func placement(
    around answer: CGRect,
    inkSize: CGSize,
    gap: CGFloat,
    canvas: CGRect,
    occupied: [CGRect]
  ) -> CGRect {
    func candidate(_ x: CGFloat, _ y: CGFloat) -> CGRect {
      CGRect(
        x: x.clamped(to: canvas.minX...(canvas.maxX - inkSize.width)),
        y: y.clamped(to: canvas.minY...(canvas.maxY - inkSize.height)),
        width: inkSize.width,
        height: inkSize.height
      )
    }
    let choices = [
      candidate(answer.maxX + gap, answer.midY - inkSize.height / 2),
      candidate(answer.minX - gap - inkSize.width, answer.midY - inkSize.height / 2),
      candidate(answer.maxX - inkSize.width, answer.maxY + gap),
      candidate(answer.minX, answer.maxY + gap),
      candidate(answer.maxX - inkSize.width, answer.minY - gap - inkSize.height),
      candidate(answer.minX, answer.minY - gap - inkSize.height)
    ]
    return choices.enumerated().min { lhs, rhs in
      score(lhs.element, preference: lhs.offset, answer: answer, occupied: occupied) <
        score(rhs.element, preference: rhs.offset, answer: answer, occupied: occupied)
    }?.element ?? choices[0]
  }

  private static func score(_ rect: CGRect, preference: Int, answer: CGRect, occupied: [CGRect]) -> CGFloat {
    let overlap = occupied.reduce(CGFloat.zero) { result, item in
      let intersection = rect.intersection(item)
      return result + (intersection.isNull ? 0 : intersection.width * intersection.height)
    }
    return overlap * 1_000 + abs(rect.midY - answer.midY) + CGFloat(preference)
  }
}

private extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
  }
}
