import SwiftUI

enum GalaxySSIHealthAtlasRectusDeflection {
  typealias G = GalaxySSIHealthAtlasRectusGeometry
  static let wall = GalaxySSIHealthAtlasRectusContours(G.wall)
  static let ribCage = GalaxySSIHealthAtlasRectusContours(G.ribCage)
  static let ribLines = GalaxySSIHealthAtlasRectusContours(G.ribLines)
  static let cartilage = GalaxySSIHealthAtlasRectusContours(G.cartilage)
  static let spine = GalaxySSIHealthAtlasRectusContours(G.spine)
  static let discs = GalaxySSIHealthAtlasRectusContours(G.discs)
  static let rectus = GalaxySSIHealthAtlasRectusContours(G.rectus)
  static let fascicles = GalaxySSIHealthAtlasRectusContours(G.fascicles)
  static let intersections = GalaxySSIHealthAtlasRectusContours(G.intersections)
}
