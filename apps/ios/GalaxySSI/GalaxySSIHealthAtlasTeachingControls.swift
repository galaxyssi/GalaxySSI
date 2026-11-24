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
    case .ureterDelivery:
      return [control("ureter-delivery-pushes", "pushes", 0...6, 3, "", digits: 0),
        control("ureter-delivery-volume", "per_push", 5...30, 20, "mL", scale: 10, digits: 1)]
    case .cornealRefraction:
      return [control("corneal-refraction-incident-angle", "incident_angle", 0...80, 40, "\u{00b0}", digits: 0),
        control("corneal-refraction-medium-index", "medium_index", 130...145, 134, "", scale: 100)]
    case .externalEarResonance:
      return [control("external-ear-resonance-length", "length", 10...50, 20, "cm", digits: 0),
        control("external-ear-resonance-speed", "speed", 330...360, 343, "m/s", digits: 0)]
    case .neuralRelayDelays:
      return [control("neural-relay-count", "count", 1...8, 3, "", digits: 0),
        control("neural-relay-delay", "per_relay", 5...25, 15, "ms", scale: 10, digits: 1)]
    case .biliaryFlowTally:
      return [control("biliary-flow-tally-per-channel", "per_channel", 0...24, 10, "VU/min", scale: 4),
        control("biliary-flow-tally-channel-count", "channel_count", 1...8, 4, "", digits: 0)]
    case .parathyroidSignalOccupancy:
      return [control("parathyroid-occupancy-signal", "signal", 0...120, 20, "", scale: 10, digits: 1),
        control("parathyroid-occupancy-half-point", "half_point", 5...60, 20, "", scale: 10, digits: 1)]
    case .follicleSurface:
      return [control("follicle-surface-cavity-diameter", "cavity_diameter", 4...14, 8, "mm", digits: 0),
        control("follicle-surface-shell-thickness", "shell_thickness", 2...10, 5, "mm", scale: 10, digits: 1)]
    case .jointArticularArc:
      return [control("joint-articular-arc-angle", "angle", 0...90, 45, "\u{00b0}", digits: 0),
        control("joint-articular-arc-radius", "radius", 10...40, 25, "mm", digits: 0)]
    case .sweatDuctBalance:
      return [control("sweat-duct-coil-sodium", "coil_sodium", 120...160, 140, "nmol", digits: 0),
        control("sweat-duct-net-reabsorbed", "net_reabsorbed", 0...90, 75, "%", digits: 0)]
    case .vocalCycles:
      return [control("vocal-cycle-frequency", "frequency", 60...240, 140, "Hz", digits: 0),
        control("vocal-cycle-duration", "duration", 5...30, 20, "ms", digits: 0)]
    case .vertebralSeries:
      return [control("vertebral-series-pad-count", "pad_count", 1...8, 4, "", digits: 0),
        control("vertebral-series-shortening-per-pad", "shortening_per_pad", 0...100, 25, "mm", scale: 100)]
    case .oralMarkerDilution:
      return [control("oral-marker-dilution-marker-stream", "marker_stream", 2...8, 4, "VU", digits: 0),
        control("oral-marker-dilution-added-water", "added_water", 0...12, 4, "VU", digits: 0)]
    case .olfactorySurfaceRetention:
      return [control("olfactory-marker-total", "total", 20...100, 80, "a.u.", digits: 0),
        control("olfactory-mucus-side-share", "mucus_share", 0...100, 35, "%", digits: 0)]
    case .circadianLightWindow:
      return [control("circadian-light-window-period", "period", 12...30, 24, "h", digits: 0),
        control("circadian-light-window-elapsed", "elapsed", 0...48, 30, "h", digits: 0)]
    case .adiposeVolumeShare:
      return [control("adipose-volume-share-radius-ratio", "radius_ratio", 40...98, 90, "", scale: 100),
        control("adipose-volume-share-cell-percent", "cell_percent", 20...70, 60, "%", digits: 0)]
    case .thymicBranching:
      return [control("thymic-branching-starting-tally", "starting_tally", 1...10, 4, "tiles", scale: 0.05, digits: 0),
        control("thymic-branching-selected-percent", "selected_percent", 0...20, 7, "%", scale: 0.2, digits: 0)]
    case .gastricPrecursorBalance:
      return [control("gastric-precursor-amount", "amount", 0...20, 12, "MU", digits: 0),
        control("gastric-precursor-converted-percent", "converted_percent", 0...100, 35, "%", digits: 0)]
    case .melaninDistribution:
      return [control("melanin-distribution-packet-units", "packet_units", 0...24, 12, "PPU", digits: 0),
        control("melanin-distribution-recipient-cells", "recipient_cells", 2...8, 4, "", digits: 0)]
    case .placentalMarker:
      return [control("placental-marker-amount", "amount", 40...120, 80, "a.u.", digits: 0),
        control("placental-marker-equilibration", "equilibration", 0...100, 50, "%", digits: 0)]
    case .renalTubuleRetention:
      return [control("renal-tubule-retention-segment-a", "segment_a", 0...80, 40, "%", digits: 0),
        control("renal-tubule-retention-segment-b", "segment_b", 0...80, 25, "%", digits: 0)]
    case .merkelContact:
      return [control("merkel-contact-force", "force", 10...80, 40, "mN", digits: 0),
        control("merkel-contact-radius", "radius", 10...40, 20, "mm", scale: 10, digits: 1)]
    case .toothEnamelSection:
      return [control("tooth-enamel-section-thickness", "thickness", 5...20, 10, "mm", scale: 10, digits: 1),
        control("tooth-enamel-section-radius", "radius", 30...60, 40, "mm", scale: 10, digits: 1)]
    case .mucosalSampling:
      return [control("mucosal-sampling-selected-tiles", "selected_tiles", 1...12, 3, "", digits: 0),
        control("mucosal-sampling-unselected-tiles", "unselected_tiles", 1...12, 9, "", digits: 0)]
    case .mammaryDuctDelivery:
      return [control("mammary-duct-secreted-volume", "secreted_volume", 4...12, 8, "VU", digits: 0),
        control("mammary-duct-displaced-share", "displaced_share", 0...100, 60, "%", digits: 0)]
    case .rectalReservoir:
      return [control("rectal-reservoir-initial-volume", "initial_volume", 20...200, 120, "mL", digits: 0),
        control("rectal-reservoir-release-share", "release_share", 0...100, 40, "%", digits: 0)]
    case .stromalMatrix:
      return [control("stromal-matrix-added-mass", "added_mass", 0...20, 6, "MU", digits: 0),
        control("stromal-matrix-initial-mass", "initial_mass", 0...40, 12, "MU", digits: 0)]
    case .mucusFilmThickness:
      return [control("mucus-film-volume", "volume", 4...24, 12, "u\u{00b3}", digits: 0),
        control("mucus-film-area", "area", 2...12, 6, "u\u{00b2}", digits: 0)]
    }
  }
}
