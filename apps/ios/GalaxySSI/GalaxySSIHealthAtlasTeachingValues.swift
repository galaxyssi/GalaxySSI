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
    }
    return result.isFinite ? result : nil
  }
}
