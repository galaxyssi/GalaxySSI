// Portions based on LiveKit's wake-word Swift implementation.
// Copyright 2026 LiveKit, Inc. Licensed under Apache-2.0.

import Foundation
import OnnxRuntimeBindings

enum SignalASIOpenWakeWordError: Error, LocalizedError {
  case missingModel(String)
  case invalidAudioLength(Int)
  case invalidOutput(String)
  case unsupportedAudioFormat(Double)
  case runtime(Error)

  var errorDescription: String? {
    switch self {
    case .missingModel(let name):
      return "OpenWakeWord model is missing: \(name)"
    case .invalidAudioLength(let count):
      return "OpenWakeWord received an invalid audio window (\(count) samples)."
    case .invalidOutput(let details):
      return "OpenWakeWord returned an invalid model output: \(details)"
    case .unsupportedAudioFormat(let sampleRate):
      return "OpenWakeWord cannot convert the microphone format (\(Int(sampleRate)) Hz)."
    case .runtime(let error):
      return "OpenWakeWord runtime failed: \(error.localizedDescription)"
    }
  }
}

enum SignalASIOpenWakeWordConstants {
  static let sampleRate: Double = 16_000
  static let melBins = 32
  static let embeddingWindow = 76
  static let embeddingStride = 8
  static let classifierEmbeddings = 16
  static let embeddingDimension = 96
  static let minimumSamples = 16_000
  static let maximumSamples = 48_000
}

enum SignalASIOpenWakeWordResources {
  static func modelURL(named fileName: String) throws -> URL {
    let safeName = URL(fileURLWithPath: fileName).lastPathComponent
    let fileURL = URL(fileURLWithPath: safeName)
    let name = fileURL.deletingPathExtension().lastPathComponent
    let fileExtension = fileURL.pathExtension.ifBlank("onnx")
    if let url = Bundle.main.url(
      forResource: name,
      withExtension: fileExtension,
      subdirectory: "voice/openwakeword"
    ) {
      return url
    }
    throw SignalASIOpenWakeWordError.missingModel(safeName)
  }
}

enum SignalASIOpenWakeWordEnvironment {
  private static let lock = NSLock()
  private static var cachedEnvironment: ORTEnv?

  static func makeSession(modelURL: URL) throws -> ORTSession {
    do {
      let environment = try sharedEnvironment()
      let options = try ORTSessionOptions()
      return try ORTSession(
        env: environment,
        modelPath: modelURL.path,
        sessionOptions: options
      )
    } catch {
      throw SignalASIOpenWakeWordError.runtime(error)
    }
  }

  private static func sharedEnvironment() throws -> ORTEnv {
    lock.lock()
    defer { lock.unlock() }
    if let cachedEnvironment { return cachedEnvironment }
    let environment = try ORTEnv(loggingLevel: .warning)
    cachedEnvironment = environment
    return environment
  }
}

struct SignalASIOpenWakeWordMelOutput {
  let samples: [Float]
  let frameCount: Int
}

final class SignalASIOpenWakeWordMelFrontend {
  private let session: ORTSession

  init() throws {
    session = try SignalASIOpenWakeWordEnvironment.makeSession(
      modelURL: SignalASIOpenWakeWordResources.modelURL(named: "melspectrogram.onnx")
    )
  }

  func predict(audio: UnsafeBufferPointer<Float>) throws -> SignalASIOpenWakeWordMelOutput {
    guard audio.count >= SignalASIOpenWakeWordConstants.minimumSamples,
          audio.count <= SignalASIOpenWakeWordConstants.maximumSamples else {
      throw SignalASIOpenWakeWordError.invalidAudioLength(audio.count)
    }

    let inputData = try Self.mutableData(copying: audio)
    do {
      let input = try ORTValue(
        tensorData: inputData,
        elementType: .float,
        shape: [1, NSNumber(value: audio.count)]
      )
      let outputs = try session.run(
        withInputs: ["input": input],
        outputNames: ["output"],
        runOptions: nil
      )
      guard let output = outputs["output"] else {
        throw SignalASIOpenWakeWordError.invalidOutput("melspectrogram.output is absent")
      }
      let shape = try output.tensorTypeAndShapeInfo().shape.map(\.intValue)
      guard shape.count == 4,
            shape[0] == 1,
            shape[1] == 1,
            shape[3] == SignalASIOpenWakeWordConstants.melBins else {
        throw SignalASIOpenWakeWordError.invalidOutput("melspectrogram shape \(shape)")
      }

      let frameCount = shape[2]
      let count = frameCount * SignalASIOpenWakeWordConstants.melBins
      let data = try output.tensorData()
      let source = data.bytes.assumingMemoryBound(to: Float.self)
      var samples = [Float](repeating: 0, count: count)
      for index in samples.indices {
        samples[index] = source[index] * 0.1 + 2
      }
      return SignalASIOpenWakeWordMelOutput(samples: samples, frameCount: frameCount)
    } catch let error as SignalASIOpenWakeWordError {
      throw error
    } catch {
      throw SignalASIOpenWakeWordError.runtime(error)
    }
  }

