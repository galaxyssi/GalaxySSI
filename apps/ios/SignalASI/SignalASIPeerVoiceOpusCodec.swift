import AVFoundation
import Foundation

enum SignalASIPeerVoiceOpusError: LocalizedError {
  case captureUnavailable
  case emptyRecording
  case encoderUnavailable
  case encodingFailed(String)
  case invalidContainer

  var errorDescription: String? {
    switch self {
    case .captureUnavailable:
      return "48 kHz voice capture is unavailable."
    case .emptyRecording:
      return "Voice recording is empty."
    case .encoderUnavailable:
      return "This iPhone does not provide an Opus encoder."
    case .encodingFailed(let detail):
      return detail.ifBlank("Opus encoding failed.")
    case .invalidContainer:
      return "The Ogg Opus container is invalid."
    }
  }
}

struct SignalASIPeerVoiceEncodingResult {
  var data: Data
  var durationMillis: Int64
  var mimeType: String
  var fileExtension: String
  var measuredLUFS: Double?
  var appliedGainDecibels: Double
  var voiceProcessingEnabled: Bool
}

final class SignalASIPeerVoicePCMRecorder {
  private let engine = AVAudioEngine()
  private let lock = NSLock()
  private var capturedSamples: [Float] = []
  private var captureSampleRate = 0.0
  private var peak: Float = 0
  private(set) var voiceProcessingEnabled = false
  private(set) var isRunning = false

  func start() throws {
    guard !isRunning else { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetooth]
    )
    try session.setPreferredSampleRate(Double(SignalASIPeerVoiceMessageAudio.sampleRateHz))
    try session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let input = engine.inputNode
    do {
      try input.setVoiceProcessingEnabled(true)
      input.isVoiceProcessingAGCEnabled = false
      voiceProcessingEnabled = input.isVoiceProcessingEnabled
    } catch {
      voiceProcessingEnabled = false
    }
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw SignalASIPeerVoiceOpusError.captureUnavailable
    }
    lock.lock()
    capturedSamples.removeAll(keepingCapacity: true)
    captureSampleRate = format.sampleRate
    peak = 0
    lock.unlock()

    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 960, format: format) { [weak self] buffer, _ in
      self?.append(buffer)
    }
    engine.prepare()
    do {
      try engine.start()
      isRunning = true
    } catch {
      input.removeTap(onBus: 0)
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      throw error
    }
  }

  func stopAndEncode() throws -> SignalASIPeerVoiceEncodingResult {
    let capture = stopCapture()
    guard !capture.samples.isEmpty, capture.sampleRate > 0 else {
      throw SignalASIPeerVoiceOpusError.emptyRecording
    }
    return try SignalASIPeerVoiceOpusCodec.encode(
      capture.samples,
      sourceSampleRate: capture.sampleRate,
      voiceProcessingEnabled: voiceProcessingEnabled
    )
  }

  func cancel() {
    _ = stopCapture()
  }

  func currentAmplitude() -> Double {
    lock.lock()
    defer { lock.unlock() }
    return min(max(Double(peak) * 2.4, 0.05), 1)
  }

  private func append(_ buffer: AVAudioPCMBuffer) {
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    guard frames > 0, channels > 0 else { return }
    var mono = [Float](repeating: 0, count: frames)
    if let values = buffer.floatChannelData {
      for channel in 0..<channels {
        let source = values[channel]
        for frame in 0..<frames {
          mono[frame] += source[frame] / Float(channels)
        }
      }
    } else if let values = buffer.int16ChannelData {
      for channel in 0..<channels {
        let source = values[channel]
        for frame in 0..<frames {
          mono[frame] += Float(source[frame]) / (32_768 * Float(channels))
        }
      }
    } else {
      return
    }
    let localPeak = mono.reduce(Float(0)) { max($0, abs($1)) }
    lock.lock()
    let limit = Int(max(captureSampleRate, 1) * SignalASIPeerVoiceMessageAudio.maximumDuration)
    if capturedSamples.count < limit {
      capturedSamples.append(contentsOf: mono.prefix(limit - capturedSamples.count))
    }
    peak = localPeak
    lock.unlock()
  }

  private func stopCapture() -> (samples: [Float], sampleRate: Double) {
    if isRunning {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    isRunning = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    lock.lock()
    let result = (capturedSamples, captureSampleRate)
    capturedSamples.removeAll(keepingCapacity: false)
    captureSampleRate = 0
    peak = 0
    lock.unlock()
    return result
  }

  deinit {
    cancel()
  }
}

