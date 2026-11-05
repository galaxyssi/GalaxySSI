import ImageIO
import UIKit

enum CloudVisionOrientationSheet {
  static let guidance = """
  The next image is a derived orientation reference for the preceding source image, not another user attachment. Its quadrants show the same source: upper left as displayed, upper right rotated 90 degrees clockwise, lower left 180 degrees, and lower right 270 degrees clockwise. Use the most coherent reading orientation and verify it against the original. For image annotation or coordinates, refer only to the original image at index 0.
  """

  static func make(for images: [CloudImagePayload]) -> CloudImagePayload? {
    guard images.count == 1,
          let source = CGImageSourceCreateWithData(images[0].data as CFData, nil),
          CGImageSourceGetCount(source) == 1,
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 352
          ] as CFDictionary) else { return nil }
    let input = UIImage(cgImage: image)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    for cell in [360.0, 280.0, 200.0] as [CGFloat] {
      let side = cell * 2
      let sheet = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
        let context = renderer.cgContext
        context.setFillColor(gray: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        for index in 0..<4 {
          let x = CGFloat(index % 2) * cell
          let y = CGFloat(index / 2) * cell
          context.setFillColor(gray: 1, alpha: 1)
          context.fill(CGRect(x: x + 2, y: y + 2, width: cell - 4, height: cell - 4))
          let factor = (cell - 12) / max(input.size.width, input.size.height)
          let width = input.size.width * factor
          let height = input.size.height * factor
          context.saveGState()
          context.translateBy(x: x + cell / 2, y: y + cell / 2)
          context.rotate(by: CGFloat(index) * .pi / 2)
          input.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
          context.restoreGState()
        }
      }
      for quality in [0.8, 0.62, 0.45] {
        if let data = sheet.jpegData(compressionQuality: quality), data.count <= CloudImagePayload.maximumBytes {
          return try? CloudImagePayload(displayName: "orientation-reference.jpg", mimeType: "image/jpeg", data: data)
        }
      }
    }
    return nil
  }
}
