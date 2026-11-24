import SwiftUI

private typealias AutonomicCourseRoutes = GalaxySSIHealthAtlasAutonomicRoutes
private typealias AutonomicCourseMotion = GalaxySSIHealthAtlasAutonomicMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func autonomicOutput(_ t: Double) {
    autonomicAnatomy(true)
    autonomicFiber(AutonomicCourseRoutes.symFirst, 0x98602F, first: true)
    autonomicFiber(AutonomicCourseRoutes.vagFirst, 0x367B73, first: true)
    autonomicSegment(AutonomicCourseRoutes.symFirst, AutonomicCourseMotion.output(t, vagal: false), 0x98602F)
    autonomicSegment(AutonomicCourseRoutes.vagFirst, AutonomicCourseMotion.output(t, vagal: true), 0x367B73)
    disc(AutonomicCourseRoutes.spinalX, AutonomicCourseRoutes.spinalY, 4.3, 0x98602F, border: Self.cream)
    disc(AutonomicCourseRoutes.medullaX, AutonomicCourseRoutes.medullaY, 4.3, 0x367B73, border: Self.cream)
    autonomicTarget(0)
  }
  func autonomicSympathetic(_ t: Double) {
    autonomicAnatomy(true)
    autonomicFiber(AutonomicCourseRoutes.symFirst, 0x98602F, first: true)
    autonomicFiber(AutonomicCourseRoutes.symSecond, 0x98602F, first: false)
    autonomicSegment(AutonomicCourseRoutes.symFirst, AutonomicCourseMotion.sympatheticApproach(t), 0x98602F)
    autonomicSegment(AutonomicCourseRoutes.symSecond, AutonomicCourseMotion.sympatheticExit(t), 0x98602F)
    disc(AutonomicCourseRoutes.spinalX, AutonomicCourseRoutes.spinalY, 3.9, 0x98602F, border: Self.cream)
    autonomicGanglion(AutonomicCourseRoutes.thoracicX, AutonomicCourseRoutes.thoracicY, 0x98602F, AutonomicCourseMotion.sympatheticHandoff(t))
    autonomicTarget(0)
  }
  func autonomicCardiac(_ t: Double) {
    let arrival = AutonomicCourseMotion.cardiacArrival(t)
    var local = context
    local.translateBy(x: 139, y: 140); local.scaleBy(x: 1.37, y: 1.37)
    local.translateBy(x: -AutonomicCourseRoutes.saX, y: -AutonomicCourseRoutes.saY)
    let art = copy(local)
    art.autonomicHeart()
    art.autonomicFiber(AutonomicCourseRoutes.symSecond, 0x98602F, first: false)
    art.autonomicSegment(AutonomicCourseRoutes.symSecond, arrival, 0x98602F)
    art.autonomicGanglion(AutonomicCourseRoutes.thoracicX, AutonomicCourseRoutes.thoracicY, 0x98602F, 0)
    art.autonomicTarget(min(1, max(0, (arrival - 0.83) / 0.17)))
    label("autonomic_relay_story_art_beat_spacing", 180, 273, 162)
    autonomicBeatMarks(t, AutonomicCourseMotion.beatSpacing(t))
  }
  func autonomicVagal(_ t: Double) {
    autonomicAnatomy(false)
    autonomicFiber(AutonomicCourseRoutes.vagFirst, 0x367B73, first: true)
    autonomicFiber(AutonomicCourseRoutes.vagSecond, 0x367B73, first: false)
    autonomicSegment(AutonomicCourseRoutes.vagFirst, AutonomicCourseMotion.vagalDescent(t), 0x367B73)
    let exit = AutonomicCourseMotion.vagalExit(t)
    autonomicSegment(AutonomicCourseRoutes.vagSecond, exit, 0x367B73)
    disc(AutonomicCourseRoutes.medullaX, AutonomicCourseRoutes.medullaY, 3.9, 0x367B73, border: Self.cream)
    autonomicGanglion(AutonomicCourseRoutes.cardiacX, AutonomicCourseRoutes.cardiacY, 0x367B73, AutonomicCourseMotion.vagalHandoff(t))
    autonomicTarget(min(1, max(0, (exit - 0.76) / 0.24)))
  }
  func autonomicCompare(_ t: Double) {
    var local = context
    local.translateBy(x: 271, y: 177); local.scaleBy(x: 0.73, y: 0.73)
    local.translateBy(x: -AutonomicCourseRoutes.saX, y: -AutonomicCourseRoutes.saY)
    copy(local).autonomicHeart()
    autonomicCompareRoute(AutonomicCourseRoutes.compareSymFirst, AutonomicCourseRoutes.compareSymSecond,
      107, 112, 0x98602F, split: 0.29, phase: AutonomicCourseMotion.ongoing(t, vagal: false))
    autonomicCompareRoute(AutonomicCourseRoutes.compareVagFirst, AutonomicCourseRoutes.compareVagSecond,
      216, 237, 0x367B73, split: 0.64, phase: AutonomicCourseMotion.ongoing(t, vagal: true))
    disc(271, 177, 4.5, 0x795777, border: Self.cream)
    label("autonomic_relay_story_art_sympathetic", 101, 52, 170)
    label("autonomic_relay_story_art_parasympathetic", 112, 304, 185)
  }
}
