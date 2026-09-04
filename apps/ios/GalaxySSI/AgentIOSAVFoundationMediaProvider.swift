import Foundation
import UniformTypeIdentifiers

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UIKit) && os(iOS)
import UIKit
#endif

struct AgentIOSMediaMetadataSnapshot: Equatable {
  var contentUri: String
  var contentType: String
  var displayName: String
  var sizeBytes: Int64
  var durationMillis: Int64
  var width: Int
  var height: Int
  var rotationDegrees: Int
  var hasAudio: Bool
  var hasVideo: Bool

  func output(observedAtMillis: Int64) -> AgentMcpJSONObject {
    [
      "content_uri": .string(contentUri),
      "content_type": .string(contentType),
      "display_name": .string(displayName),
      "size_bytes": .int(sizeBytes),
      "duration_ms": .int(max(0, durationMillis)),
      "width": .int(Int64(max(0, width))),
      "height": .int(Int64(max(0, height))),
      "rotation_degrees": .int(Int64(normalizedRotation)),
      "has_audio": .bool(hasAudio),
      "has_video": .bool(hasVideo),
      "observed_at_epoch_ms": .int(max(0, observedAtMillis)),
      "source": .object(["content_uri": .string(contentUri)])
    ]
  }

  private var normalizedRotation: Int {
    ((rotationDegrees % 360) + 360) % 360
  }
}

protocol AgentIOSMediaMetadataInspecting {
  var implementationId: String { get }
  var availability: AgentNativeToolAvailability { get }
  func inspect(fileURL: URL, contentUri: String) throws -> AgentIOSMediaMetadataSnapshot
}

struct AgentIOSMediaPlaybackOpenResult: Equatable {
  var launched: Bool
  var action: String
  var handlerPackage: String
}

protocol AgentIOSMediaPlaybackOpening {
  var implementationId: String { get }
  var availability: AgentNativeToolAvailability { get }
  func open(fileURL: URL, contentType: String) throws -> AgentIOSMediaPlaybackOpenResult
}

struct AgentIOSAVFoundationMediaProvider: AgentIOSMediaNativeToolProviding {
  var implementationId: String = "galaxyssi.ios.avfoundation_media"
  var metadataInspector: AgentIOSMediaMetadataInspecting
  var playbackOpener: AgentIOSMediaPlaybackOpening
  var fileManager: FileManager
  var nowMillis: () -> Int64

  init(
    metadataInspector: AgentIOSMediaMetadataInspecting = AgentIOSAVFoundationMediaMetadataInspector(),
    playbackOpener: AgentIOSMediaPlaybackOpening = AgentIOSUIKitMediaPlaybackOpener(),
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.metadataInspector = metadataInspector
    self.playbackOpener = playbackOpener
    self.fileManager = fileManager
    self.nowMillis = nowMillis
  }

