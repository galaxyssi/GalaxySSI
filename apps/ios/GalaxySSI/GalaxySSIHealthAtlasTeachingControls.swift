import Foundation

extension GalaxySSIHealthAtlasTeachingModel {
  var controls: [Control] {
    func control(_ key: String, _ label: String, _ range: ClosedRange<Int>, _ initial: Int,
                 _ unit: String, scale: Double = 1, digits: Int = 2) -> Control {
      Control(input: .init(key: key, range: range, initial: initial, scale: scale, unit: unit),
        label: resourcePrefix + "_" + label, digits: digits)
    }
    switch self {
    case .capillaryExchange:
      return [control("capillary-exchange-ps", "ps", 0...40, 20, "mL/min"),
        control("capillary-exchange-flow", "flow", 5...80, 20, "mL/min")]
    case .valveFlux:
      return [control("valve-flux-area", "area", 10...50, 25, "cm\u{00b2}", scale: 10, digits: 1),
        control("valve-flux-speed", "speed", 0...100, 50, "cm/s", digits: 0)]
    case .glomerularFiltration:
      return [control("glomerular-filtration-capillary-hydrostatic", "capillary_hydrostatic", 40...65, 52, "mmHg", digits: 0),
        control("glomerular-filtration-capsular-hydrostatic", "capsular_hydrostatic", 8...20, 12, "mmHg", digits: 0),
        control("glomerular-filtration-capillary-oncotic", "capillary_oncotic", 18...35, 28, "mmHg", digits: 0),
        control("glomerular-filtration-kf", "coefficient", 5...50, 25, "nL/(min\u{00b7}mmHg)", scale: 10, digits: 1)]
    case .skinWaterBarrier:
      return [control("skin-water-diffusivity", "diffusivity", 10...30, 20, "\u{00d7}", scale: 20),
        control("skin-water-gradient", "gradient", 0...30, 20, "\u{00d7}", scale: 20),
        control("skin-water-thickness", "thickness", 10...30, 20, "\u{00d7}", scale: 20)]
    case .salivaryDelivery:
      return [control("salivary-parotid-flow", "parotid", 0...24, 12, "DU/min", scale: 4),
        control("salivary-submandibular-flow", "submandibular", 0...24, 16, "DU/min", scale: 4),
        control("salivary-sublingual-flow", "sublingual", 0...12, 4, "DU/min", scale: 4)]
    case .tendonElongation:
      return [control("tendon-elongation-force", "force", 0...12, 6, "N", digits: 0),
        control("tendon-elongation-length", "length", 20...80, 50, "mm", digits: 0),
        control("tendon-elongation-area", "area", 30...60, 40, "mm\u{00b2}", scale: 10, digits: 1),
        control("tendon-elongation-modulus", "modulus", 50...100, 75, "N/mm\u{00b2}", scale: 0.1, digits: 0)]
    case .airwaySplit:
      return [control("airway-split-total-flow", "total_flow", 10...60, 30, "L/s", scale: 100),
        control("airway-split-selected-resistance", "selected_resistance", 10...40, 15, "cmH\u{2082}O\u{00b7}s/L", scale: 10, digits: 1),
        control("airway-split-other-resistance", "other_resistance", 10...40, 30, "cmH\u{2082}O\u{00b7}s/L", scale: 10, digits: 1)]
    case .peristalticTravel:
      return [control("peristaltic-travel-speed", "speed", 10...40, 25, "cm/s", scale: 10, digits: 1),
        control("peristaltic-travel-time", "time", 0...25, 20, "s", scale: 10, digits: 1)]
    case .cochlearFrequency:
      return [control("cochlear-frequency-position", "position", 0...100, 50, "", scale: 100)]
    }
  }
}
