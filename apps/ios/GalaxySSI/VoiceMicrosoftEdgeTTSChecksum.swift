// SPDX-License-Identifier: LGPL-3.0-only
// Adapted from edge-tts drm.py and GalaxySSI's Android port (#3630).
// Copyright (c) rany <rany@riseup.net> and edge-tts contributors.
// Copyright (c) 2026 GalaxySSI contributors.
import Foundation

enum VoiceMicrosoftEdgeTTSChecksum {
  static func token(epochSeconds: Int64, clientToken: String) -> String {
    let windowsSeconds = epochSeconds + 11_644_473_600
    let window = windowsSeconds / 300 - (windowsSeconds % 300 < 0 ? 1 : 0)
    let input = Array("\(window * 3_000_000_000)\(clientToken)".utf8)
    let digest = digestWords(input).flatMap { bytes($0.bigEndian) }
    return hex(checksum(input, digest)) + "-" + hex(digest)
  }

  private static func digestWords(_ input: [UInt8]) -> [UInt32] {
    var schedule = [UInt32](repeating: 0, count: 64)
    schedule[14] = word([0] + Array(input.prefix(3)), at: 0)
    schedule[15] = word(input, at: 3)
    for i in 16..<30 {
      var value = initialSchedule[i - 16]
      if i - 2 >= 14 { value = value &+ (sigma1(schedule[i - 2]) ^ (i == 16 ? 0x000B92C0 : 0)) }
      if i - 7 >= 14 { value = value &+ schedule[i - 7] }
      if i - 15 >= 14 { value = value &+ (sigma0(schedule[i - 15]) ^ (i == 29 ? 0x059C0B80 : 0)) }
      schedule[i] = value
    }
    schedule[30] = sigma1(schedule[28]) &+ schedule[23] &+ sigma0(schedule[15]) &+
      schedule[14] &+ adjustment &- constants[14]
    expand(&schedule, from: 31)
    var state = zip(initial, rounds(initialState, schedule, from: 14)).map { $0.0 &+ $0.1 }

    // The initial state represents a fixed prefix, so padding counts that prefix too.
    let length = 57 + input.count
    var padded = Array(input.dropFirst(7)) + [0x80]
    padded += [UInt8](repeating: 0, count: (55 - length % 64 + 64) % 64)
    var bitCount = (UInt64(length) * 8).bigEndian
    padded += withUnsafeBytes(of: &bitCount) { Array($0) }
    for offset in stride(from: 0, to: padded.count, by: 64) {
      for i in 0..<16 { schedule[i] = word(padded, at: offset + i * 4) }
      expand(&schedule, from: 16)
      state = zip(state, rounds(state, schedule)).map { $0.0 &+ $0.1 }
    }
    return state
  }

  private static func expand(_ schedule: inout [UInt32], from: Int) {
    for i in from..<64 {
      schedule[i] = sigma1(schedule[i - 2]) &+ schedule[i - 7] &+ sigma0(schedule[i - 15]) &+ schedule[i - 16]
    }
  }

