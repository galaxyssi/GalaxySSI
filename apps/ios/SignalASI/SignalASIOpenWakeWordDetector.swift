// Portions based on LiveKit's wake-word Swift implementation.
// Copyright 2026 LiveKit, Inc. Licensed under Apache-2.0.

import Foundation

/// Serial callers pass a rolling two-second, mono 16 kHz Int16 window and
/// receive the Android-compatible hello_world classifier confidence.
final class SignalASIOpenWakeWordDetector {
  private let melFrontend: SignalASIOpenWakeWordMelFrontend
  private let embeddingModel: SignalASIOpenWakeWordEmbeddingModel
  private let classifier: SignalASIOpenWakeWordClassifier

  init(modelName: String) throws {
    melFrontend = try SignalASIOpenWakeWordMelFrontend()
    embeddingModel = try SignalASIOpenWakeWordEmbeddingModel()
    classifier = try SignalASIOpenWakeWordClassifier(modelName: modelName)
  }

  func confidence(for pcm: [Int16]) throws -> Float {
    guard pcm.count >= SignalASIOpenWakeWordConstants.minimumSamples else { return 0 }
    let cappedCount = min(pcm.count, SignalASIOpenWakeWordConstants.maximumSamples)
    var normalized = [Float](repeating: 0, count: cappedCount)
    for index in 0..<cappedCount {
      normalized[index] = Float(pcm[index]) / 32_768
    }

    let mel = try normalized.withUnsafeBufferPointer { samples in
      try melFrontend.predict(audio: samples)
    }
    let windowCount = (mel.frameCount - SignalASIOpenWakeWordConstants.embeddingWindow) /
      SignalASIOpenWakeWordConstants.embeddingStride + 1
    guard windowCount >= SignalASIOpenWakeWordConstants.classifierEmbeddings else { return 0 }

    let windows = Self.embeddingWindows(
      from: mel,
      firstWindow: windowCount - SignalASIOpenWakeWordConstants.classifierEmbeddings
    )
    return try classifier.predict(embeddings: embeddingModel.predict(windows: windows))
  }

  private static func embeddingWindows(
    from mel: SignalASIOpenWakeWordMelOutput,
    firstWindow: Int
  ) -> [Float] {
    let framesPerWindow = SignalASIOpenWakeWordConstants.embeddingWindow
    let bins = SignalASIOpenWakeWordConstants.melBins
    let stride = SignalASIOpenWakeWordConstants.embeddingStride
    let batchSize = SignalASIOpenWakeWordConstants.classifierEmbeddings
    let valuesPerWindow = framesPerWindow * bins
    var result = [Float](repeating: 0, count: batchSize * valuesPerWindow)

    mel.samples.withUnsafeBufferPointer { source in
      result.withUnsafeMutableBufferPointer { destination in
        guard let sourceBase = source.baseAddress,
              let destinationBase = destination.baseAddress else { return }
        for batchIndex in 0..<batchSize {
          let sourceOffset = (firstWindow + batchIndex) * stride * bins
          let destinationOffset = batchIndex * valuesPerWindow
          destinationBase.advanced(by: destinationOffset).update(
            from: sourceBase.advanced(by: sourceOffset),
            count: valuesPerWindow
          )
        }
      }
    }
    return result
  }
}