  func availability(kind: AgentIOSMediaNativeToolKind) -> AgentNativeToolAvailability {
    switch kind {
    case .metadata:
      return metadataInspector.availability
    case .playback:
      return playbackOpener.availability
    case .transcode:
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "iOS signed FFmpeg media runtime is not connected"
      )
    }
  }

  func inspectMetadata(
    contentUri: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    do {
      let fileURL = try resolveReadableFileURL(contentUri)
      let didAccess = fileURL.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          fileURL.stopAccessingSecurityScopedResource()
        }
      }
      try validateReadableMediaFile(fileURL)
      let snapshot = try metadataInspector.inspect(fileURL: fileURL, contentUri: contentUri)
      return AgentNativeToolExecutionResult.success(
        output: snapshot.output(observedAtMillis: nowMillis()),
        message: "Selected media metadata inspected",
        metadata: [
          "media_implementation": .string(metadataInspector.implementationId),
          "media_provider": .string(implementationId),
          "content_scope": .string("security_scoped_file_url"),
          "metadata_backend": .string("avfoundation_imageio")
        ]
      )
    } catch let error as AgentIOSAVFoundationMediaProviderError {
      return error.executionResult
    } catch {
      return AgentIOSAVFoundationMediaProviderError.metadataUnavailable(error.localizedDescription).executionResult
    }
  }

  func handoffPlayback(
    contentUri: String,
    contentType: String,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    do {
      let fileURL = try resolveReadableFileURL(contentUri)
      let didAccess = fileURL.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          fileURL.stopAccessingSecurityScopedResource()
        }
      }
      try validateReadableMediaFile(fileURL)
      let opened = try playbackOpener.open(
        fileURL: fileURL,
        contentType: contentType.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      return AgentNativeToolExecutionResult.success(
        output: [
          "launched": .bool(opened.launched),
          "action": .string(opened.action),
          "handler_package": .string(opened.handlerPackage),
          "completed": .bool(false),
          "handed_off_at_epoch_ms": .int(max(0, nowMillis())),
          "source": .object(["content_uri": .string(contentUri)])
        ],
        message: "Media playback handed off to iOS",
        metadata: [
          "playback_implementation": .string(playbackOpener.implementationId),
          "media_provider": .string(implementationId),
          "completion_semantics": .string("handoff_only")
        ]
      )
    } catch let error as AgentIOSAVFoundationMediaProviderError {
      return error.executionResult
    } catch {
      return AgentIOSAVFoundationMediaProviderError.playbackUnavailable(error.localizedDescription).executionResult
    }
  }

  func transcode(
    request: AgentIOSMediaTranscodeRequest,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "ffmpeg_runtime_unavailable",
      message: "iOS signed FFmpeg media runtime is not connected",
      retryable: true
    )
  }

  private func resolveReadableFileURL(_ contentUri: String) throws -> URL {
    let trimmed = contentUri.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
      throw AgentIOSAVFoundationMediaProviderError.invalidContentUri
    }
    guard url.isFileURL else {
      throw AgentIOSAVFoundationMediaProviderError.unsupportedContentUri
    }
    return url.standardizedFileURL
  }

  private func validateReadableMediaFile(_ fileURL: URL) throws {
    guard fileURL.isFileURL else {
      throw AgentIOSAVFoundationMediaProviderError.invalidContentUri
    }
    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw AgentIOSAVFoundationMediaProviderError.mediaUnavailable
    }
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
    guard size >= 0 else {
      throw AgentIOSAVFoundationMediaProviderError.mediaUnavailable
    }
    guard size <= AgentIOSMediaNativeToolCatalog.maxMediaBytes else {
      throw AgentIOSAVFoundationMediaProviderError.mediaTooLarge
    }
  }
}

struct AgentIOSAVFoundationMediaMetadataInspector: AgentIOSMediaMetadataInspecting {
  var implementationId: String = "ios.avfoundation.imageio.metadata"

