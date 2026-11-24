import Foundation

struct GalaxySSIHealthAtlasErectorMotion {
  let ease: Double
  let flexion: Double
  let emphasis: Double
  let posteriorEmphasis: Double
  init(_ step: Int, _ t: Double) {
    let t = t.isFinite ? min(1,max(0,t)) : 0, ease = t*t*(3-2*t)
    self.ease = ease
    flexion = step == 1 ? 1-ease : 0
    emphasis = step == 1 ? 0.42+0.58*sin(.pi*ease) : step == 3 ? 0.42+0.58*ease : 0.25+0.12*ease
    posteriorEmphasis = (1+sin(2 * .pi*(t-0.25)))/2
  }
  static func shift(_ y: Double, _ flexion: Double) -> Double { 49*flexion*pow(max(0,(250-y)/185),1.45) }
  static func spineX(_ y: Double, _ flexion: Double) -> Double { 151-13*sin((y-69)*(2 * .pi/198))+shift(y,flexion) }
}
