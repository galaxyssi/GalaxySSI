import Foundation

struct VoiceWhisperAudio: Equatable {
  var samples: [Float]
  var sampleRateHz: Int
  var sourceSampleRateHz: Int
  var channelCount: Int

  var durationMs: Int64 {
    guard sampleRateHz > 0 else { return 0 }
    return Int64(samples.count) * 1_000 / Int64(sampleRateHz)
  }

  mutating func wipeSensitive() {
    for index in samples.indices { samples[index] = 0 }
    samples.removeAll(keepingCapacity: false)
  }
}

enum VoiceWhisperAudioDecodeError: LocalizedError, Equatable {
  case unsupportedFormat
  case invalidWaveHeader
  case unsupportedWaveEncoding
  case missingWaveData
  case emptyAudio

  var errorDescription: String? {
    switch self {
    case .unsupportedFormat:
      return "Only PCM16 wave audio is supported by the iOS local Whisper foundation decoder."
    case .invalidWaveHeader:
      return "The wave audio header is invalid."
    case .unsupportedWaveEncoding:
      return "Only PCM16 wave audio is supported."
    case .missingWaveData:
      return "The wave audio data chunk is missing."
    case .emptyAudio:
      return "Decoded audio is empty."
    }
  }
}

protocol VoiceWhisperAudioDecoding {
  func decode(fileURL: URL) throws -> VoiceWhisperAudio
  func decodePcmWave(_ data: Data) throws -> VoiceWhisperAudio
}

struct VoiceWhisperAudioDecoder: VoiceWhisperAudioDecoding {
  let targetSampleRateHz: Int

  init(targetSampleRateHz: Int = 16_000) {
    self.targetSampleRateHz = max(1, targetSampleRateHz)
  }

  func decode(fileURL: URL) throws -> VoiceWhisperAudio {
    guard fileURL.pathExtension.caseInsensitiveCompare("wav") == .orderedSame else {
      throw VoiceWhisperAudioDecodeError.unsupportedFormat
    }
    return try decodePcmWave(Data(contentsOf: fileURL))
  }

  func decodePcmWave(_ data: Data) throws -> VoiceWhisperAudio {
    guard data.count >= 44,
          data.asciiString(in: 0..<4) == "RIFF",
          data.asciiString(in: 8..<12) == "WAVE" else {
      throw VoiceWhisperAudioDecodeError.invalidWaveHeader
    }
    var offset = 12
    var audioFormat = 0
    var channels = 0
    var sampleRate = 0
    var bitsPerSample = 0
    var pcmRange: Range<Int>?
    while offset + 8 <= data.count {
      let chunkId = data.asciiString(in: offset..<(offset + 4))
      let chunkSize = Int(data.leUInt32(at: offset + 4))
      let payloadOffset = offset + 8
      guard payloadOffset + chunkSize <= data.count else { break }
      switch chunkId {
      case "fmt ":
        if chunkSize >= 16 {
          audioFormat = Int(data.leUInt16(at: payloadOffset))
          channels = Int(data.leUInt16(at: payloadOffset + 2))
          sampleRate = Int(data.leUInt32(at: payloadOffset + 4))
          bitsPerSample = Int(data.leUInt16(at: payloadOffset + 14))
        }
      case "data":
        pcmRange = payloadOffset..<(payloadOffset + chunkSize)
      default:
        break
      }
      offset = payloadOffset + chunkSize + (chunkSize % 2)
    }
    guard audioFormat == 1, bitsPerSample == 16, sampleRate > 0, channels > 0 else {
      throw VoiceWhisperAudioDecodeError.unsupportedWaveEncoding
    }
    guard let pcmRange = pcmRange else {
      throw VoiceWhisperAudioDecodeError.missingWaveData
    }
    let mono = monoPcm16Samples(data[pcmRange], channels: channels)
    guard !mono.isEmpty else {
      throw VoiceWhisperAudioDecodeError.emptyAudio
    }
    let samples = resample(mono, sourceRateHz: sampleRate, targetRateHz: targetSampleRateHz)
    return VoiceWhisperAudio(
      samples: samples,
      sampleRateHz: targetSampleRateHz,
      sourceSampleRateHz: sampleRate,
      channelCount: channels
    )
  }

  private func monoPcm16Samples(_ data: Data.SubSequence, channels: Int) -> [Float] {
    var bytes = Array(data)
    defer {
      for index in bytes.indices { bytes[index] = 0 }
      bytes.removeAll(keepingCapacity: false)
    }
    let shorts = bytes.count / 2
    let frames = shorts / max(1, channels)
    guard frames > 0 else { return [] }
    return (0..<frames).map { frame in
      var sum: Float = 0
      for channel in 0..<channels {
        let sampleIndex = (frame * channels + channel) * 2
        let raw = UInt16(bytes[sampleIndex]) | (UInt16(bytes[sampleIndex + 1]) << 8)
        sum += Float(Int16(bitPattern: raw)) / 32_768.0
      }
      return sum / Float(channels)
    }
  }

  private func resample(
    _ mono: [Float],
    sourceRateHz: Int,
    targetRateHz: Int
  ) -> [Float] {
    guard !mono.isEmpty, sourceRateHz > 0, targetRateHz > 0 else { return [] }
    guard sourceRateHz != targetRateHz else { return mono }
    let outputSize = max(1, Int(Int64(mono.count) * Int64(targetRateHz) / Int64(sourceRateHz)))
    return (0..<outputSize).map { index in
      let source = Double(index) * Double(sourceRateHz) / Double(targetRateHz)
      let left = min(max(Int(floor(source)), 0), mono.count - 1)
      let right = min(left + 1, mono.count - 1)
      let fraction = Float(source - Double(left))
      return mono[left] + (mono[right] - mono[left]) * fraction
    }
  }
}

private extension Data {
  func asciiString(in range: Range<Int>) -> String {
    guard range.lowerBound >= 0, range.upperBound <= count else { return "" }
    return String(bytes: self[range], encoding: .ascii) ?? ""
  }

  func leUInt16(at offset: Int) -> UInt16 {
    guard offset + 1 < count else { return 0 }
    return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
  }

  func leUInt32(at offset: Int) -> UInt32 {
    guard offset + 3 < count else { return 0 }
    return UInt32(self[offset]) |
      (UInt32(self[offset + 1]) << 8) |
      (UInt32(self[offset + 2]) << 16) |
      (UInt32(self[offset + 3]) << 24)
  }
}