enum SignalASIPeerVoiceOpusCodec {
  static func encode(
    _ source: [Float],
    sourceSampleRate: Double,
    voiceProcessingEnabled: Bool
  ) throws -> SignalASIPeerVoiceEncodingResult {
    var samples = resample(source, sourceRate: sourceSampleRate)
    guard !samples.isEmpty else { throw SignalASIPeerVoiceOpusError.emptyRecording }
    let dsp = SignalASIPeerVoiceDSP.process(&samples)
    let pcm = samples.map { value -> Int16 in
      Int16(clamping: Int((value * Float(Int16.max)).rounded()))
    }
    let duration = Int64(pcm.count) * 1_000 / Int64(SignalASIPeerVoiceMessageAudio.sampleRateHz)
    var packets = try SignalASIPeerVoiceCoreAudioOpusEncoder.encode(pcm)
    defer {
      for index in packets.indices { packets[index].wipeSensitive() }
      packets.removeAll(keepingCapacity: false)
    }
    return SignalASIPeerVoiceEncodingResult(
      data: try SignalASIOggOpus.write(packets: packets, inputSampleCount: pcm.count),
      durationMillis: max(duration, 1),
      mimeType: "audio/ogg",
      fileExtension: "opus",
      measuredLUFS: dsp.measuredLUFS,
      appliedGainDecibels: dsp.appliedGainDecibels,
      voiceProcessingEnabled: voiceProcessingEnabled
    )
  }

  private static func resample(_ source: [Float], sourceRate: Double) -> [Float] {
    let targetRate = Double(SignalASIPeerVoiceMessageAudio.sampleRateHz)
    guard sourceRate > 0, !source.isEmpty else { return [] }
    guard abs(sourceRate - targetRate) > 0.5 else { return source }
    let count = max(1, Int((Double(source.count) * targetRate / sourceRate).rounded()))
    return (0..<count).map { index in
      let position = Double(index) * sourceRate / targetRate
      let left = min(Int(position), source.count - 1)
      let right = min(left + 1, source.count - 1)
      let fraction = Float(position - Double(left))
      return source[left] + (source[right] - source[left]) * fraction
    }
  }

  static func pcmWave(_ samples: [Int16]) -> Data {
    var data = Data()
    let payloadSize = samples.count * MemoryLayout<Int16>.size
    data.appendASCII("RIFF")
    data.appendLE(UInt32(36 + payloadSize))
    data.appendASCII("WAVEfmt ")
    data.appendLE(UInt32(16))
    data.appendLE(UInt16(1))
    data.appendLE(UInt16(1))
    data.appendLE(UInt32(SignalASIPeerVoiceMessageAudio.sampleRateHz))
    data.appendLE(UInt32(SignalASIPeerVoiceMessageAudio.sampleRateHz * 2))
    data.appendLE(UInt16(2))
    data.appendLE(UInt16(16))
    data.appendASCII("data")
    data.appendLE(UInt32(payloadSize))
    samples.forEach { data.appendLE(UInt16(bitPattern: $0)) }
    return data
  }
}

enum SignalASIPeerVoiceOpusPlayback {
  static func pcmWaveData(fromOggOpus data: Data) throws -> Data {
    var packets = try SignalASIOggOpus.audioPackets(from: data)
    defer {
      for index in packets.indices { packets[index].wipeSensitive() }
      packets.removeAll(keepingCapacity: false)
    }
    var samples = try decode(packets)
    defer { samples.wipeSensitive() }
    return SignalASIPeerVoiceOpusCodec.pcmWave(samples)
  }

