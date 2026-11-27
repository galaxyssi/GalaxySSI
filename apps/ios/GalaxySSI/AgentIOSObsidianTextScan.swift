import CryptoKit
import Darwin
import Foundation

enum AgentIOSObsidianTextScan {
  struct Result { let prefix: String; let hash: String }
  static func read(_ url: URL, maximumUTF16: Int) throws -> Result {
    guard maximumUTF16 >= 0 else { throw AgentKnowledgeDatabaseError.corruptRecord }
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? file.close() }
    var info = stat()
    guard Darwin.fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    var hash = SHA256(), tail = Data(), prefix = "", retained = 0, retaining = true
    while true {
      try Task.checkCancellation()
      let chunk = try file.read(upToCount: 8_192) ?? Data()
      if chunk.isEmpty { guard tail.isEmpty else { throw AgentKnowledgeDatabaseError.corruptRecord }; break }
      hash.update(data: chunk)
      var bytes = tail; bytes.append(chunk)
      var count = bytes.count
      if String(data: bytes, encoding: .utf8) == nil {
        var found = false
        for suffix in 1...min(3, bytes.count) {
          let end = bytes.count - suffix
          if partial(Array(bytes.suffix(suffix))), String(data: bytes.prefix(end), encoding: .utf8) != nil {
            count = end; found = true; break
          }
        }
        guard found else { throw AgentKnowledgeDatabaseError.corruptRecord }
      }
      let text = String(decoding: bytes.prefix(count), as: UTF8.self)
      if retaining {
        for scalar in text.unicodeScalars {
          let units = scalar.value > 0xFFFF ? 2 : 1
          guard units <= maximumUTF16 - retained else { retaining = false; break }
          prefix.unicodeScalars.append(scalar); retained += units
        }
      }
      tail = Data(bytes.suffix(bytes.count - count))
    }
    return Result(prefix: prefix, hash: hash.finalize().map { String(format: "%02x", $0) }.joined())
  }
  private static func partial(_ bytes: [UInt8]) -> Bool {
    guard let first = bytes.first else { return false }
    let expected: Int
    switch first { case 0xC2...0xDF: expected = 2; case 0xE0...0xEF: expected = 3; case 0xF0...0xF4: expected = 4; default: return false }
    guard bytes.count < expected, bytes.dropFirst().allSatisfy({ (0x80...0xBF).contains($0) }) else { return false }
    if bytes.count > 1 {
      if first == 0xE0 && bytes[1] < 0xA0 || first == 0xED && bytes[1] > 0x9F ||
         first == 0xF0 && bytes[1] < 0x90 || first == 0xF4 && bytes[1] > 0x8F { return false }
    }
    return true
  }
}