  private static func rounds(_ state: [UInt32], _ schedule: [UInt32], from: Int = 0) -> [UInt32] {
    var a = state[0], b = state[1], c = state[2], d = state[3]
    var e = state[4], f = state[5], g = state[6], h = state[7]
    for i in from..<64 {
      let constant = from == 14 && i == 14 ? adjustment : constants[i]
      let t1 = h &+ (ror(e, 6) ^ ror(e, 11) ^ ror(e, 25)) &+ (g ^ (e & (f ^ g))) &+ constant &+ schedule[i]
      let t2 = (ror(a, 2) ^ ror(a, 13) ^ ror(a, 22)) &+ ((a & b) | (c & (a | b)))
      (h, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
    }
    return [a, b, c, d, e, f, g, h]
  }

  private static func checksum(_ input: [UInt8], _ digest: [UInt8]) -> [UInt8] {
    let keys = [word(digest, at: 0).byteSwapped | 1, word(digest, at: 4).byteSwapped | 1]
    let factors = keys.map { $0 &* 0x82893933 }
    var terms = coefficients.enumerated().map { $0.element &* factors[$0.offset % 2] }
    var offsets = checksumOffsets
    var buffer = [UInt8(0)] + input
    buffer += [UInt8](repeating: 0, count: (8 - buffer.count % 8) % 8)
    for index in 0..<(buffer.count / 4) {
      let value = word(buffer, at: index * 4).byteSwapped
      let even = index % 2 == 0
      let term = value &* keys[index % 2]
      let offset = ror(value, 16) &* (even ? 0xEF0569FB : 0xC31713DB)
      terms.append(index == 0 ? term &+ (0xF2F90B1A &* factors[0]) : term)
      offsets.append(index == 0 ? offset &+ 0x0B1A0000 : offset)
    }
    var swapAcc: UInt32 = 0, swapLast: UInt32 = 0, state: UInt32 = 0, acc: UInt32 = 0
    for i in stride(from: 0, to: terms.count, by: 2) {
      let x = terms[i], y = terms[i + 1]
      var q = ror(offsets[i] &+ x, 16) &* 0x76F50F34
      swapAcc = swapAcc &+ (ror(q, 16) &* 0xC3EFEA97) &+ q
      q = ror(offsets[i + 1] &+ y, 16) &* 0x1881CE3C
      swapLast = (ror(q, 16) &* 0x35BD1EC9) &+ q
      swapAcc = swapAcc &+ swapLast
      state = ror((state &* keys[0]) &+ x, 16) &* 0xCF98B111
      state = ror(state, 16) &* 0x87085B9F
      state = ror(state, 16) &* 0x12CEB96D
      state = ror(state, 16) &* 0x257E1D83
      acc = acc &+ state
      var t = ror((state &* keys[1]) &+ y, 16) &* 0xA27416F5
      t = ror(t, 16) &* 0xD38396FF
      state = ror(ror(t, 16) &* 0x7C932B89, 16) &* 0xBFA49F69
      acc = acc &+ state
    }
    return bytes((swapLast ^ state).littleEndian) + bytes((swapAcc ^ acc).littleEndian)
  }

  private static func word(_ input: [UInt8], at i: Int) -> UInt32 {
    (UInt32(input[i]) << 24) | (UInt32(input[i + 1]) << 16) | (UInt32(input[i + 2]) << 8) | UInt32(input[i + 3])
  }

  private static func bytes(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value) { Array($0) } }
  private static func ror(_ x: UInt32, _ n: Int) -> UInt32 { (x >> n) | (x << (32 - n)) }
  private static func sigma0(_ x: UInt32) -> UInt32 { ror(x, 7) ^ ror(x, 18) ^ (x >> 3) }
  private static func sigma1(_ x: UInt32) -> UInt32 { ror(x, 17) ^ ror(x, 19) ^ (x >> 10) }
  private static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", Int($0)) }.joined() }

  private static let adjustment: UInt32 = 0xC9DC06A7
  private static let initial: [UInt32] = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  ]
  private static let initialState: [UInt32] = [
    0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A, 0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2,
  ]
  private static let initialSchedule: [UInt32] = [
    0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, 0xC0DD25A0,
    0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33, 0xD258B060, 0x72766564,
  ]
  private static let constants: [UInt32] = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
  ]
  private static let coefficients: [UInt32] = [
    0xE82E91B1, 0x44DE24C6, 0x3BEB65BC, 0xC89C5933, 0x8D1EC211, 0x314EF5D5, 0xE92491B1,
    0xF0A5B9D5, 0x06064CF3, 0xDA79FA60, 0xBED20560, 0x89F9C9F8, 0x35FA38C6, 0xCB49E3C6,
  ]
  private static let checksumOffsets: [UInt32] = [
    0xB32700D0, 0x88DFF51D, 0x29514038, 0xB328CBDF, 0xD405B4D5, 0x26E55F3C, 0x607801C6,
    0x82B2C1FB, 0xFA51A3DA, 0x207CC464, 0x3C3C74F3, 0xD2D14B61, 0xBB04A2C1, 0xC5626167,
  ]
}
