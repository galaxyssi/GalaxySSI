import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func obliqueBands(_ motion: GalaxySSIHealthAtlasObliqueMotion) {
    for index in [1,0,3,2] {
      let band = motion.bands[index], external = band.external, effort = band.effort
      let color: UInt32 = external ? 0x9B5B63 : 0x665A88
      obliqueTissue(band.shape,external ? 104 : 140,external ? 178 : 220,
        external ? 0xEFC9BC : 0xE1D7EB,external ? 0xCF8E94 : 0xAC9DC4,color)
      var quiet = context; quiet.opacity = Double(Int(86*(1-effort)))/255
      copy(quiet).fill(band.shape,Self.cream)
      var tone = context; tone.opacity = Double(Int(88*effort))/255
      copy(tone).fill(band.shape,color)
      stroke(band.strands,external ? 0xF8DED3 : 0xEEE6F2,0.95+0.25*effort)
    }
  }
}
