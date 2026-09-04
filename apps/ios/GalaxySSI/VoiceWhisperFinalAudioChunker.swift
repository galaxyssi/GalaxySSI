import Foundation

struct VoiceWhisperPcmChunk: Equatable {
  var offset: Int
  var length: Int

  var endExclusive: Int {
    offset + length
  }
}

struct VoiceWhisperFinalDecodeChunk: Equatable {
  var chunk: VoiceWhisperPcmChunk
  var result: VoiceNativeWhisperResult
}

enum VoiceWhisperFinalAudioChunker {
  static func plan(
    sampleCount: Int,
    sampleRateHz: Int,
    mode: VoiceWhisperExecutionMode,
    maximumChunkMillis: Int64 = 26_000,
    overlapMillis: Int64 = 1_500
  ) -> [VoiceWhisperPcmChunk] {
    guard sampleCount > 0, sampleRateHz > 0 else { return [] }
    guard maximumChunkMillis > 0,
          overlapMillis >= 0,
          overlapMillis < maximumChunkMillis else {
      return []
    }
    guard mode == .finalOnly else {
      return [VoiceWhisperPcmChunk(offset: 0, length: sampleCount)]
    }

    let maximumSamples = millisecondsToSamples(maximumChunkMillis, sampleRateHz: sampleRateHz)
    guard sampleCount > maximumSamples else {
      return [VoiceWhisperPcmChunk(offset: 0, length: sampleCount)]
    }
    let overlapSamples = millisecondsToSamples(overlapMillis, sampleRateHz: sampleRateHz)
    let advanceSamples = max(1, maximumSamples - overlapSamples)
    var chunks: [VoiceWhisperPcmChunk] = []
    var offset = 0
    while offset < sampleCount {
      let length = min(maximumSamples, sampleCount - offset)
      chunks.append(VoiceWhisperPcmChunk(offset: offset, length: length))
      if offset + length >= sampleCount { break }
      offset += advanceSamples
    }
    return chunks
  }

  private static func millisecondsToSamples(_ milliseconds: Int64, sampleRateHz: Int) -> Int {
    let samples = milliseconds * Int64(sampleRateHz) / 1_000
    return Int(min(max(samples, 1), Int64(Int.max)))
  }
}

enum VoiceWhisperFinalResultAssembler {
  static func assemble(
    chunks: [VoiceWhisperFinalDecodeChunk],
    totalSamples: Int,
    sampleRateHz: Int
  ) -> VoiceNativeWhisperResult {
    guard !chunks.isEmpty, totalSamples > 0, sampleRateHz > 0 else {
      return .failure(.invalidPCM, message: "Final Whisper audio assembly received invalid input.")
    }
    if let failure = chunks.first(where: { !$0.result.successful })?.result {
      return failure
    }

    let text = chunks.reduce(into: "") { accumulated, item in
      accumulated = merge(prefix: accumulated, suffix: item.result.text)
    }
    let totalAudioMillis = Int64(totalSamples) * 1_000 / Int64(sampleRateHz)
    let totalMillis = chunks.reduce(0.0) { $0 + $1.result.timings.totalMillis }
    let segments = text.isEmpty
      ? []
      : [VoiceNativeWhisperSegment(
        startMillis: 0,
        endMillis: totalAudioMillis,
        text: text,
        averageLogProbability: mean(chunks.flatMap { $0.result.segments.map(\.averageLogProbability) }),
        noSpeechProbability: mean(chunks.flatMap { $0.result.segments.map(\.noSpeechProbability) })
      )]
    return VoiceNativeWhisperResult(
      codeValue: VoiceNativeWhisperCode.ok.rawValue,
      segments: segments,
      detectedLanguage: chunks.first(where: { $0.result.detectedLanguage != nil })?.result.detectedLanguage,
      timings: VoiceNativeWhisperTimings(
        sampleMillis: chunks.reduce(0.0) { $0 + $1.result.timings.sampleMillis },
        encodeMillis: chunks.reduce(0.0) { $0 + $1.result.timings.encodeMillis },
        decodeMillis: chunks.reduce(0.0) { $0 + $1.result.timings.decodeMillis },
        totalMillis: totalMillis,
        audioMillis: totalAudioMillis,
        realTimeFactor: totalMillis / Double(max(totalAudioMillis, 1))
      ),
      aborted: false,
      message: nil
    )
  }

  private static func merge(prefix: String, suffix: String) -> String {
    let left = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    let right = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    if left.isEmpty { return right }
    if right.isEmpty { return left }
    let leftCharacters = Array(left)
    let rightCharacters = Array(right)
    let maximum = min(leftCharacters.count, rightCharacters.count, 96)
    var overlap = 0
    if maximum > 0 {
      for candidate in stride(from: maximum, through: 1, by: -1) {
        guard Array(leftCharacters.suffix(candidate)) == Array(rightCharacters.prefix(candidate)) else {
          continue
        }
        if candidate >= 2 || acceptableSingleCharacterOverlap(
          left: leftCharacters,
          right: rightCharacters
        ) {
          overlap = candidate
          break
        }
      }
    }
    let remainder = String(rightCharacters.dropFirst(overlap))
    if remainder.isEmpty { return left }
    let separator = isLetterOrNumber(leftCharacters.last!) &&
      isLetterOrNumber(remainder.first!) &&
      !isCJK(leftCharacters.last!) &&
      !isCJK(remainder.first!) ? " " : ""
    return left + separator + remainder
  }

  private static func acceptableSingleCharacterOverlap(
    left: [Character],
    right: [Character]
  ) -> Bool {
    guard let point = right.first else { return false }
    return isCJK(point) || !isLetterOrNumber(point) || left == right
  }

  private static func mean(_ values: [Float]) -> Float {
    let finite = values.filter { !$0.isNaN && !$0.isInfinite }
    guard !finite.isEmpty else { return .nan }
    return finite.reduce(0, +) / Float(finite.count)
  }

  private static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
  }

  private static func isLetterOrNumber(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
  }
}
