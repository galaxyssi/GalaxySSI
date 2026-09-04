import CryptoKit
import Foundation

struct AgentChunkedField: Equatable {
  var storedValue: String
  var chunks: [String]
  var totalLength: Int
  var sha256: String

  var chunkCount: Int {
    chunks.count
  }
}

enum AgentLargeOutputPolicy {
  static let chunkThresholdCharacters = 16 * 1024
  static let chunkCharacters = 8 * 1024
  static let previewCharacters = 4 * 1024

  static func prepare(_ value: String, includePreview: Bool) -> AgentChunkedField {
    let totalLength = value.utf16.count
    if totalLength <= chunkThresholdCharacters {
      return AgentChunkedField(
        storedValue: value,
        chunks: [],
        totalLength: totalLength,
        sha256: digest(value)
      )
    }

    return AgentChunkedField(
      storedValue: includePreview ? prefix(value, utf16Count: previewCharacters) : "",
      chunks: split(value),
      totalLength: totalLength,
      sha256: digest(value)
    )
  }

  static func split(_ value: String) -> [String] {
    let totalLength = value.utf16.count
    var chunks: [String] = []
    var offset = 0

    while offset < totalLength {
      let start = boundary(in: value, requestedOffset: offset)
      var endOffset = min(offset + chunkCharacters, totalLength)
      if endOffset < totalLength {
        let minimum = offset + chunkCharacters / 2
        let searchEnd = boundary(in: value, requestedOffset: endOffset).index
        if start.index < searchEnd {
          let searchRange = start.index..<searchEnd
          let paragraph = lastOffset(of: "\n\n", in: value, range: searchRange).flatMap {
            $0 >= minimum ? $0 : nil
          }
          let line = lastOffset(of: "\n", in: value, range: searchRange).flatMap {
            $0 >= minimum ? $0 : nil
          }
          endOffset = paragraph ?? line ?? endOffset
        }
      }

      var end = boundary(in: value, requestedOffset: endOffset)
      if end.offset <= start.offset, start.index < value.endIndex {
        let nextIndex = value.index(after: start.index)
        end = (nextIndex.utf16Offset(in: value), nextIndex)
      }
      chunks.append(String(value[start.index..<end.index]))
      offset = end.offset
    }

    return chunks
  }

  static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  static func hasDeferredContent(_ entry: AgentTranscriptEntry) -> Bool {
    (entry.textChunkCount > 0 && entry.text.utf16.count < entry.textLength) ||
      (
        entry.richOutputChunkCount > 0 &&
          entry.richOutputJson.utf16.count < entry.richOutputLength
      )
  }

  private static func prefix(_ value: String, utf16Count: Int) -> String {
    let end = boundary(in: value, requestedOffset: utf16Count).index
    return String(value[..<end])
  }

  private static func lastOffset(
    of needle: String,
    in value: String,
    range: Range<String.Index>
  ) -> Int? {
    value.range(of: needle, options: .backwards, range: range)?
      .upperBound
      .utf16Offset(in: value)
  }

  private static func boundary(
    in value: String,
    requestedOffset: Int
  ) -> (offset: Int, index: String.Index) {
    let totalLength = value.utf16.count
    var offset = safeBoundary(in: value, requestedOffset: requestedOffset)
    if offset <= 0 {
      return (0, value.startIndex)
    }
    if offset >= totalLength {
      return (totalLength, value.endIndex)
    }

    while offset > 0 {
      let utf16Index = value.utf16.index(value.utf16.startIndex, offsetBy: offset)
      if let index = String.Index(utf16Index, within: value) {
        return (offset, index)
      }
      offset -= 1
    }
    return (0, value.startIndex)
  }

  private static func safeBoundary(in value: String, requestedOffset: Int) -> Int {
    var end = min(max(0, requestedOffset), value.utf16.count)
    guard end > 0, end < value.utf16.count else {
      return end
    }

    let beforeIndex = value.utf16.index(value.utf16.startIndex, offsetBy: end - 1)
    let afterIndex = value.utf16.index(value.utf16.startIndex, offsetBy: end)
    if isHighSurrogate(value.utf16[beforeIndex]),
       isLowSurrogate(value.utf16[afterIndex]) {
      end -= 1
    }
    return end
  }

  private static func isHighSurrogate(_ value: UInt16) -> Bool {
    (0xD800...0xDBFF).contains(value)
  }

  private static func isLowSurrogate(_ value: UInt16) -> Bool {
    (0xDC00...0xDFFF).contains(value)
  }
}