  private static func decode(_ packets: [Data]) throws -> [Int16] {
    var inputDescription = AudioStreamBasicDescription(
      mSampleRate: Double(SignalASIPeerVoiceMessageAudio.sampleRateHz),
      mFormatID: kAudioFormatOpus,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: 960,
      mBytesPerFrame: 0,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 0,
      mReserved: 0
    )
    guard let inputFormat = AVAudioFormat(streamDescription: &inputDescription),
          let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(SignalASIPeerVoiceMessageAudio.sampleRateHz),
            channels: 1,
            interleaved: false
          ),
          let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw SignalASIPeerVoiceOpusError.encoderUnavailable
    }
    var packetIndex = 0
    var samples: [Int16] = []
    var reachedEnd = false
    var emptyDrainPasses = 0
    while !reachedEnd {
      guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 9_600) else {
        throw SignalASIPeerVoiceOpusError.encodingFailed("Unable to allocate Opus playback buffer.")
      }
      var conversionError: NSError?
      let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
        guard packetIndex < packets.count else {
          inputStatus.pointee = .endOfStream
          return nil
        }
        let packet = packets[packetIndex]
        packetIndex += 1
        let buffer = AVAudioCompressedBuffer(
          format: inputFormat,
          packetCapacity: 1,
          maximumPacketSize: max(packet.count, 1)
        )
        packet.copyBytes(to: buffer.data.assumingMemoryBound(to: UInt8.self), count: packet.count)
        buffer.byteLength = UInt32(packet.count)
        buffer.packetCount = 1
        if let descriptions = buffer.packetDescriptions {
          descriptions[0] = AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: 960,
            mDataByteSize: UInt32(packet.count)
          )
        }
        inputStatus.pointee = .haveData
        return buffer
      }
      if let conversionError {
        throw SignalASIPeerVoiceOpusError.encodingFailed(conversionError.localizedDescription)
      }
      if let channel = output.floatChannelData?[0] {
        for index in 0..<Int(output.frameLength) {
          samples.append(Int16(clamping: Int((channel[index] * Float(Int16.max)).rounded())))
        }
      }
      emptyDrainPasses = output.frameLength == 0 ? emptyDrainPasses + 1 : 0
      switch status {
      case .endOfStream:
        reachedEnd = true
      case .error:
        throw SignalASIPeerVoiceOpusError.encodingFailed("Core Audio rejected the Opus message.")
      case .haveData, .inputRanDry:
        if packetIndex >= packets.count, emptyDrainPasses > 2 {
          throw SignalASIPeerVoiceOpusError.encodingFailed("The Opus decoder did not finish draining.")
        }
      @unknown default:
        throw SignalASIPeerVoiceOpusError.encodingFailed("Unknown Core Audio decoding status.")
      }
    }
    guard !samples.isEmpty else { throw SignalASIPeerVoiceOpusError.emptyRecording }
    return samples
  }
}

struct SignalASIPeerVoiceDSPResult {
  var measuredLUFS: Double?
  var appliedGainDecibels: Double
  var outputPeakDBFS: Double
}

enum SignalASIPeerVoiceDSP {
  private static let absoluteGateLUFS = -70.0
  private static let relativeGateLU = 10.0
  private static let loudnessOffset = -0.691

  static func process(_ samples: inout [Float]) -> SignalASIPeerVoiceDSPResult {
    applyHighPass(&samples, cutoffHz: Double(SignalASIPeerVoiceMessageAudio.highPassHz))
    let measured = integratedLUFS(samples)
    let requestedDB = measured.map { SignalASIPeerVoiceMessageAudio.targetLUFS - $0 } ?? 0
    let requestedGain = pow(10, requestedDB / 20)
    let peak = samples.reduce(0.0) { max($0, Double(abs($1))) }
    let limit = pow(10, SignalASIPeerVoiceMessageAudio.peakDBFS / 20)
    let peakSafeGain = peak > 0 ? limit / peak : requestedGain
    let gain = max(0, min(requestedGain, peakSafeGain))
    var outputPeak = 0.0
    for index in samples.indices {
      let value = min(max(Double(samples[index]) * gain, -limit), limit)
      samples[index] = Float(value)
      outputPeak = max(outputPeak, abs(value))
    }
    return SignalASIPeerVoiceDSPResult(
      measuredLUFS: measured,
      appliedGainDecibels: gain > 0 ? 20 * log10(gain) : -120,
      outputPeakDBFS: outputPeak > 0 ? 20 * log10(outputPeak) : -120
    )
  }

