import CryptoKit
import Foundation

enum AgentIOSMediaTargetFormat: String, Codable, CaseIterable, Identifiable {
  case mp4
  case m4a
  case wav
  case flac
  case gif
  case png
  case jpg

  var id: String { rawValue }
  var wireValue: String { rawValue }
  var fileExtension: String { rawValue }

  var mimeType: String {
    switch self {
    case .mp4:
      return "video/mp4"
    case .m4a:
      return "audio/mp4"
    case .wav:
      return "audio/wav"
    case .flac:
      return "audio/flac"
    case .gif:
      return "image/gif"
    case .png:
      return "image/png"
    case .jpg:
      return "image/jpeg"
    }
  }

  static func fromWireValue(_ value: String) -> AgentIOSMediaTargetFormat? {
    Self(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }
}

enum AgentIOSMediaTranscodePreset: String, Codable, CaseIterable, Identifiable {
  case compact
  case balanced
  case highQuality = "high_quality"

  var id: String { rawValue }
  var wireValue: String { rawValue }

  static func fromWireValue(_ value: String) -> AgentIOSMediaTranscodePreset? {
    Self(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }
}

struct AgentIOSFfmpegTranscodePlan: Equatable {
  var sourcePath: String
  var destinationPath: String
  var arguments: [String]
}

enum AgentIOSFfmpegTranscodePlanner {
  static func create(request: AgentIOSMediaTranscodeRequest) throws -> AgentIOSFfmpegTranscodePlan {
    guard let targetFormat = AgentIOSMediaTargetFormat.fromWireValue(request.targetFormat) else {
      throw AgentIOSFfmpegTranscodePlannerError.invalidTargetFormat
    }
    let destinationPath = request.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? defaultDestination(invocationId: request.invocationId, targetFormat: targetFormat)
      : request.destinationPath
    return try create(request: request, sourcePath: request.sourcePath, destinationPath: destinationPath)
  }

  static func create(
    request: AgentIOSMediaTranscodeRequest,
    sourcePath: String,
    destinationPath: String
  ) throws -> AgentIOSFfmpegTranscodePlan {
    guard let targetFormat = AgentIOSMediaTargetFormat.fromWireValue(request.targetFormat) else {
      throw AgentIOSFfmpegTranscodePlannerError.invalidTargetFormat
    }
    let source = try AgentIOSMediaWorkspacePaths.normalizeRelative(sourcePath, field: "source_path")
    let destination = try AgentIOSMediaWorkspacePaths.normalizeRelative(destinationPath, field: "destination_path")
    guard source != destination else {
      throw AgentIOSFfmpegTranscodePlannerError.invalidPath("Source and destination paths must be different")
    }
    guard destination.lowercased().hasSuffix(".\(targetFormat.fileExtension)") else {
      throw AgentIOSFfmpegTranscodePlannerError.extensionMismatch(targetFormat.wireValue)
    }
    guard request.startMillis >= 0 && request.startMillis <= maxMediaTimeMillis else {
      throw AgentIOSFfmpegTranscodePlannerError.outOfRange("Start time is outside the allowed range")
    }
    guard request.durationMillis >= 0 && request.durationMillis <= maxMediaTimeMillis else {
      throw AgentIOSFfmpegTranscodePlannerError.outOfRange("Duration is outside the allowed range")
    }
    guard request.maxWidth >= 0 && request.maxWidth <= maxDimension else {
      throw AgentIOSFfmpegTranscodePlannerError.outOfRange("Maximum width is outside the allowed range")
    }
    guard request.maxHeight >= 0 && request.maxHeight <= maxDimension else {
      throw AgentIOSFfmpegTranscodePlannerError.outOfRange("Maximum height is outside the allowed range")
    }
    guard request.audioBitrateKbps == 0 ||
      (request.audioBitrateKbps >= minAudioBitrate && request.audioBitrateKbps <= maxAudioBitrate) else {
      throw AgentIOSFfmpegTranscodePlannerError.outOfRange("Audio bitrate is outside the allowed range")
    }

    var arguments = ["-hide_banner", "-loglevel", "error", "-y"]
    if request.startMillis > 0 {
      arguments += ["-ss", seconds(request.startMillis)]
    }
    arguments += ["-i", "./\(source)"]
    if request.durationMillis > 0 {
      arguments += ["-t", seconds(request.durationMillis)]
    }
    arguments += ["-map_metadata", "-1", "-sn", "-dn", "-threads", "2"]

    switch targetFormat {
    case .mp4:
      addMp4(&arguments, request: request)
    case .m4a:
      addM4a(&arguments, request: request)
    case .wav:
      arguments += ["-map", "0:a:0", "-vn", "-c:a", "pcm_s16le"]
    case .flac:
      arguments += [
        "-map", "0:a:0",
        "-vn",
        "-c:a", "flac",
        "-compression_level", request.presetValue == .balanced ? "5" : "8"
      ]
    case .gif:
      addGif(&arguments, request: request)
    case .png:
      addStillImage(&arguments, request: request, codec: "png", quality: "2")
    case .jpg:
      addStillImage(
        &arguments,
        request: request,
        codec: "mjpeg",
        quality: request.presetValue == .compact ? "7" : request.presetValue == .balanced ? "4" : "2"
      )
    }
    arguments.append("./\(destination)")
    return AgentIOSFfmpegTranscodePlan(sourcePath: source, destinationPath: destination, arguments: arguments)
  }

