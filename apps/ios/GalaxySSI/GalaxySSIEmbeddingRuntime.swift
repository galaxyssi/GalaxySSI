import Foundation

enum GalaxySSIEmbeddingRuntimeError: Error, Equatable {
  case unavailable
  case modelLoadFailed(String)
  case inferenceFailed(String)
  case closed
  case invalidVector
}

enum GalaxySSIEmbeddingVector {
  static func normalized(_ values: [Float]) throws -> [Float] {
    let squaredNorm = values.reduce(0.0) { partial, value in
      partial + Double(value) * Double(value)
    }
    guard !values.isEmpty, squaredNorm.isFinite, squaredNorm > 0 else {
      throw GalaxySSIEmbeddingRuntimeError.invalidVector
    }
    let norm = sqrt(squaredNorm)
    let normalized = values.map { Float(Double($0) / norm) }
    guard normalized.allSatisfy(\.isFinite) else {
      throw GalaxySSIEmbeddingRuntimeError.invalidVector
    }
    return normalized
  }

  static func cosine(_ left: [Float], _ right: [Float]) throws -> Float {
    guard !left.isEmpty, left.count == right.count else {
      throw GalaxySSIEmbeddingRuntimeError.invalidVector
    }
    let lhs = try normalized(left)
    let rhs = try normalized(right)
    return zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
  }
}

#if GALAXYSSI_NATIVE_LLAMA
final class GalaxySSIEmbeddingRuntime {
  private let queue = DispatchQueue(label: "com.galaxyssi.embedding-runtime", qos: .utility)
  private var handle: Int64

  private init(handle: Int64) {
    self.handle = handle
  }

  deinit {
    let current = handle
    if current != 0 { galaxyssi_embedding_close(current) }
  }

  static func open(modelURL: URL, contextTokens: Int, threads: Int) async throws -> GalaxySSIEmbeddingRuntime {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        let handle = modelURL.path.withCString {
          galaxyssi_embedding_open($0, Int32(contextTokens), Int32(threads))
        }
        guard handle != 0 else {
          continuation.resume(throwing: GalaxySSIEmbeddingRuntimeError.modelLoadFailed(lastEmbeddingError()))
          return
        }
        continuation.resume(returning: GalaxySSIEmbeddingRuntime(handle: handle))
      }
    }
  }

  func embed(_ text: String) async throws -> [Float] {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        guard handle != 0 else {
          continuation.resume(throwing: GalaxySSIEmbeddingRuntimeError.closed)
          return
        }
        let input = Data(text.utf8)
        guard !input.isEmpty else {
          continuation.resume(throwing: GalaxySSIEmbeddingRuntimeError.inferenceFailed("Embedding input is empty"))
          return
        }
        var output: UnsafeMutablePointer<Float>?
        var dimensions: Int32 = 0
        let result = input.withUnsafeBytes { bytes in
          galaxyssi_embedding_encode(
            handle,
            bytes.bindMemory(to: CChar.self).baseAddress,
            Int32(input.count),
            &output,
            &dimensions
          )
        }
        guard result == 0, let output, dimensions > 0 else {
          continuation.resume(throwing: GalaxySSIEmbeddingRuntimeError.inferenceFailed(Self.lastEmbeddingError()))
          return
        }
        let values = Array(UnsafeBufferPointer(start: output, count: Int(dimensions)))
        galaxyssi_embedding_free(output, dimensions)
        guard values.allSatisfy(\.isFinite) else {
          continuation.resume(throwing: GalaxySSIEmbeddingRuntimeError.invalidVector)
          return
        }
        continuation.resume(returning: values)
      }
    }
  }

  func close() async {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        if handle != 0 {
          galaxyssi_embedding_close(handle)
          handle = 0
        }
        continuation.resume()
      }
    }
  }

  private static func lastEmbeddingError() -> String {
    galaxyssi_embedding_last_error().map { String(cString: $0) } ?? ""
  }
}

@_silgen_name("galaxyssi_embedding_open")
private func galaxyssi_embedding_open(
  _ modelPath: UnsafePointer<CChar>,
  _ contextTokens: Int32,
  _ threads: Int32
) -> Int64

@_silgen_name("galaxyssi_embedding_encode")
private func galaxyssi_embedding_encode(
  _ handle: Int64,
  _ utf8Text: UnsafePointer<CChar>?,
  _ utf8Length: Int32,
  _ output: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>,
  _ dimensions: UnsafeMutablePointer<Int32>
) -> Int32

@_silgen_name("galaxyssi_embedding_free")
private func galaxyssi_embedding_free(_ output: UnsafeMutablePointer<Float>?, _ dimensions: Int32)

@_silgen_name("galaxyssi_embedding_close")
private func galaxyssi_embedding_close(_ handle: Int64)

@_silgen_name("galaxyssi_embedding_last_error")
private func galaxyssi_embedding_last_error() -> UnsafePointer<CChar>?
#else
final class GalaxySSIEmbeddingRuntime {
  static func open(modelURL: URL, contextTokens: Int, threads: Int) async throws -> GalaxySSIEmbeddingRuntime {
    throw GalaxySSIEmbeddingRuntimeError.unavailable
  }

  func embed(_ text: String) async throws -> [Float] {
    throw GalaxySSIEmbeddingRuntimeError.unavailable
  }

  func close() async {}
}
#endif