  var availability: AgentNativeToolAvailability {
    #if canImport(AVFoundation) && canImport(ImageIO) && canImport(CoreGraphics)
    return .available
    #else
    return AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "AVFoundation and ImageIO are required for iOS media metadata"
    )
    #endif
  }

  func inspect(fileURL: URL, contentUri: String) throws -> AgentIOSMediaMetadataSnapshot {
    #if canImport(AVFoundation) && canImport(ImageIO) && canImport(CoreGraphics)
    let resource = mediaResource(fileURL)
    let asset = AVURLAsset(url: fileURL)
    let audioTracks = asset.tracks(withMediaType: .audio)
    let videoTracks = asset.tracks(withMediaType: .video)
    let video = videoTracks.first.map(videoSnapshot)
    let image = videoTracks.isEmpty && audioTracks.isEmpty ? imageSnapshot(fileURL) : nil
    let hasAudio = !audioTracks.isEmpty
    let hasVideo = !videoTracks.isEmpty

    guard hasAudio || hasVideo || image != nil || isMediaHint(resource.contentType, fileURL) else {
      throw AgentIOSAVFoundationMediaProviderError.unsupportedMediaType
    }

    return AgentIOSMediaMetadataSnapshot(
      contentUri: contentUri,
      contentType: inferredContentType(
        resource.contentType,
        fileURL: fileURL,
        hasAudio: hasAudio,
        hasVideo: hasVideo,
        hasImage: image != nil
      ),
      displayName: resource.displayName,
      sizeBytes: resource.sizeBytes,
      durationMillis: durationMillis(asset.duration),
      width: video?.width ?? image?.width ?? 0,
      height: video?.height ?? image?.height ?? 0,
      rotationDegrees: video?.rotationDegrees ?? image?.rotationDegrees ?? 0,
      hasAudio: hasAudio,
      hasVideo: hasVideo
    )
    #else
    throw AgentIOSAVFoundationMediaProviderError.metadataUnavailable("AVFoundation and ImageIO are unavailable")
    #endif
  }

  #if canImport(AVFoundation) && canImport(ImageIO) && canImport(CoreGraphics)
  private struct ResourceSnapshot {
    var contentType: String
    var displayName: String
    var sizeBytes: Int64
  }

  private struct VisualSnapshot {
    var width: Int
    var height: Int
    var rotationDegrees: Int
  }

  private func mediaResource(_ fileURL: URL) -> ResourceSnapshot {
    let keys: Set<URLResourceKey> = [.localizedNameKey, .nameKey, .fileSizeKey, .contentTypeKey]
    let values = try? fileURL.resourceValues(forKeys: keys)
    let contentType = values?.contentType?.preferredMIMEType
      ?? UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
      ?? mimeTypeByExtension(fileURL.pathExtension)
    let displayName = (values?.localizedName ?? values?.name ?? fileURL.lastPathComponent).ifBlank("media")
    let size = Int64(values?.fileSize ?? -1)
    return ResourceSnapshot(
      contentType: contentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      displayName: String(displayName.prefix(1_024)),
      sizeBytes: size
    )
  }

  private func videoSnapshot(_ track: AVAssetTrack) -> VisualSnapshot {
    let natural = track.naturalSize
    let transformed = natural.applying(track.preferredTransform)
    return VisualSnapshot(
      width: boundedDimension(transformed.width == 0 ? natural.width : transformed.width),
      height: boundedDimension(transformed.height == 0 ? natural.height : transformed.height),
      rotationDegrees: rotationDegrees(track.preferredTransform)
    )
  }

  private func imageSnapshot(_ fileURL: URL) -> VisualSnapshot? {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
          let rawProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
      return nil
    }
    let width = number(rawProperties[kCGImagePropertyPixelWidth]).map { boundedDimension(CGFloat($0)) } ?? 0
    let height = number(rawProperties[kCGImagePropertyPixelHeight]).map { boundedDimension(CGFloat($0)) } ?? 0
    guard width > 0 || height > 0 else { return nil }
    let orientation = number(rawProperties[kCGImagePropertyOrientation]).map(Int.init) ?? 1
    return VisualSnapshot(
      width: width,
      height: height,
      rotationDegrees: imageRotationDegrees(orientation)
    )
  }

  private func durationMillis(_ duration: CMTime) -> Int64 {
    let seconds = duration.seconds
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return max(0, Int64((seconds * 1_000).rounded()))
  }

  private func inferredContentType(
    _ contentType: String,
    fileURL: URL,
    hasAudio: Bool,
    hasVideo: Bool,
    hasImage: Bool
  ) -> String {
    if !contentType.isBlank { return String(contentType.prefix(255)) }
    if let inferred = mimeTypeByExtension(fileURL.pathExtension).nonEmpty {
      return String(inferred.prefix(255))
    }
    if hasImage { return "image/*" }
    if hasVideo { return "video/*" }
    if hasAudio { return "audio/*" }
    return "application/octet-stream"
  }

  private func isMediaHint(_ contentType: String, _ fileURL: URL) -> Bool {
    if contentType.hasPrefix("image/") || contentType.hasPrefix("audio/") || contentType.hasPrefix("video/") {
      return true
    }
    guard let type = UTType(filenameExtension: fileURL.pathExtension) else {
      return false
    }
    return type.conforms(to: .image) || type.conforms(to: .audio) || type.conforms(to: .movie)
  }

  private func boundedDimension(_ value: CGFloat) -> Int {
    let rounded = Int(abs(value).rounded())
    return max(0, min(rounded, 65_535))
  }

  private func rotationDegrees(_ transform: CGAffineTransform) -> Int {
    let angle = atan2(Double(transform.b), Double(transform.a)) * 180 / .pi
    let rounded = Int(angle.rounded())
    return ((rounded % 360) + 360) % 360
  }

  private func imageRotationDegrees(_ orientation: Int) -> Int {
    switch orientation {
    case 3, 4:
      return 180
    case 5, 6:
      return 90
    case 7, 8:
      return 270
    default:
      return 0
    }
  }

  private func number(_ value: Any?) -> Int64? {
    switch value {
    case let value as NSNumber:
      return value.int64Value
    case let value as Int:
      return Int64(value)
    case let value as Int64:
      return value
    case let value as String:
      return Int64(value)
    default:
      return nil
    }
  }
  #endif

  private func mimeTypeByExtension(_ pathExtension: String) -> String {
    switch pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "gif":
      return "image/gif"
    case "heic":
      return "image/heic"
    case "mp4", "m4v":
      return "video/mp4"
    case "mov":
      return "video/quicktime"
    case "mp3":
      return "audio/mpeg"
    case "m4a":
      return "audio/mp4"
    case "wav":
      return "audio/wav"
    case "flac":
      return "audio/flac"
    default:
      return ""
    }
  }
}

