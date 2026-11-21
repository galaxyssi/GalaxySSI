import Foundation

/// Synthetic teaching inputs only. This model has no archive, observation, file or transport dependency.
struct GalaxySSIHealthAtlasPhysiology: Equatable, Sendable {
  struct Input: Equatable, Sendable {
    let key: String
    let range: ClosedRange<Int>
    let initial: Int
    var scale: Double = 1
    let unit: String
  }
  enum Kind: String, CaseIterable, Sendable {
    case ventilation, renal, potassium
    var inputs: [Input] {
      switch self {
      case .ventilation:
        return [.init(key: "rate", range: 6...30, initial: 12, unit: "/min"),
          .init(key: "tidal", range: 200...900, initial: 500, unit: "mL"),
          .init(key: "model_dead_space", range: 0...200, initial: 150, unit: "mL")]
      case .renal:
        return [.init(key: "model_filtered", range: 0...200, initial: 100, unit: "mg/min"),
          .init(key: "model_reabsorbed", range: 0...100, initial: 90, unit: "%"),
          .init(key: "model_secreted", range: 0...100, initial: 10, unit: "mg/min")]
      case .potassium:
        return [.init(key: "model_outside", range: 10...200, initial: 40, scale: 10, unit: "mmol/L"),
          .init(key: "model_inside", range: 50...200, initial: 140, unit: "mmol/L")]
      }
    }
    var axis: Int { self == .potassium ? 0 : 1 }
    var unit: String { self == .ventilation ? "L/min" : self == .renal ? "mg/min" : "mV" }
    var bounds: ClosedRange<Double> { self == .ventilation ? 0...27 : self == .renal ? 0...300 : -150...0 }
    var source: URL {
      switch self {
      case .ventilation: return URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-3-the-process-of-breathing")!
      case .renal: return URL(string: "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-6-tubular-reabsorption")!
      case .potassium: return URL(string: "https://neurotext.library.stonybrook.edu/C2/C2_4/C2_4.html")!
      }
    }
    static func forEntry(_ id: String) -> Self? {
      switch id {
      case "respiratory", "lungs", "alveoli": return .ventilation
      case "urinary", "kidneys", "nephron", "renal-tubules", "collecting-ducts", "cell-proximal-tubular-cell",
           "cell-distal-tubular-cell", "cell-collecting-duct-principal-cell", "cell-collecting-duct-intercalated-cell": return .renal
      case "nervous", "brain", "spinal-cord", "cell-neuron", "cell-olfactory-receptor-neuron": return .potassium
      default: return nil
      }
    }
  }
  struct Point: Identifiable {
    let id: Int
    let x: Double
    let y: Double
  }
  let kind: Kind
  let inputs: [Int]

  init(kind: Kind) { self.kind = kind; inputs = kind.inputs.map(\.initial) }
  init?(kind: Kind, inputs: [Int]) {
    guard inputs.count == kind.inputs.count, inputs.indices.allSatisfy({ kind.inputs[$0].range.contains(inputs[$0]) }) else { return nil }
    self.kind = kind; self.inputs = inputs
  }
  func input(_ index: Int) -> Double { Double(inputs[index]) / kind.inputs[index].scale }
  func changing(_ index: Int, to value: Int) -> Self? {
    guard inputs.indices.contains(index) else { return nil }
    var changed = inputs; changed[index] = value
    return Self(kind: kind, inputs: changed)
  }
  var result: Double { evaluate(inputs.indices.map(input)) }
  var companionValue: Double {
    switch kind {
    case .ventilation: return input(0) * input(1) / 1000
    case .renal: return input(0) * input(1) / 100
    case .potassium: return input(0) / input(1)
    }
  }
  var axisRange: ClosedRange<Double> {
    let spec = kind.inputs[kind.axis]
    return Double(spec.range.lowerBound) / spec.scale...Double(spec.range.upperBound) / spec.scale
  }
  func resultAt(_ x: Double) -> Double? {
    guard x.isFinite, axisRange.contains(x) else { return nil }
    return evaluate(inputs.indices.map { $0 == kind.axis ? x : input($0) })
  }
  var response: [Point] {
    (0...120).map { step in
      let x = axisRange.lowerBound + (axisRange.upperBound - axisRange.lowerBound) * Double(step) / 120
      return Point(id: step, x: x, y: resultAt(x)!)
    }
  }
  private func evaluate(_ values: [Double]) -> Double {
    switch kind {
    case .ventilation: return values[0] * (values[1] - values[2]) / 1000
    case .renal: return values[0] * (1 - values[1] / 100) + values[2]
    case .potassium: return Self.potassiumPotential(outside: values[0], inside: values[1])!
    }
  }
  static func potassiumPotential(outside: Double, inside: Double) -> Double? {
    guard outside.isFinite, inside.isFinite, outside > 0, inside > 0 else { return nil }
    // Nernst for z = +1 at 310.15 K, volts converted to millivolts. Log difference avoids ratio underflow.
    return 8.31446261815324 * 310.15 / 96485.33212 * 1000 * (log(outside) - log(inside))
  }
  static func restore(_ id: String, inputs: [Int]?) -> Self? {
    guard let kind = Kind.forEntry(id), let inputs else { return nil }
    return Self(kind: kind, inputs: inputs)
  }
  static func resolved(_ id: String, inputs: [Int]?, legacyVentilation: [Double]? = nil) -> Self? {
    guard let kind = Kind.forEntry(id) else { return nil }
    if let restored = restore(id, inputs: inputs) { return restored }
    if kind == .ventilation, ["lungs", "respiratory"].contains(id), let values = legacyVentilation, values.count == 2,
       values.enumerated().allSatisfy({ index, value in
         value.isFinite && value.rounded() == value && value >= Double(kind.inputs[index].range.lowerBound) &&
           value <= Double(kind.inputs[index].range.upperBound)
       }), let migrated = Self(kind: kind, inputs: values.map(Int.init) + [150]) { return migrated }
    return Self(kind: kind)
  }
}
