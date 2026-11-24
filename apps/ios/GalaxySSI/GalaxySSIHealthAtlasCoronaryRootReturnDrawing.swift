import SwiftUI

private typealias CoronaryRoot = GalaxySSIHealthAtlasCoronaryGeometry
private typealias CoronaryReturn = GalaxySSIHealthAtlasCoronaryRoutes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func coronaryRoot(_ t: Double) {
    gradient(CoronaryRoot.rootSection,246,322,0xFFD9BD,0xE09082); stroke(CoronaryRoot.rootSection,CoronaryRoot.wall,1.5)
    oval(145,243,215,254,fill: 0xF9BCA8,border: CoronaryRoot.wall); stroke(CoronaryRoot.rootValve,CoronaryRoot.wall,2.1)
    for (index, branch) in CoronaryReturn.ostialFlows.enumerated() {
      let segment = branch.path.trimmedPath(from: 0.53,to: 1)
      stroke(segment,CoronaryRoot.artery,10); stroke(segment,CoronaryRoot.arteryFill,6.4)
      disc(index == 0 ? 132 : 228,291,5,CoronaryRoot.artery,border: Self.cream)
      coronaryStream(branch,time: t,speed: 1.12,count: 2,color: 0x763345)
    }
    label("coronary_story_root_section",180,239,179)
    label("coronary_story_rca",71,321,119); label("coronary_story_lca",289,321,119)
    line(73,306,73,309,CoronaryRoot.leader,1); line(287,306,287,309,CoronaryRoot.leader,1)
    line(181,320,181,339,CoronaryRoot.leader,1); label("coronary_story_aortic_valve",180,352,138)
  }
  func coronaryReturn(_ t: Double) {
    gradient(CoronaryRoot.posteriorHeart,249,331,0xF7D1BB,0xD58E90); stroke(CoronaryRoot.posteriorHeart,CoronaryRoot.wall,1.5)
    gradient(CoronaryRoot.posteriorAtrium,52,110,0xDFEBEC,0x96B8C1); stroke(CoronaryRoot.posteriorAtrium,CoronaryRoot.vein,1.5)
    stroke(CoronaryReturn.tributary.path,CoronaryRoot.vein,4); stroke(CoronaryReturn.tributary.path,CoronaryRoot.veinFill,2.1)
    stroke(CoronaryReturn.cardiacVein.path,CoronaryRoot.vein,6.4); stroke(CoronaryReturn.cardiacVein.path,CoronaryRoot.veinFill,3.8)
    stroke(CoronaryReturn.coronarySinus.path,CoronaryRoot.vein,11); stroke(CoronaryReturn.coronarySinus.path,CoronaryRoot.veinFill,7.2)
    coronaryStream(CoronaryReturn.cardiacVein,time: t,speed: 1.12,count: 2,color: Self.cream)
    coronaryStream(CoronaryReturn.tributary,time: t + 0.34,speed: 1.1,count: 1,color: Self.cream)
    coronaryStream(CoronaryReturn.coronarySinus,time: t - 0.15,speed: 1.38,count: 3,color: Self.cream)
    label("coronary_story_posterior",109,240,161); line(239,272,270,276,CoronaryRoot.leader,1)
    label("coronary_story_right_atrium",308,287,92)
    line(111,276,81,302,CoronaryRoot.leader,1); line(81,302,81,333,CoronaryRoot.leader,1); line(188,286,211,332,CoronaryRoot.leader,1)
    label("coronary_story_cardiac_vein",89,348,141); label("coronary_story_sinus",237,348,140)
  }
}
