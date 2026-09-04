import CryptoKit
import Foundation

enum VoiceWhisperBenchmarkAudioLoaderError: LocalizedError, Equatable {
  case resourceMissing(String)
  case checksumMismatch(expected: String, actual: String)
  case invalidWave
  case unsupportedFormat
  case missingData

  var errorDescription: String? {
    switch self {
    case .resourceMissing(let name):
      return "Whisper benchmark audio resource is missing: \(name)"
    case .checksumMismatch:
      return "Whisper benchmark audio checksum mismatch."
    case .invalidWave:
      return "Whisper benchmark audio is not a valid RIFF/WAVE file."
    case .unsupportedFormat:
      return "Whisper benchmark audio must be PCM16."
    case .missingData:
      return "Whisper benchmark audio has no data chunk."
    }
  }
}

enum VoiceWhisperBenchmarkAudioLoader {
  static let defaultResourceName = "zh_cn_v1"
  static let defaultResourceExtension = "wav"
  static let defaultResourceSubdirectory = "voice/benchmark"

  static func loadBundled(
    bundle: Bundle = .main,
    resourceName: String = defaultResourceName,
    fileExtension: String = defaultResourceExtension,
    subdirectory: String? = defaultResourceSubdirectory,
    version: String = VoiceWhisperBenchmarkManager.benchmarkAudioVersion,
    expectedSHA256: String = VoiceWhisperBenchmarkManager.benchmarkAudioSHA256,
    expectedTokens: Set<String> = defaultExpectedTokens,
    language: String = "zh"
  ) throws -> VoiceWhisperBenchmarkAudio {
    guard let fileURL = bundle.url(
      forResource: resourceName,
      withExtension: fileExtension,
      subdirectory: subdirectory
    ) ?? bundle.url(
      forResource: resourceName,
      withExtension: fileExtension
    ) else {
      let resourcePath = [subdirectory, "\(resourceName).\(fileExtension)"]
        .compactMap { $0 }
        .joined(separator: "/")
      throw VoiceWhisperBenchmarkAudioLoaderError.resourceMissing(resourcePath)
    }
    return try load(
      fileURL: fileURL,
      version: version,
      expectedSHA256: expectedSHA256,
      expectedTokens: expectedTokens,
      language: language
    )
  }

  static func load(
    fileURL: URL,
    version: String,
    expectedSHA256: String? = nil,
    expectedTokens: Set<String>,
    language: String = "zh"
  ) throws -> VoiceWhisperBenchmarkAudio {
    let data = try Data(contentsOf: fileURL)
    let actualSHA256 = sha256(data)
    let expected = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if !expected.isEmpty, expected != actualSHA256 {
      throw VoiceWhisperBenchmarkAudioLoaderError.checksumMismatch(
        expected: expected,
        actual: actualSHA256
      )
    }
    return try VoiceWhisperBenchmarkAudio(
      version: "\(version.trimmingCharacters(in: .whitespacesAndNewlines)):\(String(actualSHA256.prefix(16)))",
      pcm16: decodePcmWave(data),
      expectedTokens: expectedTokens,
      language: language
    )
  }