  static func applyHighPass(_ samples: inout [Float], cutoffHz: Double) {
    let dt = 1.0 / Double(SignalASIPeerVoiceMessageAudio.sampleRateHz)
    let rc = 1.0 / (2 * Double.pi * cutoffHz)
    let alpha = rc / (rc + dt)
    var previousInput = 0.0
    var previousOutput = 0.0
    for index in samples.indices {
      let input = Double(samples[index])
      let output = alpha * (previousOutput + input - previousInput)
      samples[index] = Float(output)
      previousInput = input
      previousOutput = output
    }
  }

  static func integratedLUFS(_ samples: [Float]) -> Double? {
    let block = SignalASIPeerVoiceMessageAudio.sampleRateHz * 400 / 1_000
    let step = SignalASIPeerVoiceMessageAudio.sampleRateHz * 100 / 1_000
    guard samples.count >= block else {
      let energy = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(samples.count, 1))
      let value = loudness(energy)
      return value > absoluteGateLUFS ? value : nil
    }
    var shelf = Biquad(1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585)
    var highPass = Biquad(1, -2, 1, -1.99004745483398, 0.99007225036621)
    var ring = [Double](repeating: 0, count: block)
    var sum = 0.0
    var energies: [Double] = []
    for (index, sample) in samples.enumerated() {
      let weighted = highPass.process(shelf.process(Double(sample)))
      let square = weighted * weighted
      let slot = index % block
      sum -= ring[slot]
      ring[slot] = square
      sum += square
      if index + 1 >= block, (index + 1 - block) % step == 0 {
        energies.append(max(sum / Double(block), 0))
      }
    }
    let absolute = energies.filter { loudness($0) > absoluteGateLUFS }
    guard !absolute.isEmpty else { return nil }
    let threshold = loudness(absolute.reduce(0, +) / Double(absolute.count)) - relativeGateLU
    let gated = absolute.filter { loudness($0) > threshold }
    guard !gated.isEmpty else { return nil }
    return loudness(gated.reduce(0, +) / Double(gated.count))
  }

  private static func loudness(_ energy: Double) -> Double {
    energy > 0 ? loudnessOffset + 10 * log10(energy) : -120
  }

  private struct Biquad {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double
    var x1 = 0.0
    var x2 = 0.0
    var y1 = 0.0
    var y2 = 0.0

    init(_ b0: Double, _ b1: Double, _ b2: Double, _ a1: Double, _ a2: Double) {
      self.b0 = b0
      self.b1 = b1
      self.b2 = b2
      self.a1 = a1
      self.a2 = a2
    }

    mutating func process(_ input: Double) -> Double {
      let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
      x2 = x1
      x1 = input
      y2 = y1
      y1 = output
      return output
    }
  }
}

enum SignalASIPeerVoiceCoreAudioOpusEncoder {
  private static let frameSamples: AVAudioFrameCount = 960

