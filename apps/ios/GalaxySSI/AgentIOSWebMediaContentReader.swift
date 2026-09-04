import Foundation

struct AgentIOSWebMediaContent: Equatable {
  var contentURI: String
  var contentType: String
  var displayName: String
  var data: Data
}

enum AgentIOSWebMediaContentReadError: Error, Equatable {
  case contentURIRequired
  case unsupportedContentScheme
  case invalidContentURI
  case contentUnavailable(String)
  case contentTooLarge(Int64, Int64)
}

protocol AgentIOSWebMediaContentReading {
  var implementationId: String { get }
  func read(contentURI: String, maxBytes: Int64) throws -> AgentIOSWebMediaContent
}

struct AgentIOSFileWebMediaContentReader: AgentIOSWebMediaContentReading {
  var implementationId = "galaxyssi.ios.file_url_content_reader"
  var fileManager: FileManager = .default

  func read(contentURI: String, maxBytes: Int64) throws -> AgentIOSWebMediaContent {
    let url = try contentURL(contentURI)
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
      if resourceValues.isDirectory == true {
        throw AgentIOSWebMediaContentReadError.invalidContentURI
      }
      if let fileSize = resourceValues.fileSize, Int64(fileSize) > maxBytes {
        throw AgentIOSWebMediaContentReadError.contentTooLarge(Int64(fileSize), maxBytes)
      }
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      if Int64(data.count) > maxBytes {
        throw AgentIOSWebMediaContentReadError.contentTooLarge(Int64(data.count), maxBytes)
      }
      return AgentIOSWebMediaContent(
        contentURI: url.absoluteString,
        contentType: Self.contentType(for: url),
        displayName: url.lastPathComponent,
        data: data
      )
    } catch let error as AgentIOSWebMediaContentReadError {
      throw error
    } catch {
      throw AgentIOSWebMediaContentReadError.contentUnavailable(error.localizedDescription)
    }
  }

  private func contentURL(_ contentURI: String) throws -> URL {
    let trimmed = contentURI.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw AgentIOSWebMediaContentReadError.contentURIRequired
    }
    guard let url = URL(string: trimmed) else {
      throw AgentIOSWebMediaContentReadError.invalidContentURI
    }
    guard url.scheme?.lowercased() == "file" else {
      throw AgentIOSWebMediaContentReadError.unsupportedContentScheme
    }
    guard !url.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentIOSWebMediaContentReadError.invalidContentURI
    }
    return url
  }

  private static func contentType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "heic":
      return "image/heic"
    case "heif":
      return "image/heif"
    case "gif":
      return "image/gif"
    case "tif", "tiff":
      return "image/tiff"
    case "bmp":
      return "image/bmp"
    default:
      return "application/octet-stream"
    }
  }
}