  static func decodePcmWave(_ data: Data) throws -> [Int16] {
    let bytes = [UInt8](data)
    guard bytes.count >= 44,
          ascii(bytes, offset: 0, count: 4) == "RIFF",
          ascii(bytes, offset: 8, count: 4) == "WAVE" else {
      throw VoiceWhisperBenchmarkAudioLoaderError.invalidWave
    }

    var offset = 12
    var sampleRate = 0
    var channels = 0
    var bitsPerSample = 0
    var audioFormat = 0
    var pcmBytes: [UInt8]?

    while offset + 8 <= bytes.count {
      guard let chunkId = ascii(bytes, offset: offset, count: 4),
            let chunkSize = int32LittleEndian(bytes, offset: offset + 4) else {
        throw VoiceWhisperBenchmarkAudioLoaderError.invalidWave
      }
      let cleanChunkSize = max(chunkSize, 0)
      let payloadOffset = offset + 8
      let payloadEnd = payloadOffset + cleanChunkSize
      guard payloadEnd <= bytes.count else {
        throw VoiceWhisperBenchmarkAudioLoaderError.invalidWave
      }

      if chunkId == "fmt ", cleanChunkSize >= 16 {
        audioFormat = int16LittleEndian(bytes, offset: payloadOffset) ?? 0
        channels = int16LittleEndian(bytes, offset: payloadOffset + 2) ?? 0
        sampleRate = int32LittleEndian(bytes, offset: payloadOffset + 4) ?? 0
        bitsPerSample = int16LittleEndian(bytes, offset: payloadOffset + 14) ?? 0
      } else if chunkId == "data" {
        pcmBytes = Array(bytes[payloadOffset..<payloadEnd])
      }
      offset = payloadEnd + (cleanChunkSize & 1)
    }

    guard audioFormat == 1, bitsPerSample == 16 else {
      throw VoiceWhisperBenchmarkAudioLoaderError.unsupportedFormat
    }
    guard sampleRate > 0, channels > 0 else {
      throw VoiceWhisperBenchmarkAudioLoaderError.invalidWave
    }
    guard let pcmBytes else {
      throw VoiceWhisperBenchmarkAudioLoaderError.missingData
    }
    return resamplePcm16(bytes: pcmBytes, sourceRate: sampleRate, channels: channels)
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func resamplePcm16(bytes: [UInt8], sourceRate: Int, channels: Int) -> [Int16] {
    let samplesPerFrame = max(channels, 1)
    let frames = bytes.count / 2 / samplesPerFrame
    guard frames > 0 else {
      return []
    }
    let mono = (0..<frames).map { frame -> Int16 in
      var sum = 0
      for channel in 0..<samplesPerFrame {
        sum += Int(sample(bytes, index: frame * samplesPerFrame + channel))
      }
      return Int16(clamping: sum / samplesPerFrame)
    }
    guard sourceRate != VoiceWhisperBenchmarkAudio.sampleRateHz else {
      return mono
    }
    let outputSize = max(frames * VoiceWhisperBenchmarkAudio.sampleRateHz / max(sourceRate, 1), 1)
    return (0..<outputSize).map { index -> Int16 in
      let source = Double(index) * Double(sourceRate) / Double(VoiceWhisperBenchmarkAudio.sampleRateHz)
      let left = min(max(Int(floor(source)), 0), mono.count - 1)
      let right = min(left + 1, mono.count - 1)
      let fraction = source - Double(left)
      let interpolated = Double(mono[left]) + (Double(mono[right]) - Double(mono[left])) * fraction
      return Int16(clamping: Int(interpolated.rounded()))
    }
  }

  private static func sample(_ bytes: [UInt8], index: Int) -> Int16 {
    let offset = index * 2
    guard offset + 1 < bytes.count else {
      return 0
    }
    let raw = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    return Int16(bitPattern: raw)
  }

  private static func ascii(_ bytes: [UInt8], offset: Int, count: Int) -> String? {
    guard offset >= 0, count >= 0, offset + count <= bytes.count else {
      return nil
    }
    return String(bytes: bytes[offset..<(offset + count)], encoding: .ascii)
  }

  private static func int16LittleEndian(_ bytes: [UInt8], offset: Int) -> Int? {
    guard offset >= 0, offset + 1 < bytes.count else {
      return nil
    }
    return Int(UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
  }

  private static func int32LittleEndian(_ bytes: [UInt8], offset: Int) -> Int? {
    guard offset >= 0, offset + 3 < bytes.count else {
      return nil
    }
    let raw = UInt32(bytes[offset]) |
      (UInt32(bytes[offset + 1]) << 8) |
      (UInt32(bytes[offset + 2]) << 16) |
      (UInt32(bytes[offset + 3]) << 24)
    return raw > UInt32(Int32.max) ? Int(Int32.max) : Int(raw)
  }

  private static let defaultExpectedTokens: Set<String> = [
    "\u{4f60}\u{597d}",
    "\u{672c}\u{5730}",
    "\u{8bed}\u{97f3}",
    "\u{6d4b}\u{8bd5}",
    "\u{6027}\u{80fd}",
    "\u{5185}\u{5b58}",
    "\u{6e29}\u{5ea6}",
    "\u{53d6}\u{6d88}"
  ]
}