struct AgentIOSUIKitMediaPlaybackOpener: AgentIOSMediaPlaybackOpening {
  var implementationId: String = "ios.uiapplication.open_url"

  var availability: AgentNativeToolAvailability {
    #if canImport(UIKit) && os(iOS)
    return .available
    #else
    return AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "UIKit UIApplication openURL is required for iOS media playback handoff"
    )
    #endif
  }

  func open(fileURL: URL, contentType: String) throws -> AgentIOSMediaPlaybackOpenResult {
    #if canImport(UIKit) && os(iOS)
    var canOpen = false
    let launch = {
      let application = UIApplication.shared
      canOpen = application.canOpenURL(fileURL)
      if canOpen {
        application.open(fileURL, options: [:], completionHandler: nil)
      }
    }
    if Thread.isMainThread {
      launch()
    } else {
      DispatchQueue.main.sync(execute: launch)
    }
    guard canOpen else {
      throw AgentIOSAVFoundationMediaProviderError.playbackUnavailable("No iOS media handler can open the selected file")
    }
    return AgentIOSMediaPlaybackOpenResult(
      launched: true,
      action: "ios.media.open",
      handlerPackage: "com.apple.UIKit"
    )
    #else
    throw AgentIOSAVFoundationMediaProviderError.playbackUnavailable("UIKit UIApplication openURL is unavailable")
    #endif
  }
}

enum AgentIOSAVFoundationMediaProviderError: LocalizedError, Equatable {
  case invalidContentUri
  case unsupportedContentUri
  case mediaUnavailable
  case mediaTooLarge
  case unsupportedMediaType
  case metadataUnavailable(String)
  case playbackUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .invalidContentUri:
      return "Media content_uri must be a valid file URL"
    case .unsupportedContentUri:
      return "iOS media tools require a security-scoped file:// URL"
    case .mediaUnavailable:
      return "The selected media file is unavailable"
    case .mediaTooLarge:
      return "The selected media exceeds the 256 MB limit"
    case .unsupportedMediaType:
      return "The selected file is not a supported image, audio, or video media item"
    case .metadataUnavailable(let message), .playbackUnavailable(let message):
      return message
    }
  }

  var executionResult: AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: code,
      message: errorDescription ?? "iOS media provider failed",
      retryable: retryable
    )
  }

  private var code: String {
    switch self {
    case .invalidContentUri:
      return "invalid_content_uri"
    case .unsupportedContentUri:
      return "unsupported_content_uri"
    case .mediaUnavailable:
      return "media_unavailable"
    case .mediaTooLarge:
      return "media_too_large"
    case .unsupportedMediaType:
      return "unsupported_media_type"
    case .metadataUnavailable:
      return "metadata_unavailable"
    case .playbackUnavailable:
      return "playback_unavailable"
    }
  }

  private var retryable: Bool {
    switch self {
    case .mediaUnavailable, .metadataUnavailable, .playbackUnavailable:
      return true
    case .invalidContentUri, .unsupportedContentUri, .mediaTooLarge, .unsupportedMediaType:
      return false
    }
  }
}
