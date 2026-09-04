import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct VoiceWhisperModelDownloadedFile {
  var temporaryFileURL: URL
  var statusCode: Int?
  var byteCount: Int64?
}

protocol VoiceWhisperModelDownloading {
  func download(_ request: VoiceWhisperModelDownloadRequest) async throws -> VoiceWhisperModelDownloadedFile
}

struct URLSessionVoiceWhisperModelDownloader: VoiceWhisperModelDownloading {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func download(_ request: VoiceWhisperModelDownloadRequest) async throws -> VoiceWhisperModelDownloadedFile {
    var urlRequest = URLRequest(url: request.sourceURL)
    urlRequest.allowsCellularAccess = request.allowsCellularAccess
    let (temporaryFileURL, response) = try await session.download(for: urlRequest)
    let statusCode = (response as? HTTPURLResponse)?.statusCode
    let byteCount = response.expectedContentLength > 0 ? response.expectedContentLength : nil
    return VoiceWhisperModelDownloadedFile(
      temporaryFileURL: temporaryFileURL,
      statusCode: statusCode,
      byteCount: byteCount
    )
  }
}

enum VoiceWhisperModelDownloadServiceError: LocalizedError, Equatable {
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case .httpStatus(let status):
      return "Whisper model download failed with HTTP \(status)."
    }
  }
}

final class VoiceWhisperModelDownloadService {
  private let manager: VoiceWhisperModelManager
  private let downloader: VoiceWhisperModelDownloading
  private let errorCode: (Error) -> String

  init(
    manager: VoiceWhisperModelManager = VoiceWhisperModelManager(),
    downloader: VoiceWhisperModelDownloading = URLSessionVoiceWhisperModelDownloader(),
    errorCode: @escaping (Error) -> String = VoiceWhisperModelDownloadService.defaultErrorCode
  ) {
    self.manager = manager
    self.downloader = downloader
    self.errorCode = errorCode
  }

  @discardableResult
  func start(
    _ model: VoiceWhisperModelProfile,
    allowsCellularAccess: Bool = true,
    meteredConfirmed: Bool = false
  ) async throws -> VoiceWhisperModelDownloadState {
    let requests = try manager.downloadRequests(
      for: model,
      allowsCellularAccess: allowsCellularAccess,
      meteredConfirmed: meteredConfirmed
    )
    _ = manager.recordProgress(model, downloadedBytes: 0, totalBytes: 0)
    var lastError: Error?
    for (index, request) in requests.enumerated() {
      let lastAttempt = index == requests.index(before: requests.endIndex)
      do {
        let downloaded = try await downloader.download(request)
        if let statusCode = downloaded.statusCode, !(200...299).contains(statusCode) {
          try? FileManager.default.removeItem(at: downloaded.temporaryFileURL)
          throw VoiceWhisperModelDownloadServiceError.httpStatus(statusCode)
        }
        if let byteCount = downloaded.byteCount {
          _ = manager.recordProgress(model, downloadedBytes: byteCount, totalBytes: byteCount)
        }
        return try manager.recordCompleted(model, temporaryFileURL: downloaded.temporaryFileURL)
      } catch {
        lastError = error
        if lastAttempt {
          _ = manager.recordFailure(model, errorCode: errorCode(error))
          throw error
        }
        _ = manager.recordProgress(model, downloadedBytes: 0, totalBytes: 0)
      }
    }
    let error = lastError ?? VoiceWhisperModelManagerError.missingDownloadURL(model.id)
    _ = manager.recordFailure(model, errorCode: errorCode(error))
    throw error
  }

  private static func defaultErrorCode(_ error: Error) -> String {
    if let serviceError = error as? VoiceWhisperModelDownloadServiceError {
      switch serviceError {
      case .httpStatus(let status):
        return "HTTP_\(status)"
      }
    }
    if let managerError = error as? VoiceWhisperModelManagerError {
      switch managerError {
      case .bundledModelDoesNotNeedDownload:
        return "BUNDLED_MODEL"
      case .unsupportedPlatform:
        return "UNSUPPORTED_PLATFORM"
      case .missingDownloadURL:
        return "MISSING_DOWNLOAD_URL"
      case .meteredDownloadConfirmationRequired:
        return "METERED_CONFIRMATION_REQUIRED"
      case .downloadUnavailable(_, let decision, _, _):
        return decision.rawValue
      case .temporaryFileMissing:
        return "TEMPORARY_FILE_MISSING"
      case .downloadedFileTooSmall:
        return "MODEL_FILE_TOO_SMALL"
      case .installFailed(_, let failure):
        return failure.rawValue
      }
    }
    return "DOWNLOAD_FAILED"
  }
}
