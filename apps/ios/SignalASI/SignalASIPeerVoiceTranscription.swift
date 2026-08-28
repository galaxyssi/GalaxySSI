import AudioToolbox
import Foundation

enum SignalASIPeerMessageAction: Equatable {
  case copy
  case transcribe
  case delete
}

struct SignalASIPeerVoiceAttachment: Equatable {
  var displayName: String
  var mimeType: String
  var fileExtension: String
  var sourceURL: URL?
  var storage: String
  var encryptionPurpose: String

  static func decode(from message: ChatMessage) -> SignalASIPeerVoiceAttachment? {
    AgentRichContentCodec.decode(message.richOutputJson)
      .first(where: {
        $0.type == .audio &&
          $0.metadata["source"] == "peer_message"
      })
      .map { block in
        let titleExtension = (block.title as NSString).pathExtension.lowercased()
        let metadataExtension = block.metadata["display_extension"]?
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
        return SignalASIPeerVoiceAttachment(
          displayName: block.title,
          mimeType: block.mimeType,
          fileExtension: metadataExtension?.ifBlank(titleExtension) ?? titleExtension,
          sourceURL: URL(string: block.uri),
          storage: block.metadata["storage"] ?? "",
          encryptionPurpose: block.metadata["encryption_purpose"] ?? ""
        )
      }
  }

  func loadSensitiveData() throws -> Data {
    if storage == "attachment_aes_256_gcm",
       !encryptionPurpose.isBlank,
       let sourceURL,
       sourceURL.isFileURL {
      return try SignalASIAttachmentAtRestCipher.shared.read(
        from: sourceURL,
        purpose: encryptionPurpose
      )
    }
    guard let data = SignalASIPeerMessageAttachmentStore().resolveAudioData(
      displayName: displayName,
      sourceURL: sourceURL
    ), !data.isEmpty else {
      throw SignalASIPeerVoiceTranscriptionError.audioUnavailable
    }
    return data
  }
}

enum SignalASIPeerMessageActionPolicy {
  static func voiceAttachment(in message: ChatMessage) -> SignalASIPeerVoiceAttachment? {
    SignalASIPeerVoiceAttachment.decode(from: message)
  }

  static func actions(for message: ChatMessage) -> [SignalASIPeerMessageAction] {
    voiceAttachment(in: message) == nil
      ? [.copy, .delete]
      : [.transcribe, .delete]
  }

  static func returnsTextWithoutCommandExecution() -> Bool { true }
}

enum SignalASIPeerVoiceTranscriptionError: LocalizedError, Equatable {
  case audioUnavailable
  case unsupportedAudioFormat(String)
  case audioDecodeFailed(Int32)
  case emptyTranscript
  case busy

  var errorDescription: String? {
    switch self {
    case .audioUnavailable:
      return "Voice message audio is unavailable."
    case .unsupportedAudioFormat(let fileExtension):
      return "The voice message format cannot be transcribed: \(fileExtension.ifBlank("unknown"))."
    case .audioDecodeFailed(let status):
      return "The voice message could not be decoded (\(status))."
    case .emptyTranscript:
      return "The local speech model did not return any text."
    case .busy:
      return "Another voice message is already being transcribed."
    }
  }
}

actor SignalASIPeerVoiceTranscriber {
  static let shared = SignalASIPeerVoiceTranscriber()

  private let asr: VoiceLocalWhisperASR
  private var busy = false

  init(
    asr: VoiceLocalWhisperASR = VoiceLocalWhisperASR(
      runtime: DefaultVoiceLocalWhisperRuntime()
    )
  ) {
    self.asr = asr
  }

  func transcribe(
    message: ChatMessage,
    settings: VoiceSettings
  ) async throws -> String {
    guard !busy else { throw SignalASIPeerVoiceTranscriptionError.busy }
    busy = true
    defer { busy = false }

    guard let attachment = SignalASIPeerMessageActionPolicy.voiceAttachment(in: message) else {
      throw SignalASIPeerVoiceTranscriptionError.audioUnavailable
    }
    var encodedAudio = try attachment.loadSensitiveData()
    defer { encodedAudio.wipeSensitive() }
    var decodedAudio = try SignalASIPeerVoiceInMemoryDecoder.decode(
      encodedAudio,
      fileExtension: attachment.fileExtension,
      mimeType: attachment.mimeType
    )
    defer { decodedAudio.wipeSensitive() }

    let result = try await asr.transcribe(
      decodedAudio: decodedAudio,
      settings: settings,
      language: settings.preferredLocaleIdentifier,
      traceId: "peer-voice-\(message.id.uuidString.lowercased())"
    )
    let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !transcript.isEmpty else {
      throw SignalASIPeerVoiceTranscriptionError.emptyTranscript
    }
    return transcript
  }
}

enum SignalASIPeerVoiceInMemoryDecoder {
  static func decode(
    _ data: Data,
    fileExtension: String,
    mimeType: String
  ) throws -> VoiceWhisperAudio {
    let normalizedExtension = fileExtension.lowercased()
    let normalizedMimeType = mimeType.lowercased()
    if normalizedExtension == "opus" ||
       normalizedMimeType.contains("audio/ogg") ||
       normalizedMimeType.contains("opus") {
      var wave = try SignalASIPeerVoiceOpusPlayback.pcmWaveData(fromOggOpus: data)
      defer { wave.wipeSensitive() }
      return try VoiceWhisperAudioDecoder().decodePcmWave(wave)
    }
    if normalizedExtension == "wav" || normalizedMimeType.contains("audio/wav") {
      return try VoiceWhisperAudioDecoder().decodePcmWave(data)
    }
    if ["m4a", "aac", "mp4", "caf"].contains(normalizedExtension) ||
       normalizedMimeType.contains("audio/mp4") ||
       normalizedMimeType.contains("audio/aac") {
      return try SignalASIAppleInMemoryAudioDecoder.decode(
        data,
        fileExtension: normalizedExtension
      )
    }
    throw SignalASIPeerVoiceTranscriptionError.unsupportedAudioFormat(normalizedExtension)
  }
}

