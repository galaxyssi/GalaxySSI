import SwiftUI

private typealias CoronaryHeart = GalaxySSIHealthAtlasCoronaryGeometry
private typealias CoronaryArteries = GalaxySSIHealthAtlasCoronaryRoutes
private typealias CoronaryHeartTime = GalaxySSIHealthAtlasCoronaryMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func coronaryHeart(step: Int, t: Double, squeeze: Double) {
    gradient(CoronaryHeart.venaCava,52,110,0xDFEBEC,0x96B8C1); stroke(CoronaryHeart.venaCava,0x789AA6,1.5)
    gradient(CoronaryHeart.arch,20,111,0xF7B5A0,0xC76B70); stroke(CoronaryHeart.arch,CoronaryHeart.wall,1.5)
    line(218,47,227,42,0xFFC5AC,2.3)
    gradient(CoronaryHeart.pulmonaryTrunk,52,110,0xDFEBEC,0x96B8C1); stroke(CoronaryHeart.pulmonaryTrunk,0x789AA6,1.5)
    gradient(CoronaryHeart.heart,84,215,0xF7CBB3,0xCC777E); stroke(CoronaryHeart.heart,CoronaryHeart.wall,1.5)
    gradient(CoronaryHeart.lvSurface,106,215,0xECB09B,0xB86675); stroke(CoronaryHeart.lvSurface,0xB67577,1.5)
    stroke(CoronaryHeart.atrialGroove,0xB9797A,1.35)
    gradient(CoronaryHeart.exposedRoot,20,111,0xF7B5A0,0xC76B70); stroke(CoronaryHeart.exposedRoot,CoronaryHeart.wall,1.5)
    stroke(CoronaryHeart.rootCusp,0xFBE0C2,1.9)
    let prominent = step != 4
    coronaryVessel(CoronaryArteries.rightCoronary,width: 8,prominent: prominent)
    coronaryVessel(CoronaryArteries.rightBranch,width: 4.2,prominent: prominent)
    coronaryVessel(CoronaryArteries.leftMain,width: 8.5,prominent: prominent)
    coronaryVessel(CoronaryArteries.descending,width: 7.5,prominent: prominent)
    coronaryVessel(CoronaryArteries.circumflex,width: 6.4,prominent: prominent)
    coronaryVessel(CoronaryArteries.diagonal,width: 4.8,prominent: prominent)
    disc(145,95,3.9,CoronaryHeart.artery,border: Self.cream); disc(178,94,3.9,CoronaryHeart.artery,border: Self.cream)
    switch step {
    case 0:
      coronaryStream(CoronaryArteries.rightCoronary,time: t,speed: 0.36,count: 1,color: Self.cream,strength: 0.45,span: 0.55)
      coronaryStream(CoronaryArteries.leftMain,time: t,speed: 0.75,count: 1,color: Self.cream)
    case 4:
      stroke(CoronaryArteries.anteriorVein.path,CoronaryHeart.vein,6.4); stroke(CoronaryArteries.anteriorVein.path,CoronaryHeart.veinFill,3.9)
      coronaryStream(CoronaryArteries.anteriorVein,time: t,speed: 1.38,count: 3,color: Self.cream)
    default:
      let cycle = Double(step - 1) + t
      coronaryStream(CoronaryArteries.rightCoronary,time: cycle,speed: 1.43,count: 2,color: Self.cream)
      coronaryStream(CoronaryArteries.rightBranch,time: cycle + 0.12,speed: 1.55,count: 1,color: Self.cream)
      coronaryStream(CoronaryArteries.leftMain,time: cycle,speed: 1.5,count: 1,color: Self.cream)
      let leftFlow = CoronaryHeartTime.leftFlow(squeeze), leftT = CoronaryHeartTime.wallTime(step: step,t: t)
      coronaryStream(CoronaryArteries.descending,time: leftT,speed: 1.52,count: 3,color: Self.cream,strength: leftFlow)
      coronaryStream(CoronaryArteries.circumflex,time: leftT,speed: 1.3,count: 2,color: Self.cream,strength: leftFlow)
      coronaryStream(CoronaryArteries.diagonal,time: leftT,speed: 1.48,count: 1,color: Self.cream,strength: leftFlow)
      stroke(Path(ellipseIn: CGRect(x: 206, y: 158, width: 25, height: 25)),0x8B5B60,1.35)
      line(224,182,250,222,CoronaryHeart.leader,1)
    }
    label("coronary_story_aortic_root",77,54,112); line(104,59,144,82,CoronaryHeart.leader,1)
    label("coronary_story_right_ostium",67,86,118); line(108,89,140,95,CoronaryHeart.leader,1)
    label("coronary_story_left_ostium",290,86,116); line(249,90,184,94,CoronaryHeart.leader,1)
    label("coronary_story_rca",55,163,100); line(99,157,105,146,CoronaryHeart.leader,1)
    label("coronary_story_lad",115,202,88); line(148,197,194,190,CoronaryHeart.leader,1)
    label("coronary_story_circumflex",301,139,107); line(269,134,243,128,CoronaryHeart.leader,1)
  }
  private func coronaryVessel(_ track: GalaxySSIHealthAtlasCoronaryRoutes.Track, width: Double, prominent: Bool) {
    stroke(track.path,prominent ? CoronaryHeart.artery : 0xAC7073,width)
    stroke(track.path,prominent ? CoronaryHeart.arteryFill : 0xDCA29A,width * 0.58)
  }
}
