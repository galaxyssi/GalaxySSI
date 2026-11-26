import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Classification only. DNS preflight does not pin URLSession/WK connections.
enum AgentIOSPublicAddressPolicy {
  static func blocksHost(_ value: String) -> Bool {
    var host = value.lowercased()
    if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
    if host.hasSuffix(".") { host.removeLast() }
    guard !host.isEmpty, !host.contains("%"), !host.contains(where: { $0.isWhitespace }),
      !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return true }
    if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
    if let bytes = ipv4(host) { return blocksIPv4(bytes) }
    if let bytes = ipv6(host) { return blocksIPv6(bytes) }
    if host.contains(":") || host.contains("[") || host.contains("]") { return true }
    // inet_pton deliberately rejects the legacy inet_aton forms. Do not let a
    // subsequent resolver reinterpret a short/octal/hex numeric host as loopback.
    return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
      if part.hasPrefix("0x") { return part.dropFirst(2).allSatisfy(\.isHexDigit) }
      return !part.isEmpty && part.allSatisfy(\.isNumber)
    }
  }

  static func isNumericHost(_ value: String) -> Bool {
    let host = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    return ipv4(host) != nil || ipv6(host) != nil
  }

  private static func blocksIPv4(_ bytes: [UInt8]) -> Bool {
    let first = bytes[0], second = bytes[1]
    if first == 0 || first == 10 || first == 127 || first >= 224 { return true }
    if first == 100 && (64...127).contains(second) { return true }
    if first == 169 && second == 254 { return true }
    if first == 172 && (16...31).contains(second) { return true }
    if first == 192 && second == 168 { return true }
    return first == 198 && (18...19).contains(second)
  }

  private static func blocksIPv6(_ bytes: [UInt8]) -> Bool {
    if bytes[0] == 0xff || bytes[0] & 0xfe == 0xfc { return true }
    // fe80::/10 link-local and deprecated fec0::/10 site-local, not just fe80:.
    if bytes[0] == 0xfe && (bytes[1] & 0xc0 == 0x80 || bytes[1] & 0xc0 == 0xc0) { return true }
    if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
      return blocksIPv4(Array(bytes.suffix(4)))
    }
    // Unspecified, loopback and deprecated IPv4-compatible forms.
    if bytes.prefix(12).allSatisfy({ $0 == 0 }) { return true }
    // RFC 6052 well-known NAT64 /96: classify the embedded IPv4 too, without
    // rejecting public DNS64 destinations on IPv6-only networks.
    if bytes.prefix(12).elementsEqual([0, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0]) {
      return blocksIPv4(Array(bytes.suffix(4)))
    }
    return false
  }

  private static func ipv4(_ host: String) -> [UInt8]? {
#if canImport(Darwin) || canImport(Glibc)
    var address = in_addr()
    guard host.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else { return nil }
    return withUnsafeBytes(of: address) { Array($0) }
#else
    return nil
#endif
  }

  private static func ipv6(_ host: String) -> [UInt8]? {
#if canImport(Darwin) || canImport(Glibc)
    var address = in6_addr()
    guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else { return nil }
    return withUnsafeBytes(of: address) { Array($0) }
#else
    return nil
#endif
  }
}