private final class SignalASIInMemoryAudioReader {
  var data: Data

  init(data: Data) {
    self.data = data
  }

  deinit {
    data.wipeSensitive()
  }
}

private enum SignalASIAppleInMemoryAudioDecoder {
  private static let targetSampleRateHz = 16_000
  private static let readCallback: AudioFile_ReadProc = {
    clientData,
    position,
    requestCount,
    buffer,
    actualCount
    in
    let reader = Unmanaged<SignalASIInMemoryAudioReader>
      .fromOpaque(clientData)
      .takeUnretainedValue()
    let offset = max(0, Int(position))
    guard offset < reader.data.count else {
      actualCount.pointee = 0
      return noErr
    }
    let count = min(Int(requestCount), reader.data.count - offset)
    let target = UnsafeMutableBufferPointer(
      start: buffer.assumingMemoryBound(to: UInt8.self),
      count: count
    )
    reader.data.copyBytes(to: target, from: offset..<(offset + count))
    actualCount.pointee = UInt32(count)
    return noErr
  }

  private static let sizeCallback: AudioFile_GetSizeProc = { clientData in
    let reader = Unmanaged<SignalASIInMemoryAudioReader>
      .fromOpaque(clientData)
      .takeUnretainedValue()
    return Int64(reader.data.count)
  }

  static func decode(_ source: Data, fileExtension: String) throws -> VoiceWhisperAudio {
    let reader = SignalASIInMemoryAudioReader(data: source)
    let context = Unmanaged.passUnretained(reader).toOpaque()
    var audioFile: AudioFileID?
    let openStatus = AudioFileOpenWithCallbacks(
      context,
      readCallback,
      nil,
      sizeCallback,
      nil,
      fileTypeHint(fileExtension),
      &audioFile
    )
    guard openStatus == noErr, let audioFile else {
      throw SignalASIPeerVoiceTranscriptionError.audioDecodeFailed(openStatus)
    }
    defer { AudioFileClose(audioFile) }

    var extendedFile: ExtAudioFileRef?
    let wrapStatus = ExtAudioFileWrapAudioFileID(audioFile, false, &extendedFile)
    guard wrapStatus == noErr, let extendedFile else {
      throw SignalASIPeerVoiceTranscriptionError.audioDecodeFailed(wrapStatus)
    }
    defer { ExtAudioFileDispose(extendedFile) }

    var sourceFormat = AudioStreamBasicDescription()
    var sourceFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let sourceStatus = ExtAudioFileGetProperty(
      extendedFile,
      kExtAudioFileProperty_FileDataFormat,
      &sourceFormatSize,
      &sourceFormat
    )
    guard sourceStatus == noErr else {
      throw SignalASIPeerVoiceTranscriptionError.audioDecodeFailed(sourceStatus)
    }

    var clientFormat = AudioStreamBasicDescription(
      mSampleRate: Double(targetSampleRateHz),
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: 2,
      mFramesPerPacket: 1,
      mBytesPerFrame: 2,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 16,
      mReserved: 0
    )
    let clientStatus = ExtAudioFileSetProperty(
      extendedFile,
      kExtAudioFileProperty_ClientDataFormat,
      UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
      &clientFormat
    )
    guard clientStatus == noErr else {
      throw SignalASIPeerVoiceTranscriptionError.audioDecodeFailed(clientStatus)
    }

    var pcm16: [Int16] = []
    var chunk = [Int16](repeating: 0, count: 4_096)
    defer {
      for index in pcm16.indices { pcm16[index] = 0 }
      pcm16.removeAll(keepingCapacity: false)
      for index in chunk.indices { chunk[index] = 0 }
      chunk.removeAll(keepingCapacity: false)
    }
    while true {
      var frameCount = UInt32(chunk.count)
      let readStatus = chunk.withUnsafeMutableBytes { bytes -> OSStatus in
        var bufferList = AudioBufferList(
          mNumberBuffers: 1,
          mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(bytes.count),
            mData: bytes.baseAddress
          )
        )
        return ExtAudioFileRead(extendedFile, &frameCount, &bufferList)
      }
      guard readStatus == noErr else {
        throw SignalASIPeerVoiceTranscriptionError.audioDecodeFailed(readStatus)
      }
      guard frameCount > 0 else { break }
      pcm16.append(contentsOf: chunk.prefix(Int(frameCount)))
    }
    guard !pcm16.isEmpty else {
      throw VoiceWhisperAudioDecodeError.emptyAudio
    }
    return VoiceWhisperAudio(
      samples: pcm16.map { Float($0) / 32_768.0 },
      sampleRateHz: targetSampleRateHz,
      sourceSampleRateHz: Int(sourceFormat.mSampleRate.rounded()),
      channelCount: Int(sourceFormat.mChannelsPerFrame)
    )
  }

  private static func fileTypeHint(_ fileExtension: String) -> AudioFileTypeID {
    switch fileExtension {
    case "m4a", "mp4": return kAudioFileM4AType
    case "aac": return kAudioFileAAC_ADTSType
    case "caf": return kAudioFileCAFType
    default: return 0
    }
  }
}
