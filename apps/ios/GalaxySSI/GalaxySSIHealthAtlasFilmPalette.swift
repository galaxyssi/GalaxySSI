import SwiftUI

enum GalaxySSIHealthAtlasFilmPalette {
  struct Values: Equatable {
    let ground: UInt32
    let caption: UInt32
    let chapter: UInt32
    let text: UInt32
  }
  static func values(dark: Bool) -> Values {
    .init(ground: dark ? 0x263537 : 0xE7EFED, caption: dark ? 0x192C30 : 0x223A3D,
      chapter: 0xAFE2D0, text: 0xFFFFFF)
  }
  static func color(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
  }
}
