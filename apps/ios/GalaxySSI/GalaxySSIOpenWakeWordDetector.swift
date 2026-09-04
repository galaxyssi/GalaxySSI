// Portions based on LiveKit's wake-word Swift implementation.
// Copyright 2026 LiveKit, Inc. Licensed under Apache-2.0.

import Foundation

/// Serial callers pass a rolling two-second, mono 16 kHz Int16 window and
/// receive the Android-compatible hello_world classifier confidence.
final class GalaxySSIOpenWakeWordDetector {
  private let melFrontend: GalaxySSIOpenWakeWordMelFrontend
  private let embeddingModel: GalaxySSIOpenWakeWordEmbeddingModel
  private let classifier: GalaxySSIOpenWakeWordClassifier

  init(modelName: String) throws {
    melFrontend = try GalaxySSIOpenWakeWordMelFrontend()
    embeddingModel = try GalaxySSIOpenWakeWordEmbeddingModel()
    classifier = try GalaxySSIOpenWakeWordClassifier(modelName: modelName)
  }

  func confidence(for pcm: [Int16]) throws -> Float {
    guard pcm.count >= GalaxySSIOpenWakeWordConstants.minimumSamples else { return 0 }
    let cappedCount = min(pcm.count, GalaxySSIOpenWakeWordConstants.maximumSamples)
    var normalized = [Float](repeating: 0, count: cappedCount)
    for index in 0..<cappedCount {
      normalized[index] = Float(pcm[index]) / 32_768
    }

    let mel = try normalized.withUnsafeBufferPointer { samples in
      try melFrontend.predict(audio: samples)
    }
    let windowCount = (mel.frameCount - GalaxySSIOpenWakeWordConstants.embeddingWindow) /
      GalaxySSIOpenWakeWordConstants.embeddingStride + 1
    guard windowCount >= GalaxySSIOpenWakeWordConstants.classifierEmbeddings else { return 0 }

    let windows = Self.embeddingWindows(
      from: mel,
      firstWindow: windowCount - GalaxySSIOpenWakeWordConstants.classifierEmbeddings
    )
    return try classifier.predict(embeddings: embeddingModel.predict(windows: windows))
  }

  private static func embeddingWindows(
    from mel: GalaxySSIOpenWakeWordMelOutput,
    firstWindow: Int
  ) -> [Float] {
    let framesPerWindow = GalaxySSIOpenWakeWordConstants.embeddingWindow
    let bins = GalaxySSIOpenWakeWordConstants.melBins
    let stride = GalaxySSIOpenWakeWordConstants.embeddingStride
    let batchSize = GalaxySSIOpenWakeWordConstants.classifierEmbeddings
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
