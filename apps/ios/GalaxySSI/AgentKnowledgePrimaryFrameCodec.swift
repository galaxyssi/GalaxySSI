import Compression
import Foundation

enum AgentKnowledgePrimaryFrameCodec {
  static let maximumPlainBytes = 64 * 1_024
  static let maximumEncodedBytes = 128 * 1_024

  private struct Frame: Codable {
    var version: Int
    var codec: String
    var plainBytes: Int
    var payload: Data
  }

  static func encode(_ plain: Data) throws -> Data {
    guard (1...maximumPlainBytes).contains(plain.count) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    var buffer = [UInt8](repeating: 0, count: plain.count)
    defer { _ = buffer.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
    let count = buffer.withUnsafeMutableBufferPointer { destination in
      plain.withUnsafeBytes { source in
        compression_encode_buffer(destination.baseAddress!, destination.count,
          source.bindMemory(to: UInt8.self).baseAddress!, plain.count, nil, COMPRESSION_ZLIB)
      }
    }
    let compressed = count > 0 && count < plain.count
    let frame = Frame(version: 1, codec: compressed ? "zlib" : "raw", plainBytes: plain.count,
      payload: compressed ? Data(buffer.prefix(count)) : plain)
    let encoded = try JSONEncoder().encode(frame)
    guard encoded.count <= maximumEncodedBytes else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return encoded
  }

  static func decode(_ encoded: Data) throws -> Data {
    guard !encoded.isEmpty, encoded.count <= maximumEncodedBytes else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let frame = try JSONDecoder().decode(Frame.self, from: encoded)
    guard frame.version == 1, (1...maximumPlainBytes).contains(frame.plainBytes), !frame.payload.isEmpty,
          frame.payload.count <= maximumPlainBytes else { throw AgentKnowledgeDatabaseError.corruptRecord }
    if frame.codec == "raw" {
      guard frame.payload.count == frame.plainBytes else { throw AgentKnowledgeDatabaseError.corruptRecord }
      return frame.payload
    }
    guard frame.codec == "zlib" else { throw AgentKnowledgeDatabaseError.corruptRecord }
    // The extra byte detects expansion beyond the authenticated frame length.
    var buffer = [UInt8](repeating: 0, count: frame.plainBytes + 1)
    defer { _ = buffer.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
    let count = buffer.withUnsafeMutableBufferPointer { destination in
      frame.payload.withUnsafeBytes { source in
        compression_decode_buffer(destination.baseAddress!, destination.count,
          source.bindMemory(to: UInt8.self).baseAddress!, frame.payload.count, nil, COMPRESSION_ZLIB)
      }
    }
    guard count == frame.plainBytes else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return Data(buffer.prefix(count))
  }
}
