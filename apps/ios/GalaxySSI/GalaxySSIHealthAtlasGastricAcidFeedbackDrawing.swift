import SwiftUI

private typealias GastricFeedback = GalaxySSIHealthAtlasGastricAcidGeometry
private typealias GastricFeedbackTime = GalaxySSIHealthAtlasGastricAcidMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricAcidFeedback(_ t: Double) {
    let p = GastricFeedbackTime.feedback(t), output = GastricFeedbackTime.output(t)
    var local = context; local.translateBy(x: 73, y: -44); local.scaleBy(x: 0.76, y: 0.76)
    let stomach = copy(local); stomach.gastricAcidStomachPlate()
    for i in 0...3 { stomach.disc(82 + Double(i) * 10,194 - Double(i % 2) * 11,3.2,GastricFeedback.acid,border: Self.cream) }
    gastricAcidCallout("gastric_acid_story_stomach_acid",266,84,156,225,90,166,100)
    arrow(143,137,143,168,Self.teal); disc(143,139 + 27 * p,4,Self.teal,border: Self.cream)
    label("gastric_acid_story_somatostatin",219,178,151); disc(143,174,4,Self.teal,border: Self.cream)
    line(143,181,143,224,Self.teal,1.65); line(134,224,152,224,Self.teal,2 + p * 2)
    if p > 0.3 { disc(143,181 + 40 * ((p - 0.3) / 0.7),4,Self.teal,border: Self.cream) }
    label("gastric_acid_story_gastrin",219,251,145); disc(143,247,3 + 3 * output,GastricFeedback.focus,border: Self.cream)
    arrow(143,255,143,296,GastricFeedback.focus)
    disc(143,291 - 33 * output,2 + 3 * output,GastricFeedback.focus,border: Self.cream)
    disc(143,308,3 + 4 * output,GastricFeedback.acid,border: Self.cream); label("gastric_acid_story_output",219,312,145)
    line(128,308,117,308,GastricFeedback.acid,1.4); stroke(GastricFeedback.feedbackReturn,GastricFeedback.acid,1 + output)
    line(97,102,89,102,GastricFeedback.acid,1.5); line(97,102,93,109,GastricFeedback.acid,1.5)
  }
}
