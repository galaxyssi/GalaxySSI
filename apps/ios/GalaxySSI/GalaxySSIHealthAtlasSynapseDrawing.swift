import SwiftUI

extension GalaxySSIHealthAtlasSignalDrawing {
  func synapticScene(_ motion: Motion) {
    if motion.chapter < 2 { neuron(receiving: motion.chapter == 0, t: motion.fraction) }
    else { synapse(chapter: motion.chapter, t: motion.fraction) }
  }
  private func neuron(receiving: Bool, t: Double) {
    var local = context
    local.translateBy(x: 37, y: 2); local.scaleBy(x: 0.79, y: 0.79)
    let neuron = copy(local)
    neuron.plate("HealthAtlasNeuron", 75, 12, 275, 312)
    if receiving {
      for i in Motion.dendrites.indices {
        neuron.trail(Motion.dendrites[i], Motion.loop(t * 1.22 + Double(i) * 0.28), Self.blue, length: Motion.dendriteLengths[i])
      }
      let input = Motion.gradedInput(t)
      neuron.ring(154, 138, 6 + 9 * input, input >= 0.58 ? Self.gold : Self.blue)
      neuron.leader(52, 48, 117, 61, "neuro_dendrites", Self.blue)
      neuron.leader(63, 211, 154, 138, "neuro_initial", Self.gold)
    } else {
      neuron.trail(Motion.axon, t, Self.gold, length: Motion.axonLength)
      neuron.leader(70, 223, 190, 191, "neuro_axon", Self.gold)
      neuron.leader(253, 331, 240, 281, "neuro_terminal", Self.coral)
    }
    if receiving { gradedPotential(t) } else { membraneRelay(t) }
  }
  private func synapse(chapter: Int, t: Double) {
    let fusion = chapter == 3 && t > 0.35
    var terminal = Path(); terminal.move(to: CGPoint(x: 138, y: 74))
    terminal.addCurve(to: CGPoint(x: 89, y: 145), control1: CGPoint(x: 88, y: 77), control2: CGPoint(x: 79, y: 108))
    terminal.addQuadCurve(to: CGPoint(x: 132, y: 183), control: CGPoint(x: 95, y: 179)); terminal.addLine(to: CGPoint(x: 160, y: 183))
    if fusion { terminal.addQuadCurve(to: CGPoint(x: 200, y: 183), control: CGPoint(x: 180, y: 141)) }
    terminal.addLine(to: CGPoint(x: 226, y: 183)); terminal.addQuadCurve(to: CGPoint(x: 270, y: 146), control: CGPoint(x: 262, y: 180))
    terminal.addCurve(to: CGPoint(x: 222, y: 74), control1: CGPoint(x: 280, y: 102), control2: CGPoint(x: 256, y: 76)); terminal.closeSubpath()
    gradient(terminal, 73, 185, 0xF8E0CF, 0xD49087); stroke(terminal, Self.coral, 1.5)
    box(70, 245, 290, 312, 22, 246, 317, 0xE0EDE6, 0xADD0C1); line(90, 246, 271, 246, Self.teal, 2.8)
    for x in [139.0, 180, 221] {
      var receptor = Path(); receptor.move(to: CGPoint(x: x - 10, y: 232))
      receptor.addQuadCurve(to: CGPoint(x: x + 10, y: 232), control: CGPoint(x: x, y: 246)); stroke(receptor, Self.teal, 4)
    }
    vesicle(124, 124); vesicle(213, 116)
    switch chapter {
    case 2:
      vesicle(178, 138)
      let open = t > 0.22
      var channel = context
      channel.translateBy(x: 267, y: 147); channel.rotate(by: .degrees(90)); channel.translateBy(x: -267, y: -147)
      copy(channel).gate(267, 147, Self.blue, open: open)
      for i in 0...4 {
        let f = Motion.gateProgress(t, openAt: 0.22 + Double(i) * 0.085, duration: 0.43)
        dot(318 - 99 * f, 147 + Double(i - 2) * 5.5 * abs(1 - f * 2), 3.6, Self.blue)
      }
      label(291, 116, "neuro_calcium_ions")
      if open { arrow(307, 169, 229, 169, Self.blue) }
    case 3:
      if !fusion { vesicle(180, 140 + 21 * min(1, max(0, t / 0.35))) }
      else {
        for i in 0...4 {
          let f = Motion.synapticRelease(t, index: i); dot(180 + Double(i - 2) * 18 * f, 174 + 61 * f, 3.8, Self.violet)
        }
      }
      if fusion { arrow(112, 194, 112, 227, Self.violet) }
      leader(277, 201, 208, 219, "neuro_transmitter", Self.violet)
    default:
      let receptorOpen = (0.24...0.79).contains(t)
      gate(180, 246, Self.teal, open: receptorOpen)
      let binding = Motion.gateProgress(t, openAt: 0.03, duration: 0.21)
      let clearing = Motion.gateProgress(t, openAt: 0.70, duration: 0.26)
      dot(168 + 12 * binding - 50 * clearing, 202 + 29 * binding - 38 * clearing, 4, Self.violet)
      if receptorOpen {
        arrow(180, 250, 180, 281, Self.blue)
        for i in 0...2 {
          let f = Motion.gateProgress(t, openAt: 0.25 + Double(i) * 0.11, duration: 0.27)
          dot(180 + Double(i - 1) * 11 * f, 248 + 41 * f, 3.3, Self.blue)
        }
      }
      if clearing > 0 { arrow(122, 223, 122, 189, Self.violet) }
      label(99, 280, "neuro_sodium_in")
      leader(303, 193, 230, 234, "neuro_receptor", Self.teal)
    }
    leader(134, 48, 137, 86, "neuro_terminal", Self.coral); label(180, 336, "neuro_next")
  }
  private func vesicle(_ x: Double, _ y: Double) {
    oval(x, y, 12.5, 12.5, 0xEEE2EB); ring(x, y, 12.5, Self.violet)
    dot(x - 4, y + 3, 2.5, Self.violet); dot(x + 4, y - 2, 2.5, Self.violet)
  }
}
