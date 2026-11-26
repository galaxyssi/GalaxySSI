import CryptoKit
import Foundation

struct AgentIOSWebFeatureHashEmbedder {
  static let standard = AgentIOSWebFeatureHashEmbedder()
  let dimensions: Int
  var modelID: String { "galaxyssi-feature-hash-\(dimensions)-v1" }
  private static let latin = try! NSRegularExpression(pattern: "[a-z0-9][a-z0-9_+.-]{1,}")
  private static let cjk = try! NSRegularExpression(pattern: #"[\u3400-\u9fff]+"#)

  init(dimensions: Int = 192) {
    precondition((32...2048).contains(dimensions))
    self.dimensions = dimensions
  }

  func embed(_ value: String) -> [Float] { embed(units: Array(value.utf16)) }

  func embedDocument(title: String, content: String, bodyLimit: Int = 64_000) -> [Float] {
    embed(units: Array(title.utf16) + [10] + Array(content.utf16.prefix(max(0, bodyLimit))))
  }

  private func embed(units: [UInt16]) -> [Float] {
    let normalized = Self.normalized(units)
    let text = String(decoding: normalized, as: UTF16.self)
    var counts: [[UInt16]: Int] = [:], order: [[UInt16]] = []
    func add(_ feature: [UInt16]) {
      if counts[feature] == nil { order.append(feature) }
      counts[feature, default: 0] += 1
    }
    let range = NSRange(location: 0, length: normalized.count)
    for match in Self.latin.matches(in: text, range: range) {
      add(Array(normalized[match.range.location..<(match.range.location + match.range.length)]))
    }
    for match in Self.cjk.matches(in: text, range: range) {
      let start = match.range.location, end = start + match.range.length
      if end - start == 1 { add([normalized[start]]) }
      else { for offset in start..<(end - 1) { add(Array(normalized[offset..<(offset + 2)])) } }
    }
    if normalized.count >= 3 {
      for offset in 0..<(normalized.count - 2) {
        let feature = Array(normalized[offset..<(offset + 3)])
        if !feature.contains(where: Self.isJVMWhitespace) { add(feature) }
      }
    }
    var vector = [Float](repeating: 0, count: dimensions)
    // Match LinkedHashMap feature order and Float32 accumulation, including hash collisions.
    for feature in order {
      let digest = SHA256.hash(data: Data(Self.jvmUTF8(feature)))
      let raw = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
      let index = Int((raw & 0x7fff_ffff_ffff_ffff) % UInt64(dimensions))
      let sign: Float = raw & 0x8000_0000_0000_0000 == 0 ? 1 : -1
      vector[index] += sign * Float(1 + log(1 + Double(counts[feature] ?? 0)))
    }
    let norm = Float(sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) }))
    let denominator: Float = norm > 0 ? norm : 1
    return vector.map { $0 / denominator }
  }

  func cosine(_ left: [Float], _ right: [Float]) -> Double {
    guard left.count == right.count, left.allSatisfy(\.isFinite), right.allSatisfy(\.isFinite) else { return 0 }
    return min(1, max(-1, zip(left, right).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }))
  }

  // Normalize valid runs without losing a JVM-style lone surrogate at a bounded body cut.
  private static func normalized(_ units: [UInt16]) -> [UInt16] {
    var result: [UInt16] = [], start = 0, index = 0
    func appendRun(_ end: Int) {
      result += String(decoding: units[start..<end], as: UTF16.self)
        .precomposedStringWithCompatibilityMapping.lowercased().utf16
    }
    while index < units.count {
      let high = (0xd800...0xdbff).contains(units[index])
      if high, index + 1 < units.count, (0xdc00...0xdfff).contains(units[index + 1]) { index += 2; continue }
      if high || (0xdc00...0xdfff).contains(units[index]) {
        appendRun(index); result.append(units[index]); index += 1; start = index
      } else { index += 1 }
    }
    appendRun(units.count)
    return result
  }

  private static func isJVMWhitespace(_ value: UInt16) -> Bool {
    (9...13).contains(value) || (28...32).contains(value) || value == 0x00a0 || value == 0x1680 ||
      (0x2000...0x200a).contains(value) || value == 0x2028 || value == 0x2029 || value == 0x202f ||
      value == 0x205f || value == 0x3000
  }

  // Java's UTF-8 encoder replaces malformed UTF-16 with '?', not Swift's U+FFFD.
  static func jvmUTF8(_ units: [UInt16]) -> [UInt8] {
    var bytes: [UInt8] = [], index = 0
    while index < units.count {
      let unit = units[index]
      var scalar = UInt32(unit)
      if (0xd800...0xdbff).contains(unit), index + 1 < units.count, (0xdc00...0xdfff).contains(units[index + 1]) {
        scalar = 0x10000 + (UInt32(unit) - 0xd800) * 1024 + UInt32(units[index + 1]) - 0xdc00
        index += 1
      } else if (0xd800...0xdfff).contains(unit) { scalar = 63 }
      if scalar < 0x80 { bytes.append(UInt8(scalar)) }
      else if scalar < 0x800 { bytes += [UInt8(0xc0 | scalar >> 6), UInt8(0x80 | scalar & 63)] }
      else if scalar < 0x10000 {
        bytes += [UInt8(0xe0 | scalar >> 12), UInt8(0x80 | (scalar >> 6) & 63), UInt8(0x80 | scalar & 63)]
      } else {
        bytes += [UInt8(0xf0 | scalar >> 18), UInt8(0x80 | (scalar >> 12) & 63), UInt8(0x80 | (scalar >> 6) & 63), UInt8(0x80 | scalar & 63)]
      }
      index += 1
    }
    return bytes
  }
}
