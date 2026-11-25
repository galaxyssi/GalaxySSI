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
    case .diaphragmDisplacement:
      return [control("diaphragm-descent", "descent", 0...30, 12, "mm", digits: 0),
        control("diaphragm-projected-area", "area", 100...250, 180, "cm\u{00b2}", digits: 0)]
    case .cardiacPhaseTime:
      return [control("cardiac-phase-time-rate", "rate", 50...150, 75, "bpm", digits: 0),
        control("cardiac-phase-time-filling-percent", "filling_percent", 30...70, 50, "%", digits: 0)]
    case .visualAngle:
      return [control("visual-angle-width", "width", 1...20, 10, "cm", digits: 0),
        control("visual-angle-distance", "distance", 50...150, 100, "cm", digits: 0)]
    case .serialAbsorption:
      return [control("serial-absorption-stage-a", "stage_a", 0...100, 40, "%", digits: 0),
        control("serial-absorption-stage-b", "stage_b", 0...100, 50, "%", digits: 0)]
    case .hormoneSignal:
      return [control("hormone-signal-half-life", "half_life", 10...40, 20, "", scale: 10, digits: 1),
        control("hormone-signal-elapsed", "elapsed", 0...80, 40, "", scale: 10, digits: 1)]
    case .immuneComposition:
      return [control("immune-composition-sample-size", "sample_size", 1...5, 2, "cells", scale: 0.01, digits: 0),
        control("immune-composition-selected-percent", "selected_percent", 0...100, 25, "%", digits: 0)]
    case .ductTransit:
      return [control("duct-transit-length", "length", 4...24, 12, "LU", digits: 0),
        control("duct-transit-speed", "speed", 10...50, 25, "LU/TU", scale: 10, digits: 1)]
    case .oviductCiliaryCycles:
      return [control("oviduct-ciliary-cycles-rate", "rate", 4...10, 5, "Hz", digits: 0),
        control("oviduct-ciliary-cycles-time", "time", 0...20, 15, "s", scale: 10, digits: 1)]
    case .kneeMoment:
      return [control("knee-moment-force", "force", 0...20, 10, "N", digits: 0),
        control("knee-moment-arm", "arm", 0...6, 4, "cm", digits: 0)]
    case .arterialContinuity:
      return [control("arterial-lumen-diameter", "diameter", 10...40, 24, "mm", digits: 0),
        control("arterial-volume-flow", "flow", 0...150, 70, "mL/s", digits: 0)]
    case .glialCapacitance:
      return [control("glial-capacitance-thickness", "thickness", 10...40, 20, "\u{00d7}", scale: 20),
        control("glial-capacitance-area", "area", 10...40, 20, "\u{00d7}", scale: 20)]
    case .colonicWaterBalance:
      return [control("colonic-water-starting-volume", "starting_volume", 100...1000, 500, "mL", digits: 0),
        control("colonic-water-net-absorbed", "net_absorbed", 0...100, 80, "%", digits: 0)]
    case .lymphParticleTransport:
      return [control("lymph-particle-transport-flow", "flow", 0...20, 8, "mL/min", scale: 4),
        control("lymph-particle-transport-concentration", "concentration", 0...24, 12, "\u{00b5}g/mL", scale: 4)]
    case .endocrineDilution:
      return [control("endocrine-dilution-tracer-amount", "amount", 1...12, 6, "TU", digits: 0),
        control("endocrine-dilution-final-volume", "volume", 2...12, 4, "VU", digits: 0)]
    case .boneSection:
      return [control("bone-section-force", "force", 0...120, 60, "N", digits: 0),
        control("bone-section-wall-thickness", "wall_thickness", 10...30, 20, "mm", scale: 10, digits: 1)]
    case .retinalConvergence:
      return [control("retinal-convergence-samples", "samples", 1...16, 8, "", digits: 0),
        control("retinal-convergence-lit-percent", "lit_percent", 0...100, 25, "%", digits: 0)]
    case .muscleShortening:
      return [control("muscle-shortening-count", "count", 200...2000, 1000, "", digits: 0),
        control("muscle-shortening-per-sarcomere", "per_sarcomere", 0...50, 25, "\u{00b5}m", scale: 100)]
    case .keratinGrowth:
      return [control("keratin-growth-time", "time", 0...20, 8, "d", digits: 0),
        control("keratin-growth-rate", "rate", 2...8, 5, "mm/d", scale: 10, digits: 1)]
    case .bladderExpansion:
      return [control("bladder-starting-volume", "initial", 50...150, 100, "mL", digits: 0),
        control("bladder-added-volume", "added", 0...300, 100, "mL", digits: 0)]
    case .vestibularTilt:
      return [control("vestibular-tilt-lateral", "lateral", 0...100, 30, "g", scale: 100),
        control("vestibular-tilt-downward", "downward", 50...150, 100, "g", scale: 100)]
    case .airwayCiliaryClearance:
      return [control("airway-ciliary-clearance-cycles", "cycles", 0...24, 12, "cycles", digits: 0),
        control("airway-ciliary-clearance-advance", "advance", 0...25, 15, "u/cycle", scale: 10, digits: 1)]
    case .gastricLiquidEmptying:
      return [control("gastric-liquid-removal", "removal", 5...40, 20, "%", digits: 0),
        control("gastric-liquid-intervals", "intervals", 0...10, 4, "", digits: 0)]
    case .bileStorage:
      return [control("bile-storage-marker-amount", "marker_amount", 1...12, 6, "TU", digits: 0),
        control("bile-storage-water-removed", "water_removed", 0...8, 6, "VU", digits: 0)]
    case .thoracicCrossSection:
      return [control("thoracic-cross-section-front-to-back", "front_to_back", 12...24, 18, "cm", digits: 0),
        control("thoracic-cross-section-side-to-side", "side_to_side", 24...36, 30, "cm", digits: 0)]
    case .plateletFragmentCount:
      return [control("platelet-fragment-count-icons", "icons", 0...8, 4, "", digits: 0),
        control("platelet-fragment-count-tiles-per-icon", "tiles_per_icon", 0...6, 3, "", digits: 0)]
    case .boneRemodelingBalance:
      return [control("bone-remodeling-resorbed", "resorbed", 0...20, 10, "a.u.", digits: 0),
        control("bone-remodeling-formed", "formed", 0...20, 10, "a.u.", digits: 0)]
    case .cutaneousSebum:
      return [control("cutaneous-sebum-mass", "mass", 20...80, 40, "\u{00b5}g", digits: 0),
        control("cutaneous-sebum-area", "area", 4...16, 8, "cm\u{00b2}", digits: 0)]
    }
  }
}