  static func encode(_ samples: [Int16]) throws -> [Data] {
    guard !samples.isEmpty else { throw SignalASIPeerVoiceOpusError.emptyRecording }
    guard let inputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(SignalASIPeerVoiceMessageAudio.sampleRateHz),
      channels: 1,
      interleaved: false
    ) else { throw SignalASIPeerVoiceOpusError.encoderUnavailable }
    var outputDescription = AudioStreamBasicDescription(
      mSampleRate: Double(SignalASIPeerVoiceMessageAudio.sampleRateHz),
      mFormatID: kAudioFormatOpus,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: UInt32(frameSamples),
      mBytesPerFrame: 0,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 0,
      mReserved: 0
    )
    guard let outputFormat = AVAudioFormat(streamDescription: &outputDescription),
          let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw SignalASIPeerVoiceOpusError.encoderUnavailable
    }
    converter.bitRate = SignalASIPeerVoiceMessageAudio.opusBitRateBPS
    converter.bitRateStrategy = AVAudioBitRateStrategy_Variable
    let maximumPacketSize = max(converter.maximumOutputPacketSize, 1_500)
    var inputOffset = 0
    var packets: [Data] = []
    var reachedEnd = false
    var inputEnded = false
    var emptyDrainPasses = 0

    while !reachedEnd {
      let output = AVAudioCompressedBuffer(
        format: outputFormat,
        packetCapacity: 20,
        maximumPacketSize: maximumPacketSize
      )
      var conversionError: NSError?
      let status = converter.convert(to: output, error: &conversionError) { requested, inputStatus in
        guard !inputEnded, inputOffset < samples.count else {
          inputEnded = true
          inputStatus.pointee = .endOfStream
          return nil
        }
        let frames = min(Int(requested), samples.count - inputOffset)
        guard let buffer = AVAudioPCMBuffer(
          pcmFormat: inputFormat,
          frameCapacity: AVAudioFrameCount(frames)
        ), let destination = buffer.int16ChannelData?[0] else {
          inputStatus.pointee = .noDataNow
          return nil
        }
        samples.withUnsafeBufferPointer { source in
          destination.update(from: source.baseAddress!.advanced(by: inputOffset), count: frames)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        inputOffset += frames
        inputStatus.pointee = .haveData
        return buffer
      }
      if let conversionError {
        throw SignalASIPeerVoiceOpusError.encodingFailed(conversionError.localizedDescription)
      }
      try appendPackets(from: output, to: &packets)
      emptyDrainPasses = output.packetCount == 0 ? emptyDrainPasses + 1 : 0
      switch status {
      case .endOfStream:
        reachedEnd = true
      case .error:
        throw SignalASIPeerVoiceOpusError.encodingFailed("Core Audio rejected the Opus stream.")
      case .haveData, .inputRanDry:
        if inputEnded, emptyDrainPasses > 2 {
          throw SignalASIPeerVoiceOpusError.encodingFailed("The Opus encoder did not finish draining.")
        }
      @unknown default:
        throw SignalASIPeerVoiceOpusError.encodingFailed("Unknown Core Audio conversion status.")
      }
    }
    guard !packets.isEmpty else {
      throw SignalASIPeerVoiceOpusError.encodingFailed("The Opus encoder produced no audio packets.")
    }
    return packets
  }

  private static func appendPackets(
    from buffer: AVAudioCompressedBuffer,
    to packets: inout [Data]
  ) throws {
    let count = Int(buffer.packetCount)
    guard count > 0 else { return }
    if let descriptions = buffer.packetDescriptions {
      for index in 0..<count {
        let description = descriptions[index]
        packets.append(Data(
          bytes: buffer.data.advanced(by: Int(description.mStartOffset)),
          count: Int(description.mDataByteSize)
        ))
      }
    } else if count == 1 {
      packets.append(Data(bytes: buffer.data, count: Int(buffer.byteLength)))
    } else {
      throw SignalASIPeerVoiceOpusError.encodingFailed("Opus packet boundaries are unavailable.")
    }
  }
}

enum SignalASIOggOpus {
  private static let preSkip: UInt64 = 312
  private static let packetsPerPage = 20

  static func write(packets: [Data], inputSampleCount: Int) throws -> Data {
    guard !packets.isEmpty, inputSampleCount > 0 else {
      throw SignalASIPeerVoiceOpusError.encodingFailed("Opus packets are empty.")
    }
    var output = Data()
    let serial = UInt32.random(in: UInt32.min...UInt32.max)
    var sequence: UInt32 = 0
    output.append(try page(
      serial: serial,
      sequence: sequence,
      granule: 0,
      headerType: 0x02,
      packets: [opusHead()]
    ))
    sequence += 1
    output.append(try page(
      serial: serial,
      sequence: sequence,
      granule: 0,
      headerType: 0,
      packets: [opusTags()]
    ))
    sequence += 1
    var consumed = 0
    for start in stride(from: 0, to: packets.count, by: packetsPerPage) {
      let end = min(start + packetsPerPage, packets.count)
      let values = Array(packets[start..<end])
      consumed += min(inputSampleCount - consumed, values.count * 960)
      output.append(try page(
        serial: serial,
        sequence: sequence,
        granule: preSkip + UInt64(max(consumed, 0)),
        headerType: end == packets.count ? 0x04 : 0,
        packets: values
      ))
      sequence += 1
    }
    return output
  }

