import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func vulvarScene(_ step: Int, _ t: Double) {
    let g = GalaxySSIHealthAtlasVulvarGeometry.self, f = GalaxySSIHealthAtlasVulvarFeatures.self
    var plate = context; plate.translateBy(x: 0, y: 40)
    let art = copy(plate)
    switch step {
    case 0:
      vulvarImage("Region")
      art.vulvarPairedTrace(g.regionOuterTrack, 0x914F48, g.reveal(t, 0, 0.56))
      art.vulvarPairedTrace(g.regionInnerMarginTrack, 0x644671, g.reveal(t, 0.32, 0.95))
      vulvarCallout(f.region[1], 55, 144, 87, 149, 0x914F48)
      vulvarCallout(f.region[2], 305, 136, 272, 141, 0x644671)
    case 1:
      vulvarImage("OuterSection")
      art.vulvarPairedTrace(g.sectionSkinTrack, 0x914F48, g.reveal(t, 0, 0.67))
      art.vulvarPairedTrace(g.sectionFatTrack, 0x845928, g.reveal(t, 0.28, 0.96))
      vulvarCallout(f.outer[0], 105, 85, 105, 94, 0x914F48)
      vulvarCallout(f.outer[1], 75, 308, 75, 290, 0x845928)
    case 2:
      vulvarImage("InnerCloseup")
      let p = g.reveal(t, 0, 0.91)
      art.vulvarTrace(g.innerLeftTrack, 0x644671, p); art.vulvarTrace(g.innerRightTrack, 0x644671, p)
      vulvarCallout(f.inner[1], 263, 82, 263, 92, 0x644671)
      vulvarCallout(f.inner[2], 181, 317, 181, 300, 0x346C60)
    case 3:
      line(180, 100, 180, 250, 0xABBDB6, 1)
      let p = g.reveal(t, 0, 0.92)
      vulvarProfile(18, longerLeft: false, progress: p); vulvarProfile(194, longerLeft: true, progress: p)
      label("vulvar_protection_profile_one", 92, 263, 130); label("vulvar_protection_profile_two", 268, 263, 130)
      label("vulvar_protection_inner_folds", 180, 303, 150); line(121, 299, 138, 299, 0x644671, 2.1)
    default:
      vulvarImage("Region")
      art.vulvarTrace(g.regionalOutlineTrack, 0x6D564D, g.reveal(t, 0, 0.72))
      art.vulvarPairedTrace(g.regionInnerMarginTrack, 0x346C60, g.reveal(t, 0.28, 0.98))
      vulvarCallout(f.region[0], 58, 86, 78, 94, 0x6D564D)
      vulvarCallout(f.region[3], 180, 321, 180, 303, 0x346C60)
    }
  }
  private func vulvarImage(_ suffix: String) {
    context.draw(Image("HealthAtlasRegionalVulvarProtection" + suffix), in: CGRect(x: 0, y: 40, width: 360, height: 280))
  }
  private func vulvarProfile(_ x: Double, longerLeft: Bool, progress: Double) {
    let g = GalaxySSIHealthAtlasVulvarGeometry.self
    var local = context; local.translateBy(x: x, y: 0)
    let art = copy(local)
    art.vulvarSurface(g.profileBase, 145, 231, 0xF4D4BC, 0xCB9383, 0x914F48)
    art.oval(54, 189, 94, 204, fill: 0xB9D4C3, border: 0x346C60)
    art.vulvarProfileFold(longerLeft, progress)
    local.translateBy(x: 148, y: 0); local.scaleBy(x: -1, y: 1)
    copy(local).vulvarProfileFold(false, progress)
  }
  private func vulvarProfileFold(_ longer: Bool, _ progress: Double) {
    let g = GalaxySSIHealthAtlasVulvarGeometry.self
    vulvarSurface(longer ? g.longFold : g.shortFold, 119, 202, 0xE8D5E7, 0xB18EAE, 0x644671)
    vulvarTrace(longer ? g.longFoldTrack : g.shortFoldTrack, 0x644671, progress)
  }
  private func vulvarSurface(_ path: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ color: UInt32) {
    gradient(path, top, bottom, from, to); stroke(path, color, 1.3)
  }
  private func vulvarCallout(_ feature: GalaxySSIHealthAtlasVulvarFeatures.Feature, _ textX: Double, _ baseline: Double, _ startX: Double, _ startY: Double, _ color: UInt32) {
    let x = feature.x * 360, y = feature.y * 280 + 40
    line(startX, startY, x, y, color, 1.05); disc(x, y, 2.6, color, border: Self.cream)
    label(feature.key, textX, baseline, 104)
  }
  private func vulvarPairedTrace(_ track: GalaxySSIHealthAtlasRegionalTrack, _ color: UInt32, _ progress: Double) {
    vulvarTrace(track, color, progress)
    var local = context; local.translateBy(x: 360, y: 0); local.scaleBy(x: -1, y: 1)
    copy(local).vulvarTrace(track, color, progress)
  }
  private func vulvarTrace(_ track: GalaxySSIHealthAtlasRegionalTrack, _ color: UInt32, _ progress: Double) {
    if progress > 0 {
      let segment = track.path.trimmedPath(from: 0, to: progress)
      stroke(segment, Self.cream, 4); stroke(segment, color, 2.05)
    }
  }
}
