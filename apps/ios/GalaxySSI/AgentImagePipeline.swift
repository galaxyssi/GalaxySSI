import Foundation
import UIKit

struct AgentTransportImage: Equatable {
  var data: Data
  var mimeType: String
  var lossless: Bool
  var width: Int
  var height: Int

  func transportName(originalName: String) -> String {
    guard !lossless, mimeType == "image/jpeg" else { return originalName }
    let clean = GalaxySSIAttachmentPayloadBuilder.sanitizeName(originalName)
    let base = (clean as NSString).deletingPathExtension.ifBlank("image")
    return "\(base).jpg"
  }
}

enum AgentImagePipeline {
  static let targetTransportBytes = 100_000

  static func encodeForTransport(
    _ attachment: GalaxySSIDraftAttachment,
    byteLimit: Int = targetTransportBytes,
    taskId: String = "",
    timing: AgentRuntimeTiming = AgentLatencyTelemetry.runtime
  ) -> AgentTransportImage? {
    timing.measure(
      taskId: taskId,
      phase: .imagePrepare,
      outcome: { $0 == nil ? "failed" : "completed" }
    ) {
      prepareForTransport(
        attachment,
        byteLimit: byteLimit,
        taskId: taskId,
        timing: timing
      )
    }
  }

  private static func prepareForTransport(
    _ attachment: GalaxySSIDraftAttachment,
    byteLimit: Int,
    taskId: String,
    timing: AgentRuntimeTiming
  ) -> AgentTransportImage? {
    let target = min(byteLimit, targetTransportBytes)
    guard attachment.isImage, target >= minimumTransportBudget else { return nil }
    let original = timing.measure(
      taskId: taskId,
      phase: .imageOriginalProbe
    ) {
      attachment.data.count <= target ? attachment.data : nil
    }
    if let original {
      return AgentTransportImage(
        data: original,
        mimeType: attachment.mimeType.ifBlank("image/jpeg"),
        lossless: true,
        width: 0,
        height: 0
      )
    }

    guard let decoded = timing.measure(
      taskId: taskId,
      phase: .imageDecode,
      outcome: { $0 == nil ? "failed" : "completed" },
      operation: { UIImage(data: attachment.data) }
    ) else {
      return nil
    }
    return timing.measure(
      taskId: taskId,
      phase: .imageEncode,
      outcome: { $0 == nil ? "failed" : "completed" }
    ) {
      compressForTransport(decoded, target: target)
    }
  }

  private static func compressForTransport(_ decoded: UIImage, target: Int) -> AgentTransportImage? {
    var image = flattened(scaleToMaximumDimension(decoded, maximum: maximumTransportDimension))
    for _ in 0..<maximumAttempts {
      if let data = bestJPEG(for: image, byteLimit: target) {
        return transportImage(data: data, image: image)
      }
      guard max(image.size.width, image.size.height) > minimumTransportDimension else { break }
      image = scaled(image, factor: 0.8)
    }
    guard let data = image.jpegData(compressionQuality: 0.25), data.count <= target else {
      return nil
    }
    return transportImage(data: data, image: image)
  }

  private static func transportImage(data: Data, image: UIImage) -> AgentTransportImage {
    AgentTransportImage(
      data: data,
      mimeType: "image/jpeg",
      lossless: false,
      width: max(1, Int(image.size.width.rounded())),
      height: max(1, Int(image.size.height.rounded()))
    )
  }

  private static func bestJPEG(for image: UIImage, byteLimit: Int) -> Data? {
    var low = minimumJPEGQuality
    var high = maximumJPEGQuality
    var best: Data?
    while low <= high {
      let quality = (low + high) / 2
      guard let candidate = image.jpegData(compressionQuality: CGFloat(quality) / 100) else {
        return best
      }
      if candidate.count <= byteLimit {
        best = candidate
        low = quality + 1
      } else {
        high = quality - 1
      }
    }
    return best
  }

  private static func scaleToMaximumDimension(_ image: UIImage, maximum: CGFloat) -> UIImage {
    let largest = max(image.size.width, image.size.height)
    guard largest > maximum else { return image }
    return scaled(image, factor: maximum / largest)
  }

  private static func scaled(_ image: UIImage, factor: CGFloat) -> UIImage {
    let size = CGSize(
      width: max(1, (image.size.width * factor).rounded()),
      height: max(1, (image.size.height * factor).rounded())
    )
    guard size != image.size else { return image }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  private static func flattened(_ image: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: image.size))
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
  }

  private static let maximumTransportDimension: CGFloat = 2_400
  private static let minimumTransportDimension: CGFloat = 240
  private static let minimumTransportBudget = 12 * 1_024
  private static let minimumJPEGQuality = 35
  private static let maximumJPEGQuality = 95
  private static let maximumAttempts = 8
}
