import SwiftUI

struct GalaxySSIHealthAtlasSensorimotorView: View {
  let story: GalaxySSIHealthAtlasFunctionCatalogue.Story
  let phase: Double
  let language: String
  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 360
      guard scale > 0 else { return }
      var local = context
      local.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 360 * scale) / 2)
      local.scaleBy(x: scale, y: scale)
      let art = GalaxySSIHealthAtlasIllustratedDrawing(context: local, language: language)
      art.gradient(Path(roundedRect: CGRect(x: 0, y: 0, width: 360, height: 360), cornerRadius: 8), 0, 360, 0xE8F4F3, 0xFBF0DF)
      art.sensorimotorScene(.init(step: story.chapter(phase), fraction: story.fraction(phase)))
    }.aspectRatio(1, contentMode: .fit).clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(GalaxySSIHealthAtlasFunctionText.get(story.chapters[story.chapter(phase)].caption, language))
      .accessibilityIdentifier("atlas-function-cerebral-sensorimotor-art")
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sensorimotorScene(_ frame: GalaxySSIHealthAtlasSensorimotorMotion.Frame) {
    typealias Motion = GalaxySSIHealthAtlasSensorimotorMotion
    typealias Routes = GalaxySSIHealthAtlasSensorimotorRoutes
    let t = frame.t, x = frame.finger.x, y = frame.finger.y
    sensorimotorAnatomy()
    line(16, 228, 344, 228, 0xCAD2C8, 1)
    sensorimotorTarget()
    if frame.step == 2 { sensorimotorReach(Motion.preview(t), dashed: true) }
    if (3...4).contains(frame.step) { sensorimotorReach(frame.reach, dashed: false) }
    sensorimotorArm(frame)
    switch frame.step {
    case 0: sensorimotorPulse(Routes.centralSulcus, Motion.tissueTrace(t), 0x8A5968)
    case 1:
      sensorimotorInput(frame.position.x, frame.position.y, Motion.position(t))
      sensorimotorSignal(Routes.touchPath, Motion.touch(t), 0x386C8B)
      sensorimotorCue(x, y, 0x386C8B)
    case 2:
      sensorimotorSignal(Routes.plansAcross, Motion.planning(t), 0x4D796A)
      sensorimotorSignal(Routes.plansBack, Motion.reply(t), 0xA3723C)
    case 3: sensorimotorSignal(Routes.commandPath, Motion.command(t), 0x9B4945)
    case 4:
      sensorimotorInput(frame.position.x, frame.position.y, Motion.ongoingInput(t))
      sensorimotorSignal(Routes.commandPath, Motion.ongoingOutput(t), 0x9B4945)
      if frame.reach > 0.96 { sensorimotorCue(x, y, 0x386C8B) }
    default: break
    }
    sensorimotorStageLabels(frame.step)
    sensorimotorAnatomyLabels()
    sensorimotorLeader("cerebral_sensorimotor_story_cup", 307, 344, 76, 307, 331, 307, 315)
  }
}
