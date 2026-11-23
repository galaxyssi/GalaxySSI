import SwiftUI

extension GalaxySSIHealthAtlasSignalDrawing {
  func synapticScene(_ motion: Motion) {
    if motion.chapter < 2 { neuron(receiving: motion.chapter == 0, t: motion.fraction) }
    else { synapse(chapter: motion.chapter, t: motion.fraction) }
  }
  private func neuron(receiving: Bool, t: Double) {
    plate("HealthAtlasNeuron", 75, 12, 275, 312)
    if receiving {
      for i in Motion.dendrites.indices {
        trail(Motion.dendrites[i], Motion.loop(t * 1.22 + Double(i) * 0.28), Self.blue, length: Motion.dendriteLengths[i])
      }
      ring(154, 138, 7 + 4.5 * sin(t * .pi), Self.gold)
      leader(52, 48, 117, 61, "neuro_dendrites", Self.blue); leader(63, 211, 154, 138, "neuro_initial", Self.gold)
    } else {
      trail(Motion.axon, t, Self.gold, length: Motion.axonLength)
      leader(70, 223, 190, 191, "neuro_axon", Self.gold); leader(253, 331, 240, 281, "neuro_terminal", Self.coral)
    }
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
      for i in 0...4 {
        let f = Motion.loop(t * 1.29 + Double(i) / 5); dot(312 - f * 92, Double(151 + 10 * (i % 2)), 3.6, Self.blue)
      }
      rounded(262, 143, 273, 148, 2, Self.blue); rounded(262, 162, 273, 167, 2, Self.blue)
      label(297, 125, "neuro_calcium_ions")
    case 3:
      if !fusion { vesicle(180, 140 + 21 * min(1, max(0, t / 0.35))) }
      else {
        for i in 0...4 {
          let f = Motion.synapticRelease(t, index: i); dot(180 + Double(i - 2) * 18 * f, 174 + 61 * f, 3.8, Self.violet)
        }
      }
      leader(277, 201, 208, 219, "neuro_transmitter", Self.violet)
    default:
      ring(180, 271, 9 + t * 22, Self.gold)
      for i in 0...4 {
        let f = Motion.loop(t * 0.95 + Double(i) / 5), x = 149 + Double(i) * 36 * 0.45 + 67 * f
        dot(x, 229 - 26 * f, 3.5 - 0.8 * f, Self.violet)
      }
      leader(303, 193, 230, 234, "neuro_receptor", Self.teal)
    }
    leader(134, 48, 137, 86, "neuro_terminal", Self.coral); label(180, 336, "neuro_next")
  }
  private func vesicle(_ x: Double, _ y: Double) {
    oval(x, y, 12.5, 12.5, 0xEEE2EB); ring(x, y, 12.5, Self.violet)
    dot(x - 4, y + 3, 2.5, Self.violet); dot(x + 4, y - 2, 2.5, Self.violet)
  }
}
