import Foundation

extension GalaxySSIHealthAtlasTeachingModel {
  private func accepts(_ values: [Double]) -> Bool {
    let inputs = self.inputs
    return values.count == inputs.count && zip(values, inputs).allSatisfy { value, input in
      value.isFinite && input.scale.isFinite && input.scale > 0 &&
        (Double(input.range.lowerBound) / input.scale...Double(input.range.upperBound) / input.scale).contains(value)
    }
  }
  func evaluate(_ values: [Double]) -> Double? {
    guard accepts(values) else { return nil }
    let result: Double
    switch self {
    case .capillaryExchange: result = -100 * expm1(-values[0] / values[1])
    case .valveFlux: result = values[0] * values[1]
    case .glomerularFiltration: result = max(0, values[0] - values[1] - values[2]) * values[3]
    case .skinWaterBarrier: result = values[0] * values[1] / values[2]
    case .salivaryDelivery: result = values.reduce(0, +)
    case .tendonElongation: result = values[1] * (values[0] / (values[3] * values[2]))
    case .airwaySplit: result = values[0] * values[2] / (values[1] + values[2])
    case .peristalticTravel: result = values[0] * values[1]
    case .cochlearFrequency: result = 165.4 * (pow(10, 2.1 * values[0]) - 0.88)
    case .diaphragmDisplacement: result = values[1] * values[0] / 10
    case .cardiacPhaseTime: result = (60_000 / values[0]) * (values[1] / 100)
    case .visualAngle: result = 2 * atan(values[0] / (2 * values[1])) * 180 / .pi
    case .serialAbsorption: result = 100 - (100 - values[0]) * ((100 - values[1]) / 100)
    case .hormoneSignal: result = 100 * pow(2, -values[1] / values[0])
    case .immuneComposition: result = values[0] * values[1] / 100
    case .ductTransit: result = values[0] / values[1]
    case .oviductCiliaryCycles: result = values[0] * values[1]
    case .kneeMoment: result = values[0] * (values[1] / 100)
    case .arterialContinuity: result = values[1] / (.pi * pow(values[0] / 20, 2))
    case .glialCapacitance: result = values[1] * (log1p(0.5) / log1p(values[0] * 0.5))
    case .colonicWaterBalance: result = values[0] - values[0] * (values[1] / 100)
    case .lymphParticleTransport: result = values[1] * values[0]
    case .endocrineDilution: result = values[0] / values[1]
    case .boneSection: result = values[0] / (.pi * (25 - pow(5 - values[1], 2)))
    case .retinalConvergence: result = values[0] * (values[1] / 100)
    case .muscleShortening: result = values[0] * values[1] / 1000
    case .keratinGrowth: result = values[0] * values[1]
    case .bladderExpansion: result = 100 * (pow(1 + values[1] / values[0], 2.0 / 3.0) - 1)
    case .vestibularTilt: result = atan2(values[0], values[1]) * 180 / .pi
    case .airwayCiliaryClearance: result = values[0] * values[1]
    case .gastricLiquidEmptying: result = 100 * pow(1 - values[0] / 100, values[1])
    case .bileStorage: result = values[0] / (12 - values[1])
    case .thoracicCrossSection: result = .pi * values[0] * values[1] / 4
    // Positive chart samples use Android's half-up whole-icon counts.
    case .plateletFragmentCount: result = values[0].rounded() * values[1].rounded()
    case .boneRemodelingBalance: result = values[1] - values[0]
    case .cutaneousSebum: result = values[0] / values[1]
    case .ureterDelivery: result = values[0].rounded() * values[1]
    case .cornealRefraction: result = asin(sin(values[0] * .pi / 180) / values[1]) * 180 / .pi
    case .externalEarResonance: result = values[1] / (4 * (values[0] / 100))
    case .neuralRelayDelays: result = values[0] * values[1]
    case .biliaryFlowTally: result = values[0] * values[1]
    case .parathyroidSignalOccupancy: result = 100 * (values[0] / (values[0] + values[1]))
    case .follicleSurface: result = 4 * .pi * pow(values[0] / 2 + values[1], 2)
    case .jointArticularArc: result = values[1] * (values[0] * .pi / 180)
    case .sweatDuctBalance: result = values[0] - values[0] * (values[1] / 100)
    case .vocalCycles: result = values[0] * values[1] / 1000
    case .vertebralSeries: result = values[0] * values[1]
    case .oralMarkerDilution: result = 8 / (values[0] + values[1])
    case .olfactorySurfaceRetention: result = values[0] * values[1] / 100
    case .circadianLightWindow: result = 360 * values[1] / values[0]
    case .adiposeVolumeShare: result = values[1] * pow(values[0], 3)
    case .thymicBranching: result = values[0] * values[1] / 100
    case .gastricPrecursorBalance: result = values[0] * (values[1] / 100)
    case .melaninDistribution: result = values[0] / values[1]
    }
    return result.isFinite ? result : nil
  }
  func companion(_ values: [Double]) -> Double? {
    guard accepts(values) else { return nil }
    let result: Double
    switch self {
    case .capillaryExchange: result = 100 * exp(-values[0] / values[1])
    case .valveFlux: result = (values[0] * values[1]) * 0.1
    case .glomerularFiltration: result = values[0] - values[1] - values[2]
    case .skinWaterBarrier: result = values[0] / values[2]
    case .salivaryDelivery: result = values.reduce(0, +) * 5
    case .tendonElongation: result = 100 * (values[0] / (values[3] * values[2]))
    case .airwaySplit: result = values[0] * values[1] / (values[2] + values[1])
    case .peristalticTravel: result = 100 * (values[0] * values[1]) / 10
    case .cochlearFrequency: result = 100 * (1 - values[0])
    case .diaphragmDisplacement: result = values[1] / 10
    case .cardiacPhaseTime: result = 60_000 / values[0]
    case .visualAngle: result = atan(values[0] / (2 * values[1])) * 180 / .pi
    case .serialAbsorption: result = (100 - values[0]) * ((100 - values[1]) / 100)
    case .hormoneSignal: result = 100 - 100 * pow(2, -values[1] / values[0])
    case .immuneComposition: result = values[0] - values[0] * values[1] / 100
    case .ductTransit: result = 1 / values[1]
    case .oviductCiliaryCycles: result = 1000 / values[0]
    case .kneeMoment: result = values[1] / 100
    case .arterialContinuity: result = .pi * pow(values[0] / 20, 2)
    case .glialCapacitance: result = log1p(0.5) / log1p(values[0] * 0.5)
    case .colonicWaterBalance: result = values[0] * (values[1] / 100)
    case .lymphParticleTransport: result = values[1] * values[0] * 5
    case .endocrineDilution: result = values[0]
    case .boneSection: result = .pi * (25 - pow(5 - values[1], 2))
    case .retinalConvergence: result = values[0] * (1 - values[1] / 100)
    case .muscleShortening: result = values[0] * (2.5 - values[1]) / 1000
    case .keratinGrowth: result = 1 / values[1]
    case .bladderExpansion: result = 4 * .pi * pow(cbrt(3 * (values[0] + values[1]) / (4 * .pi)), 2)
    case .vestibularTilt: result = hypot(values[0], values[1])
    case .airwayCiliaryClearance: result = 100 * (values[0] * values[1]) / 60
    case .gastricLiquidEmptying: result = 100 - 100 * pow(1 - values[0] / 100, values[1])
    case .bileStorage: result = values[0]
    case .thoracicCrossSection: result = values[0] / values[1]
    case .plateletFragmentCount: result = values[1].rounded()
    case .boneRemodelingBalance: result = 100 + values[1] - values[0]
    case .cutaneousSebum: result = values[0]
    case .ureterDelivery: result = (6 - values[0].rounded()) * values[1]
    case .cornealRefraction: result = values[0] - asin(sin(values[0] * .pi / 180) / values[1]) * 180 / .pi
    case .externalEarResonance: result = 4 * values[0]
    case .neuralRelayDelays: result = (values[0] - 1) * values[1]
    case .biliaryFlowTally: result = values[0] * values[1] * 4
    case .parathyroidSignalOccupancy: result = 100 - 100 * (values[0] / (values[0] + values[1]))
    case .follicleSurface: result = (4 * .pi / 3) * (pow(values[0] / 2 + values[1], 3) - pow(values[0] / 2, 3))
    case .jointArticularArc: result = values[0] * .pi / 180
    case .sweatDuctBalance: result = values[0] * (values[1] / 100)
    case .vocalCycles: result = 1000 / values[0]
    case .vertebralSeries: result = values[0] * (5 - values[1])
    case .oralMarkerDilution: result = values[0] + values[1]
    case .olfactorySurfaceRetention: result = values[0] - values[0] * values[1] / 100
    case .circadianLightWindow: result = (360 * values[1] / values[0]).truncatingRemainder(dividingBy: 360)
    case .adiposeVolumeShare: result = 100 * pow(values[0], 3)
    case .thymicBranching: result = values[0] - values[0] * values[1] / 100
    case .gastricPrecursorBalance: result = values[0] - values[0] * (values[1] / 100)
    case .melaninDistribution: result = values[0]
    }
    return result.isFinite ? result : nil
  }
}