  static func audioPackets(from data: Data) throws -> [Data] {
    var offset = 0
    var packet = Data()
    var packets: [Data] = []
    while offset + 27 <= data.count {
      guard data.ascii(at: offset, count: 4) == "OggS", data[offset + 4] == 0 else {
        throw SignalASIPeerVoiceOpusError.invalidContainer
      }
      let segments = Int(data[offset + 26])
      let tableStart = offset + 27
      let payloadStart = tableStart + segments
      guard payloadStart <= data.count else { throw SignalASIPeerVoiceOpusError.invalidContainer }
      let payloadBytes = (0..<segments).reduce(0) { $0 + Int(data[tableStart + $1]) }
      guard payloadStart + payloadBytes <= data.count else {
        throw SignalASIPeerVoiceOpusError.invalidContainer
      }
      var cursor = payloadStart
      for index in 0..<segments {
        let size = Int(data[tableStart + index])
        packet.append(data[cursor..<(cursor + size)])
        cursor += size
        if size < 255 {
          if !packet.starts(withASCII: "OpusHead") && !packet.starts(withASCII: "OpusTags") {
            packets.append(packet)
          }
          packet = Data()
        }
      }
      offset = payloadStart + payloadBytes
    }
    guard offset == data.count, packet.isEmpty, !packets.isEmpty else {
      throw SignalASIPeerVoiceOpusError.invalidContainer
    }
    return packets
  }

  private static func opusHead() -> Data {
    var data = Data("OpusHead".utf8)
    data.append(1)
    data.append(1)
    data.appendLE(UInt16(preSkip))
    data.appendLE(UInt32(SignalASIPeerVoiceMessageAudio.sampleRateHz))
    data.appendLE(UInt16(0))
    data.append(0)
    return data
  }

  private static func opusTags() -> Data {
    let vendor = Data("SignalASI iOS".utf8)
    var data = Data("OpusTags".utf8)
    data.appendLE(UInt32(vendor.count))
    data.append(vendor)
    data.appendLE(UInt32(0))
    return data
  }

  private static func page(
    serial: UInt32,
    sequence: UInt32,
    granule: UInt64,
    headerType: UInt8,
    packets: [Data]
  ) throws -> Data {
    var lacing: [UInt8] = []
    for packet in packets {
      var remaining = packet.count
      while remaining >= 255 {
        lacing.append(255)
        remaining -= 255
      }
      lacing.append(UInt8(remaining))
    }
    guard lacing.count <= 255 else {
      throw SignalASIPeerVoiceOpusError.encodingFailed("An Ogg page has too many segments.")
    }
    var data = Data("OggS".utf8)
    data.append(0)
    data.append(headerType)
    data.appendLE(granule)
    data.appendLE(serial)
    data.appendLE(sequence)
    data.appendLE(UInt32(0))
    data.append(UInt8(lacing.count))
    data.append(contentsOf: lacing)
    packets.forEach { data.append($0) }
    data.replaceLE(UInt32(oggCRC(data)), at: 22)
    return data
  }

  private static func oggCRC(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0
    for byte in data {
      crc ^= UInt32(byte) << 24
      for _ in 0..<8 {
        crc = crc & 0x8000_0000 != 0 ? (crc << 1) ^ 0x04c1_1db7 : crc << 1
      }
    }
    return crc
  }
}

private extension Data {
  mutating func appendASCII(_ value: String) {
    append(Data(value.utf8))
  }

  mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }

  mutating func replaceLE<T: FixedWidthInteger>(_ value: T, at offset: Int) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { bytes in
      replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
  }

  func ascii(at offset: Int, count: Int) -> String {
    guard offset >= 0, offset + count <= self.count else { return "" }
    return String(data: Data(self[offset..<(offset + count)]), encoding: .ascii) ?? ""
  }

  func starts(withASCII value: String) -> Bool {
    starts(with: Data(value.utf8))
  }
}