  static func defaultDestination(
    invocationId: String,
    targetFormat: AgentIOSMediaTargetFormat
  ) -> String {
    let digest = SHA256.hash(data: Data(invocationId.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return "outputs/media-\(digest.prefix(16)).\(targetFormat.fileExtension)"
  }

  private static func addMp4(_ arguments: inout [String], request: AgentIOSMediaTranscodeRequest) {
    let bounds = effectiveVideoBounds(request)
    arguments += [
      "-map", "0:v:0?",
      "-map", "0:a:0?",
      "-vf", videoScaleFilter(width: bounds.width, height: bounds.height, pixelFormat: "yuv420p"),
      "-c:v", "mpeg4",
      "-q:v", request.presetValue == .compact ? "8" : request.presetValue == .balanced ? "5" : "2",
      "-c:a", "aac",
      "-b:a", "\(audioBitrate(request))k",
      "-movflags", "+faststart"
    ]
  }

  private static func addM4a(_ arguments: inout [String], request: AgentIOSMediaTranscodeRequest) {
    arguments += [
      "-map", "0:a:0",
      "-vn",
      "-c:a", "aac",
      "-b:a", "\(audioBitrate(request))k",
      "-movflags", "+faststart"
    ]
  }

  private static func addGif(_ arguments: inout [String], request: AgentIOSMediaTranscodeRequest) {
    let defaultBound: Int
    let fps: Int
    switch request.presetValue {
    case .compact:
      defaultBound = 640
      fps = 8
    case .balanced:
      defaultBound = 960
      fps = 12
    case .highQuality:
      defaultBound = 1_280
      fps = 15
    }
    let width = request.maxWidth > 0 ? request.maxWidth : defaultBound
    let height = request.maxHeight > 0 ? request.maxHeight : defaultBound
    arguments += [
      "-map", "0:v:0",
      "-an",
      "-vf", "fps=\(fps),\(videoScaleFilter(width: width, height: height))",
      "-loop", "0"
    ]
  }

  private static func addStillImage(
    _ arguments: inout [String],
    request: AgentIOSMediaTranscodeRequest,
    codec: String,
    quality: String
  ) {
    arguments += ["-map", "0:v:0", "-an", "-frames:v", "1", "-c:v", codec]
    if let filter = imageScaleFilter(width: request.maxWidth, height: request.maxHeight) {
      arguments += ["-vf", filter]
    }
    if codec == "mjpeg" {
      arguments += ["-q:v", quality]
    }
  }

  private static func effectiveVideoBounds(_ request: AgentIOSMediaTranscodeRequest) -> (width: Int, height: Int) {
    if request.maxWidth > 0 || request.maxHeight > 0 {
      return (request.maxWidth, request.maxHeight)
    }
    switch request.presetValue {
    case .compact:
      return (1_280, 720)
    case .balanced:
      return (1_920, 1_080)
    case .highQuality:
      return (0, 0)
    }
  }

  private static func audioBitrate(_ request: AgentIOSMediaTranscodeRequest) -> Int {
    if request.audioBitrateKbps > 0 {
      return request.audioBitrateKbps
    }
    switch request.presetValue {
    case .compact:
      return 96
    case .balanced:
      return 160
    case .highQuality:
      return 256
    }
  }

  private static func videoScaleFilter(width: Int, height: Int, pixelFormat: String = "") -> String {
    let scale: String
    if width > 0 && height > 0 {
      scale = "scale=w='min(\(width),iw)':h='min(\(height),ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"
    } else if width > 0 {
      scale = "scale=w='min(\(width),iw)':h=-2"
    } else if height > 0 {
      scale = "scale=w=-2:h='min(\(height),ih)'"
    } else {
      scale = "scale=w='trunc(iw/2)*2':h='trunc(ih/2)*2'"
    }
    return pixelFormat.isEmpty ? scale : "\(scale),format=\(pixelFormat)"
  }

  private static func imageScaleFilter(width: Int, height: Int) -> String? {
    if width > 0 && height > 0 {
      return "scale=w='min(\(width),iw)':h='min(\(height),ih)':force_original_aspect_ratio=decrease"
    }
    if width > 0 {
      return "scale=w='min(\(width),iw)':h=-1"
    }
    if height > 0 {
      return "scale=w=-1:h='min(\(height),ih)'"
    }
    return nil
  }

  private static func seconds(_ milliseconds: Int64) -> String {
    let whole = milliseconds / 1_000
    let remainder = milliseconds % 1_000
    guard remainder != 0 else {
      return "\(whole)"
    }
    var fraction = "\(remainder)"
    while fraction.count < 3 {
      fraction = "0\(fraction)"
    }
    while fraction.last == Character("0") {
      fraction.removeLast()
    }
    return "\(whole).\(fraction)"
  }

  private static let maxMediaTimeMillis: Int64 = 6 * 60 * 60 * 1_000
  private static let maxDimension = 8_192
  private static let minAudioBitrate = 32
  private static let maxAudioBitrate = 512
}

enum AgentIOSMediaWorkspacePaths {
  static func normalizeRelative(_ value: String, field: String) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\", with: "/")
    guard !normalized.isEmpty,
          normalized.count <= maxPathCharacters,
          !normalized.hasPrefix("/"),
          !normalized.hasPrefix("~"),
          !normalized.contains(":") else {
      throw AgentIOSFfmpegTranscodePlannerError.invalidPath("\(field) is invalid")
    }
    guard normalized.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
      throw AgentIOSFfmpegTranscodePlannerError.invalidPath("\(field) contains control characters")
    }
    let segments = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AgentIOSFfmpegTranscodePlannerError.invalidPath("\(field) is unsafe")
    }
    guard let root = segments.first?.lowercased(), !reservedRootNames.contains(root) else {
      throw AgentIOSFfmpegTranscodePlannerError.invalidPath("\(field) uses a reserved runtime path")
    }
    return normalized
  }

  private static let maxPathCharacters = 1_024
  private static let reservedRootNames: Set<String> = [
    ".galaxyssi-tools",
    ".tmp",
    "request.json",
    "status.json",
    "main.ffmpeg.json",
    "main.ffprobe.json"
  ]
}

enum AgentIOSFfmpegTranscodePlannerError: LocalizedError, Equatable {
  case invalidTargetFormat
  case invalidPath(String)
  case extensionMismatch(String)
  case outOfRange(String)

  var errorDescription: String? {
    switch self {
    case .invalidTargetFormat:
      return "Target media format is invalid"
    case .invalidPath(let detail), .outOfRange(let detail):
      return detail
    case .extensionMismatch(let format):
      return "Destination extension must match \(format)"
    }
  }
}

private extension AgentIOSMediaTranscodeRequest {
  var presetValue: AgentIOSMediaTranscodePreset {
    AgentIOSMediaTranscodePreset.fromWireValue(preset) ?? .balanced
  }
}
