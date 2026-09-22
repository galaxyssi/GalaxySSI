import Foundation
import UIKit
import CryptoKit

struct CloudImagePayload: Equatable {
  static let maximumBytes = 100_000

  var displayName: String
  var mimeType: String
  var data: Data
  var originalData: Data?

  init(displayName: String, mimeType: String, data: Data, originalData: Data? = nil) throws {
    let normalizedMimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !data.isEmpty,
          data.count <= Self.maximumBytes,
          normalizedMimeType.hasPrefix("image/") else {
      throw CloudImagePayloadError.invalidPayload(displayName)
    }
    self.displayName = GalaxySSIAttachmentPayloadBuilder.sanitizeName(displayName)
    self.mimeType = normalizedMimeType
    self.data = data
    self.originalData = originalData
  }

  var base64: String {
    data.base64EncodedString()
  }
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
    guard let encoded = AgentImagePipeline.encodeForTransport(
      attachment,
      byteLimit: CloudImagePayload.maximumBytes,
      taskId: taskId
    ) else { return nil }
    return try? CloudImagePayload(
      displayName: encoded.transportName(originalName: attachment.displayName),
      mimeType: encoded.mimeType,
      data: encoded.data,
      originalData: attachment.data
    )
  }
}

enum CloudVisionPayloadEncoder {
  static func attachOpenAI(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    guard !images.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "content": ""])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var content = contentParts(message["content"], textType: "text")
    for image in images {
      content.append([
        "type": "image_url",
        "image_url": [
          "url": "data:\(image.mimeType);base64,\(image.base64)",
          "detail": "auto"
        ]
      ])
    }
    message["content"] = content
    conversation[index] = message
  }

  static func attachAnthropic(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    guard !images.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "content": ""])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var content = contentParts(message["content"], textType: "text")
    for image in images {
      content.append([
        "type": "image",
        "source": [
          "type": "base64",
          "media_type": image.mimeType,
          "data": image.base64
        ]
      ])
    }
    message["content"] = content
    conversation[index] = message
  }

  static func attachGemini(
    to conversation: inout [[String: Any]],
    images: [CloudImagePayload]
  ) {
    guard !images.isEmpty else { return }
    let index = latestUserIndex(in: conversation) ?? {
      conversation.append(["role": "user", "parts": [[String: Any]]()])
      return conversation.count - 1
    }()
    var message = conversation[index]
    var parts = message["parts"] as? [[String: Any]] ?? []
    for image in images {
      parts.append([
        "inline_data": [
          "mime_type": image.mimeType,
          "data": image.base64
        ]
      ])
    }
    message["parts"] = parts
    conversation[index] = message
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
    This turn contains \(imageCount) attached images indexed from 0. When the user requests grading or annotations on an image, call image_annotate with normalized answer bounds. The bounds locate answers but are never drawn. Use correct, incorrect, uncertain, or note. Incorrect marks require a short replacement answer in correction; put reasoning in note. Do not add boxes, numbering, legends, extra pages, replacement worksheets, links, or duplicate images. The app appends one annotated copy of each source image.
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
