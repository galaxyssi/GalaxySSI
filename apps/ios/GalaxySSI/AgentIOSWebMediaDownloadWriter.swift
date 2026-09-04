import Foundation

struct AgentIOSWebMediaDownloadWriteResult: Equatable {
  var contentURI: String
  var bytesWritten: Int64
}

enum AgentIOSWebMediaDownloadWriteError: Error, Equatable {
  case destinationRequired
  case unsupportedDestinationScheme
  case invalidDestination
  case writeFailed(String)
}

protocol AgentIOSWebMediaDownloadWriting {
  var implementationId: String { get }
  func validate(destinationContentURI: String) throws
  func write(destinationContentURI: String, contentType: String, data: Data) throws -> AgentIOSWebMediaDownloadWriteResult
}

struct AgentIOSFileWebMediaDownloadWriter: AgentIOSWebMediaDownloadWriting {
  var implementationId = "galaxyssi.ios.file_url_download_writer"
  var fileManager: FileManager = .default

  func validate(destinationContentURI: String) throws {
    _ = try destinationURL(destinationContentURI)
  }

  func write(
    destinationContentURI: String,
    contentType: String,
    data: Data
  ) throws -> AgentIOSWebMediaDownloadWriteResult {
    let url = try destinationURL(destinationContentURI)
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let directory = url.deletingLastPathComponent()
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      return AgentIOSWebMediaDownloadWriteResult(
        contentURI: url.absoluteString,
        bytesWritten: Int64(data.count)
      )
    } catch {
      throw AgentIOSWebMediaDownloadWriteError.writeFailed(error.localizedDescription)
    }
  }

  private func destinationURL(_ destinationContentURI: String) throws -> URL {
    let trimmed = destinationContentURI.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw AgentIOSWebMediaDownloadWriteError.destinationRequired
    }
    guard let url = URL(string: trimmed) else {
      throw AgentIOSWebMediaDownloadWriteError.invalidDestination
    }
    guard url.scheme?.lowercased() == "file" else {
      throw AgentIOSWebMediaDownloadWriteError.unsupportedDestinationScheme
    }
    guard !url.hasDirectoryPath,
          !url.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentIOSWebMediaDownloadWriteError.invalidDestination
    }
    return url
  }
}