  private static func mutableData(copying audio: UnsafeBufferPointer<Float>) throws -> NSMutableData {
    let byteCount = audio.count * MemoryLayout<Float>.size
    guard let data = NSMutableData(length: byteCount), let baseAddress = audio.baseAddress else {
      throw SignalASIOpenWakeWordError.invalidOutput("unable to allocate audio tensor")
    }
    data.mutableBytes.assumingMemoryBound(to: Float.self).update(
      from: baseAddress,
      count: audio.count
    )
    return data
  }
}

final class SignalASIOpenWakeWordEmbeddingModel {
  private let session: ORTSession

  init() throws {
    session = try SignalASIOpenWakeWordEnvironment.makeSession(
      modelURL: SignalASIOpenWakeWordResources.modelURL(named: "embedding_model.onnx")
    )
  }

  func predict(windows: [Float]) throws -> [Float] {
    let batchSize = SignalASIOpenWakeWordConstants.classifierEmbeddings
    let expectedCount = batchSize * SignalASIOpenWakeWordConstants.embeddingWindow *
      SignalASIOpenWakeWordConstants.melBins
    guard windows.count == expectedCount else {
      throw SignalASIOpenWakeWordError.invalidOutput("embedding input has \(windows.count) values")
    }

    do {
      let input = try ORTValue(
        tensorData: try Self.mutableData(copying: windows),
        elementType: .float,
        shape: [
          NSNumber(value: batchSize),
          NSNumber(value: SignalASIOpenWakeWordConstants.embeddingWindow),
          NSNumber(value: SignalASIOpenWakeWordConstants.melBins),
          1,
        ]
      )
      let outputs = try session.run(
        withInputs: ["input_1": input],
        outputNames: ["conv2d_19"],
        runOptions: nil
      )
      guard let output = outputs["conv2d_19"] else {
        throw SignalASIOpenWakeWordError.invalidOutput("embedding.conv2d_19 is absent")
      }
      let data = try output.tensorData()
      let count = batchSize * SignalASIOpenWakeWordConstants.embeddingDimension
      var result = [Float](repeating: 0, count: count)
      result.withUnsafeMutableBytes { destination in
        destination.copyMemory(
          from: UnsafeRawBufferPointer(
            start: data.bytes,
            count: count * MemoryLayout<Float>.size
          )
        )
      }
      return result
    } catch let error as SignalASIOpenWakeWordError {
      throw error
    } catch {
      throw SignalASIOpenWakeWordError.runtime(error)
    }
  }

  private static func mutableData(copying values: [Float]) throws -> NSMutableData {
    let byteCount = values.count * MemoryLayout<Float>.size
    guard let data = NSMutableData(length: byteCount) else {
      throw SignalASIOpenWakeWordError.invalidOutput("unable to allocate embedding tensor")
    }
    values.withUnsafeBufferPointer { source in
      if let baseAddress = source.baseAddress {
        data.mutableBytes.assumingMemoryBound(to: Float.self).update(
          from: baseAddress,
          count: values.count
        )
      }
    }
    return data
  }
}

final class SignalASIOpenWakeWordClassifier {
  private let session: ORTSession

  init(modelName: String) throws {
    session = try SignalASIOpenWakeWordEnvironment.makeSession(
      modelURL: SignalASIOpenWakeWordResources.modelURL(named: modelName)
    )
  }

  func predict(embeddings: [Float]) throws -> Float {
    let expectedCount = SignalASIOpenWakeWordConstants.classifierEmbeddings *
      SignalASIOpenWakeWordConstants.embeddingDimension
    guard embeddings.count == expectedCount else {
      throw SignalASIOpenWakeWordError.invalidOutput("classifier input has \(embeddings.count) values")
    }

    do {
      guard let data = NSMutableData(length: embeddings.count * MemoryLayout<Float>.size) else {
        throw SignalASIOpenWakeWordError.invalidOutput("unable to allocate classifier tensor")
      }
      embeddings.withUnsafeBufferPointer { source in
        data.mutableBytes.assumingMemoryBound(to: Float.self).update(
          from: source.baseAddress!,
          count: embeddings.count
        )
      }
      let input = try ORTValue(
        tensorData: data,
        elementType: .float,
        shape: [
          1,
          NSNumber(value: SignalASIOpenWakeWordConstants.classifierEmbeddings),
          NSNumber(value: SignalASIOpenWakeWordConstants.embeddingDimension),
        ]
      )
      let outputs = try session.run(
        withInputs: ["onnx::Flatten_0": input],
        outputNames: ["39"],
        runOptions: nil
      )
      guard let output = outputs["39"] else {
        throw SignalASIOpenWakeWordError.invalidOutput("classifier.39 is absent")
      }
      return try output.tensorData().bytes.assumingMemoryBound(to: Float.self).pointee
    } catch let error as SignalASIOpenWakeWordError {
      throw error
    } catch {
      throw SignalASIOpenWakeWordError.runtime(error)
    }
  }
}
